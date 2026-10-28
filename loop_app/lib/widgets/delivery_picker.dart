import 'package:flutter/material.dart';

import '../models/country.dart';
import '../models/delivery.dart';
import '../services/boxnow/boxnow.dart';
import '../services/delivery_service.dart';
import 'loop_snackbar.dart';
import '../theme/app_theme.dart';
import 'formatters.dart';
import '../l10n/tr.dart';

/// Odabrana dostava (način + odredište).
class DeliveryChoice {
  const DeliveryChoice(
    this.method,
    this.destination, {
    this.carrier,
    this.savedCarrier,
  });
  final DeliveryMethod method;
  final String? destination;

  /// Odabrani dostavljač (GLS, DPD, pošta…), ako ga ima.
  final Carrier? carrier;

  /// Zapamćeni dostavljač (id) — iz [saved].
  String? get carrierId => carrier?.id ?? savedCarrier;
  final String? savedCarrier;

  /// Zapamćeni odabir korisnika ([AppUser.lastDelivery]) ili null.
  static DeliveryChoice? saved(String? raw) {
    if (raw == null || !raw.contains('|')) return null;
    final i = raw.indexOf('|');
    final m = DeliveryMethod.values
        .where((x) => x.name == raw.substring(0, i))
        .firstOrNull;
    if (m == null) return null;
    // "način|odredište" ili "način|odredište|dostavljač".
    final rest = raw.substring(i + 1);
    final j = rest.lastIndexOf('|');
    final dest = j < 0 ? rest : rest.substring(0, j);
    return DeliveryChoice(
      m,
      dest.isEmpty ? null : dest,
      savedCarrier: j < 0 ? null : rest.substring(j + 1),
    );
  }
}

/// Ikona izbora (dostavljač ili način).
IconData optionIcon(DeliveryOption o) => switch (o.carrier?.kind) {
  CarrierKind.locker => Icons.inventory_2_outlined,
  CarrierKind.post => Icons.local_post_office_outlined,
  CarrierKind.express => Icons.bolt,
  CarrierKind.courier when o.carrier!.international => Icons.public,
  CarrierKind.courier => Icons.local_shipping_outlined,
  null => deliveryIcon(o.method),
};

IconData deliveryIcon(DeliveryMethod m) => switch (m) {
  DeliveryMethod.pickup => Icons.storefront_outlined,
  DeliveryMethod.parcelLocker => Icons.inventory_2_outlined,
  DeliveryMethod.courier => Icons.local_shipping_outlined,
  DeliveryMethod.express => Icons.bolt,
  DeliveryMethod.europe => Icons.public,
  DeliveryMethod.digital => Icons.alternate_email,
};

/// Popis načina dostave + polje za adresu ili odabir paketomata.
/// Javlja promjene preko [onChanged].
class DeliveryPicker extends StatefulWidget {
  const DeliveryPicker({
    super.key,
    this.methods = const [],
    this.options,
    required this.onChanged,
    this.savedAddress,
    this.saved,
    this.onCleared,
    this.size = ParcelSize.small,
  });

  /// Veličina paketa — cijena dostave raste s veličinom.
  final ParcelSize size;

  /// Zapamćeni način dostave — prikaže se kao gotov odabir s gumbom
  /// "Odaberi drugi način dostave".
  final DeliveryChoice? saved;

  /// Kupac je odustao od zapamćenog odabira (bira ispočetka).
  final VoidCallback? onCleared;

  final List<DeliveryMethod> methods;

  /// Izbori s dostavljačima (GLS, DPD…); bez njih samo [methods].
  final List<DeliveryOption>? options;
  final ValueChanged<DeliveryChoice> onChanged;

  /// Zadnja korištena adresa korisnika (predlaže se).
  final String? savedAddress;

  @override
  State<DeliveryPicker> createState() => _DeliveryPickerState();
}

class _DeliveryPickerState extends State<DeliveryPicker> {
  late final List<DeliveryOption> _opts =
      widget.options ?? [for (final m in widget.methods) DeliveryOption(m)];

  /// Ništa nije unaprijed odabrano — kupac sam bira način dostave (osim
  /// kad postoji samo jedan, npr. digitalna dostava).
  late DeliveryOption? _option = _opts.length == 1 ? _opts.first : null;
  DeliveryMethod? get _method => _option?.method;

  /// Zapamćena opcija (isti dostavljač ili način kao prošli put).
  late final DeliveryOption? _savedOption = () {
    final s = widget.saved;
    if (s == null) return null;
    final id = s.carrierId ?? s.method.name;
    return _opts.where((o) => o.id == id).firstOrNull ??
        (s.carrierId == null
            ? _opts
                  .where((o) => o.carrier == null && o.method == s.method)
                  .firstOrNull
            : null);
  }();

  /// Koristi se zapamćeni odabir (dok kupac ne odabere drugi).
  late bool _useSaved = _savedOption != null;

  @override
  void initState() {
    super.initState();
    if (_useSaved) {
      final s = widget.saved!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onChanged(
            DeliveryChoice(
              s.method,
              s.destination,
              carrier: _savedOption!.carrier,
            ),
          );
        }
      });
    } else if (_option != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
    }
  }

  late final _address = TextEditingController(text: widget.savedAddress);

  /// Mreža paketomata odabrane opcije (BOX NOW, GLS, DPD) ili null.
  LockerNetwork? get _network {
    final o = _option;
    if (o == null || !o.method.needsLocker) return null;
    return o.carrier == null
        ? LockerNetwork.boxNow
        : LockerNetwork.ofCarrier(o.carrier);
  }

  /// Država kupca (za kartu i popis paketomata).
  String get _to => _option?.to?.code ?? 'HR';

  /// Paketomat s karte ili popisa (vrijedi samo za svoju mrežu).
  BoxNowLocker? _picked;

  /// Mreže čija se karta nije učitala — za njih se bira s popisa.
  final _mapFailed = <LockerNetwork>{};

  bool get _hasMap {
    final n = _network;
    return n != null && !_mapFailed.contains(n) && LockerMaps.available(n, _to);
  }

  /// Odabrani paketomat; bez karte prvi s popisa (kao dosad).
  BoxNowLocker? get _locker {
    final n = _network;
    if (n == null) return null;
    final p = _picked;
    if (p != null && p.network == n) return p;
    if (_hasMap) return null;
    return demoLockers(n, _to).firstOrNull;
  }

  /// Karta se otvara preko aplikacije; ako je kupac zatvori bez odabira,
  /// gumb ostaje dostupan (novo otvaranje zamjenjuje staro).
  Future<void> _pickOnMap() async {
    final n = _network;
    if (n == null) return;
    final r = await LockerMaps.pick(n, _to);
    if (!mounted) return;
    setState(() {
      switch (r) {
        case BoxNowPicked(:final locker):
          _picked = locker;
        case BoxNowUnavailable():
          // Karta se nije učitala — bira se s popisa.
          _mapFailed.add(n);
          showLoopSnackBar(
            t('{0} karta se nije otvorila — odaberi paketomat s popisa.', [
              n.brand,
            ]),
          );
        case BoxNowClosed():
          break;
      }
    });
    _emit();
  }

  /// Popis paketomata s pretragom (i u APK-u, gdje nema karte).
  Future<void> _pickFromList() async {
    final n = _network;
    if (n == null) return;
    final l = await showModalBottomSheet<BoxNowLocker>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => LockerListSheet(
        network: n,
        lockers: demoLockers(n, _to),
        selected: _locker,
      ),
    );
    if (l == null || !mounted) return;
    setState(() => _picked = l);
    _emit();
  }

  static LockerNetwork? _networkOf(DeliveryOption o) =>
      LockerNetwork.ofCarrier(o.carrier);

  double _cost(DeliveryOption o) => o.carrier != null
      ? DeliveryService.carrierCost(o.carrier!, widget.size)
      : DeliveryService.costFor(o.method, widget.size, country: _country);

  /// Prikazani su i rjeđi načini (ekspres, osobno preuzimanje).
  bool _all = false;

  /// Odabran je način koji je inače skriven iza "Više načina dostave".
  bool get _hiddenSelected {
    final o = _option;
    return o != null && _opts.indexOf(o) >= 2;
  }

  @override
  void dispose() {
    _address.dispose();
    _lockerText.dispose();
    super.dispose();
  }

  /// Država za dostavu u EU.
  String? _country;

  /// Paketomat bez karte (InPost, Foxpost…): upisuje se mjesto.
  bool get _otherLocker =>
      _option?.carrier?.kind == CarrierKind.locker && _network == null;
  final _lockerText = TextEditingController();

  String? get _destination => switch (_method) {
    // Međunarodno: država kupca dodaje se na kraj adrese.
    DeliveryMethod.europe when _option?.to != null =>
      '${_address.text.trim()}, ${_option!.to!.nameHr}',
    DeliveryMethod.europe =>
      _country == null ? _address.text : '${_address.text.trim()}, $_country',
    DeliveryMethod.parcelLocker when _otherLocker => _lockerText.text,
    final m? when m.needsAddress => _address.text,
    final m? when m.needsLocker => _locker?.destination,
    _ => null,
  };

  void _emit() {
    final o = _option;
    if (mounted && o != null) {
      widget.onChanged(
        DeliveryChoice(o.method, _destination, carrier: o.carrier),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    if (_useSaved) {
      final saved = widget.saved!;
      final o = _savedOption!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('delivery-saved'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: LoopColors.surface,
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(color: accent, width: 2),
            ),
            child: Row(
              children: [
                Icon(optionIcon(o), color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.label,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      if (saved.destination != null)
                        Text(
                          saved.destination!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: LoopColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      Text(
                        t('Zapamćeno iz prošle kupnje'),
                        style: TextStyle(
                          color: LoopColors.buyNow,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _cost(o) == 0 ? t('besplatno') : formatCredits(_cost(o)),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const ValueKey('delivery-change'),
            onPressed: () {
              setState(() {
                _useSaved = false;
                _option = _opts.length == 1 ? _opts.first : null;
              });
              widget.onCleared?.call();
              _emit();
            },
            icon: const Icon(Icons.swap_horiz),
            label: Text(t('Odaberi drugi način dostave ili paketomat')),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in _opts.take(_all || _hiddenSelected ? _opts.length : 2))
          Padding(
            key: ValueKey('delivery-${m.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: LoopColors.surface,
              borderRadius: BorderRadius.circular(kRadius),
              child: InkWell(
                borderRadius: BorderRadius.circular(kRadius),
                onTap: () {
                  setState(() => _option = m);
                  _emit();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kRadius),
                    border: Border.all(
                      color: _option?.id == m.id
                          ? accent
                          : LoopColors.surfaceHover,
                      width: _option?.id == m.id ? 2 : 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: switch (_networkOf(m)) {
                            final n? => Color(n.color),
                            null => LoopColors.mint,
                          },
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          optionIcon(m),
                          color: _networkOf(m) == null ? null : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              m.subtitle,
                              style: TextStyle(
                                color: LoopColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _cost(m) == 0
                            ? t('Besplatno')
                            : formatCredits(_cost(m)),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (!_all && _opts.length > 2 && !_hiddenSelected)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('delivery-more'),
              onPressed: () => setState(() => _all = true),
              child: Text(t('Više načina dostave')),
            ),
          ),
        if (_method == DeliveryMethod.europe && _option?.to != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              t('Dostava u: {0}', [_option!.to!.label]),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        if (_method == DeliveryMethod.europe && _option?.to == null) ...[
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            key: const ValueKey('delivery-country'),
            initialValue: _country,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: t('Država'),
              prefixIcon: const Icon(Icons.public),
            ),
            items: [
              for (final e in kEuCountries.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text(
                    '${t(e.key)} · ${formatCredits(DeliveryService.costFor(DeliveryMethod.europe, widget.size, country: e.key))}',
                  ),
                ),
            ],
            onChanged: (c) {
              setState(() => _country = c);
              _emit();
            },
          ),
          const SizedBox(height: 8),
        ],
        if (_method?.needsAddress ?? false) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _address,
            decoration: InputDecoration(
              labelText: t('Adresa za dostavu'),
              hintText: _method == DeliveryMethod.europe
                  ? t('npr. Hauptstraße 5, 10115 Berlin')
                  : t('npr. Ilica 1, 10000 Zagreb'),
              prefixIcon: Icon(Icons.home_outlined),
            ),
            onChanged: (_) => _emit(),
          ),
        ],
        if (_otherLocker) ...[
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('delivery-locker-text'),
            controller: _lockerText,
            decoration: InputDecoration(
              labelText: t('Paketomat ({0})', [_option!.carrier!.name]),
              hintText: t('Adresa ili broj paketomata'),
              prefixIcon: const Icon(Icons.place_outlined),
            ),
            onChanged: (_) => _emit(),
          ),
        ],
        if (_network case final n?) ...[
          const SizedBox(height: 4),
          LockerTile(
            network: n,
            locker: _locker,
            onMap: _hasMap ? _pickOnMap : null,
            onList: _pickFromList,
          ),
        ],
      ],
    );
  }
}

/// Odabrani paketomat (BOX NOW, GLS, DPD) + gumbi za kartu i popis.
class LockerTile extends StatelessWidget {
  const LockerTile({
    super.key,
    required this.network,
    required this.locker,
    required this.onMap,
    required this.onList,
  });

  final LockerNetwork network;
  final BoxNowLocker? locker;

  /// Null: karta nije dostupna (bira se s popisa).
  final VoidCallback? onMap;
  final VoidCallback onList;

  @override
  Widget build(BuildContext context) {
    final l = locker;
    final color = Color(network.color);
    return Container(
      key: const ValueKey('locker-tile'),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.place, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l == null
                          ? t('Paketomat nije odabran')
                          : '${network.brand} #${l.id}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      l == null
                          ? t('Odaberi najbliži {0} paketomat na karti.', [
                              network.brand,
                            ])
                          : l.place,
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (onMap != null) ...[
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('boxnow-pick'),
                    onPressed: onMap,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(t('Karta')),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('boxnow-list'),
                  onPressed: onList,
                  icon: const Icon(Icons.list, size: 18),
                  label: Text(l == null ? t('Popis') : t('Promijeni')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Popis paketomata mreže s pretragom (grad, adresa, broj).
class LockerListSheet extends StatefulWidget {
  const LockerListSheet({
    super.key,
    required this.network,
    required this.lockers,
    this.selected,
  });

  final LockerNetwork network;
  final List<BoxNowLocker> lockers;
  final BoxNowLocker? selected;

  @override
  State<LockerListSheet> createState() => _LockerListSheetState();
}

class _LockerListSheetState extends State<LockerListSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = [
      for (final l in widget.lockers)
        if (q.isEmpty || '${l.id} ${l.place}'.toLowerCase().contains(q)) l,
    ];
    final color = Color(widget.network.color);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('{0} paketomati', [widget.network.brand]),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('locker-search'),
                decoration: InputDecoration(
                  hintText: t('Grad, adresa ili broj paketomata'),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          t('Nema paketomata za tu pretragu.'),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final l in list)
                            ListTile(
                              key: ValueKey('locker-${l.id}'),
                              leading: CircleAvatar(
                                backgroundColor: color,
                                foregroundColor: Colors.white,
                                child: const Icon(Icons.place, size: 20),
                              ),
                              title: Text(
                                l.name.isEmpty ? '#${l.id}' : l.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '#${l.id} · ${[l.address, if (l.postalCode.isNotEmpty) l.postalCode].join(', ')}',
                              ),
                              trailing: widget.selected?.id == l.id
                                  ? Icon(Icons.check_circle, color: color)
                                  : null,
                              onTap: () => Navigator.of(context).pop(l),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
