import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/delivery.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../providers/app_providers.dart';
import '../services/live_service.dart';
import '../services/live_video.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/celebration.dart';
import '../widgets/category_style.dart';
import '../widgets/countdown.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/story_canvas.dart';
import '../widgets/trade_actions.dart';
import '../widgets/live_video_view.dart';
import '../widgets/mini_live.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/user_avatar.dart';
import 'add_device_screen.dart';
import 'deliveries_screen.dart';
import 'public_profile_screen.dart';

/// Crvena boja live aukcija (oznaka UŽIVO, gumb za licitiranje).
const kLiveRed = Color(0xFFFF2D55);
const _defaultStage = [Color(0xFF3A1C71), Color(0xFFD76D77)];

/// Gradijent pozornice prema kategoriji predmeta.
List<Color> _stageGradient(Device? d) => d == null
    ? _defaultStage
    : [d.category.color, Color.lerp(d.category.color, Colors.black, 0.75)!];

/// Crvena oznaka "UŽIVO" s točkom koja pulsira (u testovima miruje).
class LiveBadge extends ConsumerStatefulWidget {
  const LiveBadge({super.key, this.small = false});
  final bool small;

  @override
  ConsumerState<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends ConsumerState<LiveBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (ref.read(tickIntervalProvider) != null) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.small ? 6.0 : 8.0;
    final pulse = _pulse;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.small ? 6 : 8,
        vertical: widget.small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: kLiveRed,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: pulse == null
                ? const AlwaysStoppedAnimation(1.0)
                : Tween(begin: 0.3, end: 1.0).animate(pulse),
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          SizedBox(width: widget.small ? 4 : 6),
          Text(
            t('UŽIVO'),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: widget.small ? 10 : 12,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Broj gledatelja kao na Whatnotu: crveni krug (uživo) i broj.
class _ViewersChip extends StatelessWidget {
  const _ViewersChip(this.count);
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('live-viewers'),
    padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
    decoration: BoxDecoration(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: kLiveRed,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.graphic_eq, size: 15, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------- pokretanje livea

/// Prodavatelj slaže live kao na Whatnotu: naslovna slika, naslov,
/// kategorija, početak (odmah ili zakazano), predmeti (neobavezno — mogu se
/// dodavati i tijekom livea) i postavke.
class CreateLiveShowScreen extends ConsumerStatefulWidget {
  const CreateLiveShowScreen({super.key, this.deviceId});

  /// Predmet koji je odmah odabran (npr. "Novi predmet → Live").
  final String? deviceId;

  /// Testno: live se može pokrenuti odmah, bez podataka prodavatelja
  /// (traže se tek za isplatu zarade).
  static Future<void> open(BuildContext context, {String? deviceId}) async {
    if (blockGuest(context)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateLiveShowScreen(deviceId: deviceId),
      ),
    );
  }

  @override
  ConsumerState<CreateLiveShowScreen> createState() =>
      _CreateLiveShowScreenState();
}

class _CreateLiveShowScreenState extends ConsumerState<CreateLiveShowScreen> {
  final _title = TextEditingController();

  /// Odabrani predmeti redom kojim će se licitirati.
  final _selected = <String>[];
  final _prices = <String, TextEditingController>{};
  int _secs = 30;

  /// Domaćin prenosi video s kamere (kao na Whatnotu).
  bool _video = true;

  /// Neprodano nakon livea ide na Kupi odmah.
  bool _relist = true;

  /// Naslovna slika (thumbnail).
  String? _cover;
  DeviceCategory? _category;

  /// `null` = kreće odmah.
  DateTime? _startsAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    final id = widget.deviceId;
    if (id != null) {
      _selected.add(id);
      _prices[id] = TextEditingController(text: '1');
      _category = ref.read(appProvider).deviceById(id)?.category;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Trgovac smije više predmeta u liveu.
  int get _maxLots =>
      ref.read(appProvider).currentUser?.seller?.isBusiness ?? false
      ? LiveShow.businessMaxLots
      : LiveShow.maxLots;

  void _toggle(Device d) => setState(() {
    _error = null;
    if (_selected.remove(d.id)) return;
    if (_selected.length >= _maxLots) {
      _error = t('Live može imati najviše {0} predmeta.', ['$_maxLots']);
      return;
    }
    _selected.add(d.id);
    _category ??= d.category;
    // Kao na Whatnotu: licitacija kreće od 1 €.
    _prices.putIfAbsent(d.id, () => TextEditingController(text: '1'));
  });

  Future<void> _pickCover() async {
    try {
      final paths = await ref.read(imageStoreProvider).pick(limit: 1);
      if (paths.isNotEmpty && mounted) setState(() => _cover = paths.first);
    } catch (e) {
      showLoopSnackBar(
        t('Fotografiju nije moguće učitati: {0}', [e]),
        error: true,
      );
    }
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final initial = _startsAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(LiveShow.maxScheduleAhead),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(
      () => _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _submit() async {
    final items = <(String, double)>[];
    for (final id in _selected) {
      final price = double.tryParse(
        _prices[id]!.text.trim().replaceAll(',', '.'),
      );
      if (price == null) {
        setState(() => _error = t('Upiši početnu cijenu za svaki predmet.'));
        return;
      }
      items.add((id, price));
    }
    LiveShow? created;
    final ok = await runWithLoading(
      context,
      () async => created = await ref
          .read(appProvider.notifier)
          .createLiveShow(
            title: _title.text,
            items: items,
            lotSeconds: _secs,
            startsAt: _startsAt,
            video: _video,
            coverPath: _cover,
            category: _category,
            relistUnsold: _relist,
          ),
      // Bez obavijesti: soba se odmah otvara (obavijest bi prekrila gumbe
      // na dnu sobe).
      successMessage: null,
    );
    if (!ok || !mounted || created == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LiveRoomScreen(showId: created!.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final eligible = s.myDevices
        .where((d) => !d.isDigital && s.activeAuctionFor(d.id) == null)
        .toList();
    final bold = const TextStyle(fontWeight: FontWeight.w800, fontSize: 15);
    const gap = SizedBox(height: 18);

    return Scaffold(
      appBar: AppBar(title: Text(t('Novi live'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // 1. Naslovna slika i naslov (kao na Whatnotu).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CoverPicker(
                    path: _cover,
                    onPick: _pickCover,
                    onClear: () => setState(() => _cover = null),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const ValueKey('live-title'),
                          controller: _title,
                          maxLength: LiveShow.maxTitle,
                          maxLines: 2,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: t('Naslov livea'),
                            hintText: t('npr. Retro igre od 1 €'),
                          ),
                        ),
                        DropdownButtonFormField<DeviceCategory>(
                          key: const ValueKey('live-category'),
                          initialValue: _category,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t('Kategorija'),
                          ),
                          items: [
                            for (final sec in ItemSection.values)
                              if (sec != ItemSection.digital)
                                for (final c in sec.categories)
                                  DropdownMenuItem(
                                    value: c,
                                    child: Row(
                                      children: [
                                        Icon(c.icon, size: 18, color: c.color),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            c.label,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ],
                          onChanged: (c) => setState(() => _category = c),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              gap,
              // 2. Početak: odmah ili zakazano.
              Text(t('Kada?'), style: bold),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(t('Odmah'), key: const ValueKey('live-now')),
                    icon: const Icon(Icons.bolt, size: 18),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(t('Zakaži'), key: const ValueKey('live-later')),
                    icon: const Icon(Icons.event, size: 18),
                  ),
                ],
                selected: {_startsAt != null},
                onSelectionChanged: (v) async {
                  if (v.first) {
                    await _pickTime();
                  } else {
                    setState(() => _startsAt = null);
                  }
                },
              ),
              if (_startsAt != null)
                ListTile(
                  key: const ValueKey('live-when'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(
                    formatDateTime(_startsAt!),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    t(
                      'Pratitelji odmah dobivaju obavijest, a gledatelji mogu stisnuti "Podsjeti me" i predlicitirati.',
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _pickTime,
                    child: Text(t('Promijeni')),
                  ),
                ),
              gap,
              // 3. Predmeti (neobavezno).
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('Predmeti ({0}/{1})', [
                        '${_selected.length}',
                        '$_maxLots',
                      ]),
                      style: bold,
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('live-new-item'),
                    onPressed: () => AddDeviceScreen.open(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(t('Novi predmet')),
                  ),
                ],
              ),
              Text(
                t(
                  'Neobavezno: odaberi predmete i početnu cijenu. Predmete možeš dodavati i tijekom livea.',
                ),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final d in eligible)
                _LotChoice(
                  device: d,
                  order: _selected.indexOf(d.id) + 1,
                  price: _prices[d.id],
                  onTap: () => _toggle(d),
                ),
              const SizedBox(height: 8),
              // 4. Postavke.
              Material(
                color: LoopColors.surface,
                borderRadius: BorderRadius.circular(kRadius),
                child: Column(
                  children: [
                    SwitchListTile(
                      key: const ValueKey('live-video'),
                      value: _video,
                      onChanged: (v) => setState(() => _video = v),
                      secondary: const Icon(Icons.videocam),
                      title: Text(
                        t('Video uživo s kamere'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        _video
                            ? t(
                                'Gledatelji te vide i čuju dok pokazuješ predmete. Preglednik će tražiti dopuštenje za kameru i mikrofon.',
                              )
                            : t('Gledatelji vide samo fotografije predmeta.'),
                      ),
                    ),
                    SwitchListTile(
                      key: const ValueKey('live-relist'),
                      value: _relist,
                      onChanged: (v) => setState(() => _relist = v),
                      secondary: const Icon(Icons.sell_outlined),
                      title: Text(
                        t('Neprodano stavi na Kupi odmah'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        t(
                          'Što se ne proda, nakon livea ide u prodaju po početnoj cijeni.',
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('Licitacija po predmetu'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final sec in LiveShow.lotDurations)
                                ChoiceChip(
                                  key: ValueKey('live-secs-$sec'),
                                  label: Text(t('{0} s', ['$sec'])),
                                  selected: _secs == sec,
                                  onSelected: (_) =>
                                      setState(() => _secs = sec),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: LoopColors.surface,
                  borderRadius: BorderRadius.circular(kRadius),
                ),
                child: Text(
                  t(
                    '• Live traje dok si uživo — završavaš ga ti (ili kad izađeš).\n• Ti biraš predmet i pokrećeš licitaciju od {0} s.\n• Ponuda u zadnjih 10 s vraća sat na 10 s.\n• Pobjednik plaća automatski karticom, a dostava kreće na njegovu adresu.\n• Provizija je 10 % samo od razlike iznad početne cijene.',
                    ['$_secs'],
                  ),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: LoopColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('live-go'),
                style: FilledButton.styleFrom(
                  backgroundColor: kLiveRed,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _submit,
                icon: Icon(_startsAt == null ? Icons.videocam : Icons.event),
                label: Text(
                  _startsAt == null ? t('Kreni uživo') : t('Zakaži live'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Naslovna slika livea (uspravna, kao na Whatnotu).
class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.path,
    required this.onPick,
    required this.onClear,
  });

  final String? path;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = path;
    return SizedBox(
      width: 110,
      height: 146,
      child: Material(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('live-cover'),
          onTap: onPick,
          child: p == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 32,
                      color: LoopColors.textSecondary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t('Naslovna slika'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    LocalPhoto(
                      path: p,
                      cacheWidth: 300,
                      fallback: const SizedBox(),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: IconButton(
                        key: const ValueKey('live-cover-clear'),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                        onPressed: onClear,
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _LotChoice extends StatelessWidget {
  const _LotChoice({
    required this.device,
    required this.order,
    required this.price,
    required this.onTap,
  });

  final Device device;

  /// Redni broj u liveu (0 = nije odabran).
  final int order;
  final TextEditingController? price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = order > 0;
    final c = device.category.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? c.withValues(alpha: 0.14) : LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  key: ValueKey('live-item-${device.id}'),
                  borderRadius: BorderRadius.circular(kRadius),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ItemThumb(device: device, size: 44),
                            if (selected)
                              Positioned(
                                right: -6,
                                top: -6,
                                child: CircleAvatar(
                                  radius: 11,
                                  backgroundColor: kLiveRed,
                                  child: Text(
                                    '$order',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                t('Vrijednost {0}', [
                                  formatCredits(device.price),
                                ]),
                                style: TextStyle(
                                  color: LoopColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!selected)
                          Icon(
                            Icons.add_circle_outline,
                            color: LoopColors.textSecondary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (selected && price != null)
                SizedBox(
                  width: 92,
                  child: TextField(
                    key: ValueKey('live-price-${device.id}'),
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: t('Od'),
                      suffixText: t('€'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- soba uživo

/// Soba livea preko cijelog ekrana (otvorena iz obavijesti ili poveznice).
class LiveRoomScreen extends StatelessWidget {
  const LiveRoomScreen({super.key, required this.showId});
  final String showId;

  static Future<void> open(BuildContext context, String showId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => LiveRoomScreen(showId: showId)),
      );

  @override
  Widget build(BuildContext context) => Consumer(
    // Izlazak iz sobe: live se gleda dalje u malom prozoru.
    builder: (context, ref, child) => PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.read(miniLiveProvider.notifier).show(showId);
      },
      child: child!,
    ),
    child: Scaffold(
      backgroundColor: Colors.black,
      body: LiveRoomView(showId: showId),
    ),
  );
}

/// Soba livea (kao Whatnot): pozornica s predmetom, odbrojavanje, veliki
/// gumb za licitiranje, chat i red predmeta. Domaćin vidi gumb za kraj.
/// U swipe feedu je aktivna samo soba na ekranu ([active]): samo ona broji
/// gledatelja i osvježava odbrojavanje.
class LiveRoomView extends ConsumerStatefulWidget {
  const LiveRoomView({super.key, required this.showId, this.active = true});
  final String showId;
  final bool active;

  @override
  ConsumerState<LiveRoomView> createState() => _LiveRoomViewState();
}

class _LiveRoomViewState extends ConsumerState<LiveRoomView> {
  Timer? _timer;
  DateTime _joinedAt = DateTime.now();
  DateTime _beatAt = DateTime.now();
  final _chat = TextEditingController();
  bool _busy = false;

  /// Video: domaćin šalje kameru, gledatelj prima (samo dok je soba
  /// aktivna i live nije završio).
  LiveBroadcaster? _broadcaster;
  LiveWatcher? _watcher;

  /// Reakcije: šalju se kao kratka poruka, a u sobi lete uz desni rub.
  static const _reactions = ['❤️', '🔥', '👏', '😍', '💸'];

  static bool isReaction(LiveEvent e) =>
      e.type == LiveEventType.chat && _reactions.contains(e.text);

  AppController get _app => ref.read(appProvider.notifier);

  /// Srce: prozirno dok ne lajkaš (dvostruki dodir bilo gdje ili dodir na
  /// srce), zatim crveno. Svaki dodir po pozadini pušta srca.
  bool _liked = false;
  final _bursts = <_Burst>[];
  int _burstId = 0;
  DateTime? _lastTap;
  DateTime _heartSentAt = DateTime(2000);

  /// Srca lete od [at] (ili uz desni rub); ostalima se šalje najviše
  /// jedno srce u 1,5 s (da chat ne zatrpa).
  void _heart({Offset? at, bool like = false, int count = 1}) {
    setState(() {
      if (like) _liked = true;
      for (var i = 0; i < count; i++) {
        _bursts.add(_Burst(_burstId++, at));
      }
      if (_bursts.length > 40) _bursts.removeRange(0, _bursts.length - 40);
    });
    final me = ref.read(appProvider).currentUser;
    final now = DateTime.now();
    if (me != null &&
        !me.isGuest &&
        now.difference(_heartSentAt) > const Duration(milliseconds: 1500)) {
      _heartSentAt = now;
      _app.liveChat(widget.showId, '❤️').catchError((_) {});
    }
  }

  /// Srce u stupcu: lajk (srca lete) ili, ako je već crveno, poništi.
  void _toggleLike() {
    if (_liked) {
      setState(() => _liked = false);
    } else {
      _heart(like: true, count: 2);
    }
  }

  void _tapStage(TapUpDetails d) {
    final now = DateTime.now();
    final isDouble =
        _lastTap != null &&
        now.difference(_lastTap!) < const Duration(milliseconds: 320);
    _lastTap = isDouble ? null : now;
    _heart(at: d.localPosition, like: isDouble, count: isDouble ? 3 : 1);
  }

  @override
  void initState() {
    super.initState();
    pushSnackBarLift();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(LiveRoomView old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
    if (!widget.active && old.active) {
      _timer?.cancel();
      _stopVideo();
    }
  }

  void _start() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // U sobi nema malog prozora (isti live bi se gledao dvaput).
      ref.read(miniLiveProvider.notifier).hide();
      _joinedAt = DateTime.now();
      _app.joinLive(widget.showId);
      _app.settleLive();
      _beat(force: true);
      _startVideo();
    });
    final every = ref.read(tickIntervalProvider);
    _timer?.cancel();
    if (every != null) _timer = Timer.periodic(every, (_) => _tick());
  }

  /// Domaćin u sobi javlja "još sam tu" — live traje dok se javlja.
  /// Zakazani live kreće tek gumbom "Kreni uživo sada".
  void _beat({bool force = false}) {
    final s = ref.read(appProvider);
    final show = s.liveShowById(widget.showId);
    if (show == null || show.hostId != s.currentUserId) return;
    if (show.hostSeenAt == null || show.endedAt != null) return;
    final now = DateTime.now();
    if (!force && now.difference(_beatAt) < LiveShow.heartbeat) return;
    _beatAt = now;
    _app.liveHeartbeat(widget.showId);
  }

  Future<void> _goLiveNow() async {
    final ok = await runWithLoading(
      context,
      () => _app.liveHeartbeat(widget.showId),
      successMessage: t('Uživo si! 🔴'),
    );
    if (ok && mounted) await _startVideo();
  }

  Future<void> _startLot([int? index]) async {
    try {
      await _app.liveStartLot(widget.showId, index: index);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    }
  }

  /// Domaćin dodaje predmet u live (iz svojih predmeta ili novi).
  Future<void> _addItem(LiveShow show) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: LoopColors.background,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _AddLotSheet(showId: show.id),
    );
    if (added == true) showLoopSnackBar(t('Predmet je dodan u live.'));
  }

  /// Zadnji brzo dodani predmet ("Ponovi zadnji").
  (String, double)? _lastQuick;

  /// Brzo dodavanje usred livea: samo naziv i početna cijena — predmet
  /// se sam sprema u Moje predmete i stavlja na kraj reda.
  Future<void> _quickAdd(LiveShow show) async {
    final r = await showModalBottomSheet<(String, double)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: LoopColors.background,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _QuickAddSheet(last: _lastQuick),
    );
    if (r == null || !mounted) return;
    final (name, price) = r;
    final category =
        suggestCategory(name) ??
        DeviceCategory.values.firstWhere(
          (c) => c.name == show.category,
          orElse: () => DeviceCategory.other,
        );
    final ok = await runWithLoading(context, () async {
      final d = await _app.addDevice(
        name: name,
        model: '',
        condition: DeviceCondition.good,
        price: price,
        category: category,
        listOnMarket: false,
      );
      await _app.liveAddLot(show.id, d.id, price);
    }, successMessage: null);
    if (!ok || !mounted) return;
    _lastQuick = r;
    showLoopSnackBar(t('Predmet je dodan u live.'));
  }

  /// Predmeti koji su već prodani kad smo ušli ili koje smo već proslavili.
  Set<int>? _seenSold;

  /// Kratka traka "PRODANO" za ostale gledatelje.
  LotState? _sweep;
  DateTime? _sweepAt;

  /// Whatnot: kad predmet ode, pobjednik dobiva slavlje preko cijelog
  /// ekrana, a ostali traku "PRODANO @kupac · cijena".
  void _watchSales(LiveState st, String? me) {
    final sold = [
      for (final l in st.lots)
        if (l.status == LotStatus.sold && l.leader != null) l,
    ];
    final seen = _seenSold;
    if (seen == null) {
      _seenSold = {for (final l in sold) l.index};
      return;
    }
    for (final l in sold) {
      if (!seen.add(l.index)) continue;
      if (l.leader!.userId == me) {
        final device = ref.read(appProvider).deviceById(l.lot.deviceId);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showCelebration(
            context,
            title: l.mode == LotMode.dutch
                ? t('Kupljeno! 🎉')
                : t('Osvojio si! 🎉'),
            subtitle: t('Plaćeno karticom · odaberi dostavu'),
            device: device,
            amount: l.price,
          );
        });
      } else {
        _sweep = l;
        _sweepAt = DateTime.now();
      }
    }
  }

  /// Zašto se kamera domaćina nije uključila (null = sve u redu).
  String? _cameraError;

  Future<void> _startVideo() async {
    final signaling = ref.read(liveSignalingProvider);
    final s = ref.read(appProvider);
    final show = s.liveShowById(widget.showId);
    if (signaling == null || show == null || !show.video) return;
    if (_broadcaster != null || _watcher != null) return;
    if (s.liveStateOf(show).isOver) return;
    if (show.hostId == s.currentUserId) {
      // Kamera se pali kad domaćin stvarno krene uživo.
      if (show.hostSeenAt == null) return;
      final b = LiveBroadcaster(signaling(show.id));
      setState(() {
        _broadcaster = b;
        _cameraError = null;
      });
      try {
        await b.start();
      } catch (e) {
        if (mounted) {
          setState(() {
            _broadcaster = null;
            _cameraError = e is LiveCameraException && e.denied
                ? t(
                    'Preglednik nije dopustio kameru. Dopusti kameru i mikrofon (ikona lokota pokraj adrese) pa stisni "Uključi kameru".',
                  )
                : t(
                    'Kamera se nije uključila ({0}). Stisni "Uključi kameru".',
                    [e is LiveCameraException ? e.detail : '$e'],
                  );
          });
        }
        await b.stop();
      }
    } else {
      final w = LiveWatcher(signaling(show.id));
      setState(() => _watcher = w);
      try {
        await w.start();
      } catch (_) {
        // Video nije dostupan — ostaju fotografije predmeta.
      }
    }
  }

  void _stopVideo() {
    final b = _broadcaster;
    final w = _watcher;
    _broadcaster = null;
    _watcher = null;
    b?.stop();
    w?.stop();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    popSnackBarLift();
    _timer?.cancel();
    _broadcaster?.stop();
    _watcher?.stop();
    _chat.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    final s = ref.read(appProvider);
    final show = s.liveShowById(widget.showId);
    final me = s.currentUserId;
    if (show == null || me == null) return;
    final now = DateTime.now();
    if ((_broadcaster != null || _watcher != null) &&
        s.liveStateOf(show, now).isOver) {
      _stopVideo();
    }
    _beat();
    // Gledatelj ostaje brojan dok je u sobi.
    if (now.difference(_joinedAt) > const Duration(minutes: 4)) {
      _joinedAt = now;
      _app.joinLive(widget.showId);
    }
    // Završen predmet provodi domaćin ili pobjednik (tko god je prisutan).
    final due = s
        .liveStateOf(show, now)
        .lots
        .any(
          (l) =>
              l.status == LotStatus.sold &&
              !show.settled.contains(l.index) &&
              (me == show.hostId || l.leader?.userId == me),
        );
    if (due) _app.settleLive();
  }

  Future<void> _bid(double amount, {int? lot}) async {
    if (blockGuest(context) || _busy) return;
    if (!await ensureCheckout(context, ref) || !mounted) return;
    setState(() => _busy = true);
    try {
      // Bez potvrde u SnackBaru (prekrio bi chat) — gumb postaje "Vodiš".
      final leading = await _app.liveBid(widget.showId, amount, lot: lot);
      if (!leading) {
        showLoopSnackBar(
          t('Netko ima višu maksimalnu ponudu — povisi!'),
          error: true,
        );
      } else if (lot != null) {
        showLoopSnackBar(t('Predlicitacija je spremljena 🔨'));
      }
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _take() async {
    if (blockGuest(context) || _busy) return;
    if (!await ensureCheckout(context, ref) || !mounted) return;
    setState(() => _busy = true);
    try {
      final won = await _app.liveTake(widget.showId);
      if (!won) showLoopSnackBar(t('Netko je bio brži!'), error: true);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enter() async {
    if (blockGuest(context) || _busy) return;
    if (!await ensureCheckout(context, ref) || !mounted) return;
    setState(() => _busy = true);
    try {
      await _app.liveEnter(widget.showId);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Maksimalna ponuda (kao "custom bid" na Whatnotu): sustav licitira
  /// umjesto tebe do tog iznosa. [lot] = predlicitacija za predmet na
  /// čekanju.
  Future<void> _customBid(double min, {int? lot, bool raise = false}) async {
    if (blockGuest(context)) return;
    final amount = await showMaxBidDialog(context, min: min, raise: raise);
    if (amount != null && mounted) await _bid(amount, lot: lot);
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || blockGuest(context)) return;
    try {
      await _app.liveChat(widget.showId, text);
      _chat.clear();
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    }
  }

  Future<void> _end(bool scheduled) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(scheduled ? t('Otkazati live?') : t('Završiti live?')),
        content: Text(
          t(
            'Predmet koji se upravo licitira i svi sljedeći ostaju tebi. Već prodani ostaju prodani.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Odustani')),
          ),
          FilledButton(
            key: const ValueKey('live-end-confirm'),
            style: FilledButton.styleFrom(backgroundColor: kLiveRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(scheduled ? t('Otkaži') : t('Završi')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await runWithLoading(
      context,
      () => _app.endLiveShow(widget.showId),
      successMessage: t('Live je završen'),
    );
  }

  void _showQueue(LiveState st, bool isHost) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: LoopColors.background,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            t('Predmeti u liveu'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          if (!isHost && st.queue.any((l) => l.mode == LotMode.auction))
            Text(
              t(
                'Predlicitiraj predmet koji tek dolazi — tvoja maksimalna ponuda vrijedi kad krene.',
              ),
              style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
            ),
          const SizedBox(height: 8),
          for (final l in st.lots)
            _QueueRow(
              lot: l,
              me: ref.read(appProvider).currentUserId,
              onStart: isHost && st.canStart && l.status == LotStatus.upcoming
                  ? () {
                      Navigator.pop(ctx);
                      _startLot(l.index);
                    }
                  : null,
              onPreBid:
                  !isHost &&
                      !st.isOver &&
                      l.status == LotStatus.upcoming &&
                      l.mode == LotMode.auction
                  ? () async {
                      final mine =
                          l.leader?.userId ==
                          ref.read(appProvider).currentUserId;
                      final min = mine
                          ? (l.maxOf(l.leader!.userId) ?? l.price) +
                                LiveLot.increment(l.price)
                          : l.minNext;
                      final amount = await showMaxBidDialog(
                        ctx,
                        min: min,
                        preBid: true,
                        raise: mine,
                      );
                      if (amount == null || !ctx.mounted) return;
                      Navigator.pop(ctx);
                      await _bid(amount, lot: l.index);
                    }
                  : null,
            ),
          _ShowShop(hostId: st.show.hostId, isHost: isHost),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final show = s.liveShowById(widget.showId);
    if (show == null) {
      return SafeArea(
        child: Stack(
          children: [
            const Center(
              child: Icon(
                Icons.videocam_off_outlined,
                color: Colors.white54,
                size: 56,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t('Live ne postoji.'),
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('live-close'),
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ],
        ),
      );
    }
    final now = DateTime.now();
    final st = s.liveStateOf(show, now);
    final me = s.currentUser;
    final isHost = me?.id == show.hostId;
    final host = s.userById(show.hostId);
    final cur = st.current;
    final done = st.lastDone;
    final stageLot =
        cur ??
        (st.isLive ? (done ?? st.next) : null) ??
        st.lots.where((l) => l.status == LotStatus.sold).lastOrNull ??
        st.lots.firstOrNull;
    final stageDevice = stageLot == null
        ? null
        : s.deviceById(stageLot.lot.deviceId);
    final canAct = me != null && !me.isGuest;
    if (widget.active) _watchSales(st, me?.id);
    final sweep = _sweep;
    final showSweep =
        sweep != null &&
        _sweepAt != null &&
        now.difference(_sweepAt!) < const Duration(milliseconds: 2600);

    Widget center;
    if (st.isScheduled) {
      center = _Panel(
        children: [
          Text(
            t('Počinje {0}', [formatDateTime(show.startsAt)]),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          AuctionCountdown(
            endsAt: show.startsAt,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          if (isHost)
            FilledButton.icon(
              key: const ValueKey('live-go-now'),
              style: FilledButton.styleFrom(
                backgroundColor: kLiveRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _goLiveNow,
              icon: const Icon(Icons.videocam),
              label: Text(t('Kreni uživo sada')),
            )
          else ...[
            if (s.wantsReminder(show.id))
              Text(
                t('🔔 Javit ćemo ti kad krene'),
                key: const ValueKey('live-reminded'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              FilledButton.icon(
                key: const ValueKey('live-remind'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => remindMe(context, ref, show.id),
                icon: const Icon(Icons.notifications_none),
                label: Text(t('Podsjeti me')),
              ),
            const SizedBox(height: 6),
            Text(
              show.lots.isEmpty
                  ? t('Predmeti se otkrivaju uživo')
                  : t('{0} predmeta · licitacija od {1}', [
                      '${show.lots.length}',
                      formatCredits(
                        show.lots
                            .map((l) => l.startPrice)
                            .reduce((a, b) => a < b ? a : b),
                      ),
                    ]),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      );
    } else if (st.isOver) {
      final won = st.lots
          .where(
            (l) => l.status == LotStatus.sold && l.leader?.userId == me?.id,
          )
          .length;
      center = _Panel(
        key: const ValueKey('live-over'),
        children: [
          const Text('🎬', style: TextStyle(fontSize: 36)),
          Text(
            t('Live je završio'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t('Prodano {0} od {1} predmeta', [
              '${st.soldCount}',
              '${st.lots.length}',
            ]),
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          _Recap(state: st, me: me?.id),
          if (won > 0) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => DeliveriesScreen.open(context),
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(t('Osvojio si {0} · odaberi dostavu', ['$won'])),
            ),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            key: const ValueKey('live-share-recap'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => shareLink(
              context,
              publicLink(live: show.id),
              text: t('Prodano {0} od {1} predmeta', [
                '${st.soldCount}',
                '${st.lots.length}',
              ]),
            ),
            icon: const Icon(Icons.ios_share, size: 18),
            label: Text(t('Podijeli sažetak')),
          ),
        ],
      );
    } else if (cur == null && isHost) {
      center = _Panel(
        key: const ValueKey('live-host-idle'),
        children: [
          Text(
            st.queue.isEmpty
                ? t('Dodaj predmet i pokreni licitaciju')
                : t('Pokaži predmet pa pokreni licitaciju'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    } else if (cur == null && done == null) {
      center = _Panel(
        children: [
          Text(
            t('Domaćin priprema sljedeći predmet…'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      );
    } else {
      center = const SizedBox.shrink();
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LiveVideoStage(
            broadcaster: _broadcaster,
            watcher: _watcher,
            fallback: switch ((cur, show.coverPath)) {
              // Dok se ništa ne licitira: naslovna slika livea.
              (null, final cover?) => LocalPhoto(
                key: const ValueKey('live-cover-stage'),
                path: cover,
                fallback: StoryBackdrop(
                  gradient: _stageGradient(stageDevice),
                  device: stageDevice,
                ),
              ),
              _ => StoryBackdrop(
                gradient: _stageGradient(stageDevice),
                device: stageDevice,
              ),
            },
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black54,
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black87,
                ],
                stops: [0, 0.22, 0.45, 1],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    _TopBar(
                      show: show,
                      state: st,
                      host: host,
                      hostName: host?.handle ?? show.hostLabel,
                    ),
                    // Mjerač samo kad se nešto događa (inače je šum).
                    if (st.isLive && st.hype >= 0.2) _HypeMeter(st.hype),
                    Expanded(
                      child: Stack(
                        children: [
                          // Dodir bilo gdje po pozadini: srca; dvostruki = lajk.
                          Positioned.fill(
                            child: GestureDetector(
                              key: const ValueKey('live-stage-tap'),
                              behavior: HitTestBehavior.opaque,
                              onTapUp: st.isOver ? null : _tapStage,
                            ),
                          ),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                72,
                                16,
                              ),
                              child: center,
                            ),
                          ),
                          if (showSweep)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 48,
                              child: IgnorePointer(
                                child: _SoldSweep(
                                  key: ValueKey('live-sold-${sweep.index}'),
                                  text: t('PRODANO @{0} · {1}', [
                                    s.userById(sweep.leader!.userId)?.handle ??
                                        '?',
                                    formatCredits(sweep.price),
                                  ]),
                                ),
                              ),
                            ),
                          if (_cameraError != null &&
                              isHost &&
                              _broadcaster == null)
                            Positioned(
                              left: 12,
                              right: 12,
                              top: 4,
                              child: _CameraRetry(
                                message: _cameraError!,
                                onRetry: _startVideo,
                              ),
                            )
                          else
                            Positioned(
                              left: 12,
                              top: 4,
                              child: _VideoStatus(
                                show: show,
                                broadcaster: _broadcaster,
                                watcher: _watcher,
                                online:
                                    ref.watch(liveSignalingProvider) != null,
                              ),
                            ),
                          if (_broadcaster case final b?)
                            Positioned(
                              right: 8,
                              top: 4,
                              child: _HostControls(broadcaster: b),
                            ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            width: 90,
                            height: 360,
                            child: IgnorePointer(
                              child: _FloatingReactions(
                                // Svoja srca crtam odmah (lokalno).
                                events: [
                                  for (final e in st.feed)
                                    if (isReaction(e) && e.userId != me?.id) e,
                                ],
                                local: [
                                  for (final b in _bursts)
                                    if (b.at == null) b,
                                ],
                                onLocalDone: (b) =>
                                    setState(() => _bursts.remove(b)),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  for (final b in _bursts)
                                    if (b.at != null)
                                      _FloatUp(
                                        key: ValueKey('burst-${b.id}'),
                                        emoji: '❤️',
                                        seed: b.id * 7919,
                                        origin: b.at,
                                        onDone: () {
                                          if (mounted) {
                                            setState(() => _bursts.remove(b));
                                          }
                                        },
                                      ),
                                ],
                              ),
                            ),
                          ),
                          // Chat zauzima najviše pola slobodnog prostora.
                          Positioned(
                            left: 12,
                            right: 72,
                            top: 0,
                            bottom: 4,
                            child: LayoutBuilder(
                              builder: (_, c) => Align(
                                alignment: Alignment.bottomLeft,
                                child: _ChatFeed(
                                  feed: st.feed,
                                  me: me?.id,
                                  hostId: show.hostId,
                                  maxHeight: math.min(210, c.maxHeight * 0.55),
                                ),
                              ),
                            ),
                          ),
                          // Desni stupac se smanji da stane (mali ekrani).
                          Positioned(
                            right: 2,
                            top: 0,
                            bottom: 4,
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.bottomRight,
                                child: _SideRail(
                                  show: show,
                                  state: st,
                                  isHost: isHost,
                                  canAct: canAct,
                                  onQueue: () => _showQueue(st, isHost),
                                  liked: _liked,
                                  onHeart: _toggleLike,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Osvojeno u ovom liveu, a dostava još nije odabrana.
                    if (s.myDeliveries
                            .where(
                              (d) =>
                                  d.awaitingChoice &&
                                  d.id.startsWith('live-${show.id}-'),
                            )
                            .toList()
                        case final pending when pending.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        child: FilledButton.icon(
                          key: const ValueKey('live-choose-delivery'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1FA463),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(42),
                          ),
                          onPressed: () =>
                              pickDelivery(context, ref, pending.first),
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: Text(
                            t('📦 Osvojio si {0} · Odaberi dostavu', [
                              '${pending.length}',
                            ]),
                          ),
                        ),
                      ),
                    if (canAct && !st.isOver)
                      _ChatInput(controller: _chat, onSend: _send),
                    if (cur != null)
                      _LotCard(
                        lot: cur,
                        device: s.deviceById(cur.lot.deviceId),
                        total: show.lots.length,
                        lotSeconds: show.lotSeconds,
                        now: now,
                        me: me?.id,
                        leaderUser: s.userById(cur.leader?.userId),
                      )
                    else if (done != null && !st.isOver)
                      _LotCard(
                        lot: done,
                        device: s.deviceById(done.lot.deviceId),
                        total: show.lots.length,
                        lotSeconds: show.lotSeconds,
                        now: now,
                        me: me?.id,
                        leaderUser: s.userById(done.leader?.userId),
                        result: true,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: _actions(show, st, cur, isHost, canAct, me?.id),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(
    LiveShow show,
    LiveState st,
    LotState? cur,
    bool isHost,
    bool canAct,
    String? me,
  ) {
    if (isHost) {
      if (st.isOver) return const SizedBox.shrink();
      final outlined = OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      );
      if (st.isScheduled) {
        return Align(
          alignment: Alignment.center,
          child: OutlinedButton(
            key: const ValueKey('live-end'),
            style: outlined,
            onPressed: () => _end(true),
            child: Text(t('Otkaži')),
          ),
        );
      }
      final next = st.next;
      final big = FilledButton.styleFrom(
        backgroundColor: kLiveRed,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.white24,
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      );
      return Row(
        children: [
          Expanded(
            child: cur == null && next == null
                ? FilledButton.icon(
                    key: const ValueKey('live-add-first'),
                    style: big,
                    onPressed: () => _quickAdd(show),
                    icon: const Icon(Icons.bolt),
                    label: Text(t('Dodaj predmet')),
                  )
                : FilledButton.icon(
                    key: const ValueKey('live-start-next'),
                    style: big,
                    onPressed: st.canStart && next != null
                        ? () => _startLot(next.index)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      cur != null
                          ? t('Licitacija traje…')
                          : t('Sljedeći: {0}', [next!.lot.deviceName]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
          if (cur != null || next != null) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              key: const ValueKey('live-quick-add'),
              style: outlined,
              onPressed: () => _quickAdd(show),
              child: Text(t('⚡ Brzo dodaj')),
            ),
          ],
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            key: const ValueKey('live-host-menu'),
            tooltip: t('Više'),
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) => switch (v) {
              'add' => _addItem(show),
              _ => _end(false),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const ValueKey('live-add-item'),
                value: 'add',
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(t('Dodaj iz mojih predmeta')),
                ),
              ),
              PopupMenuItem(
                key: const ValueKey('live-end'),
                value: 'end',
                child: ListTile(
                  leading: Icon(Icons.stop_circle_outlined, color: kLiveRed),
                  title: Text(t('Završi live')),
                ),
              ),
            ],
          ),
        ],
      );
    }
    if (cur == null) {
      if (!st.isLive) return const SizedBox.shrink();
      return FilledButton(
        key: const ValueKey('live-awaiting'),
        style: FilledButton.styleFrom(
          disabledBackgroundColor: Colors.white24,
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
        onPressed: null,
        child: Text(t('Čeka se sljedeći predmet')),
      );
    }
    if (!canAct) {
      return FilledButton(
        key: const ValueKey('live-login'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: () => blockGuest(context),
        child: Text(t('Prijavi se za licitiranje')),
      );
    }
    if (cur.mode == LotMode.dutch) {
      final price = cur.dutchPriceAt(DateTime.now(), st.show.lotSeconds);
      return FilledButton(
        key: const ValueKey('live-take'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1FA463),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        onPressed: _busy ? null : _take,
        child: Text(t('⬇️ Uzmi za {0}', [formatCredits(price)])),
      );
    }
    if (cur.mode == LotMode.giveaway) {
      final entered = ref.watch(
        appProvider.select((s) => s.hasEnteredGiveaway(st.show.id, cur.index)),
      );
      return entered
          ? Container(
              key: const ValueKey('live-entered'),
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: LoopColors.success.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(kRadius),
              ),
              child: Text(
                t('✓ Sudjeluješ · izvlačenje na kraju'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          : FilledButton(
              key: const ValueKey('live-enter'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFC233),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(52),
                textStyle: const TextStyle(
                  fontFamily: kFontFamily,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              onPressed: _busy ? null : _enter,
              child: Text(t('🎁 Sudjeluj besplatno')),
            );
    }
    if (cur.leader?.userId == me) return _leading(cur, me);
    return _bidRow(cur);
  }

  Widget _leading(LotState cur, String? me) {
    final myMax = cur.maxOf(me) ?? cur.price;
    return Row(
      children: [
        Expanded(
          child: Container(
            key: const ValueKey('live-leading'),
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LoopColors.success.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: Text(
              t('✓ Vodiš s {0}', [formatCredits(cur.price)]),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 52,
          child: OutlinedButton(
            key: const ValueKey('live-raise'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
            onPressed: _busy
                ? null
                : () =>
                      _customBid(myMax + LiveLot.increment(myMax), raise: true),
            child: Text(t('Povisi maks')),
          ),
        ),
      ],
    );
  }

  Widget _bidRow(LotState cur) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton(
                key: const ValueKey('live-bid'),
                style: FilledButton.styleFrom(
                  backgroundColor: kLiveRed,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  textStyle: const TextStyle(
                    fontFamily: kFontFamily,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                onPressed: _busy ? null : () => _bid(cur.minNext),
                child: Text(t('Licitiraj {0}', [formatCredits(cur.minNext)])),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                key: const ValueKey('live-bid-custom'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: _busy ? null : () => _customBid(cur.minNext),
                child: Text(t('Maks')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          t('Ponuda je obvezujuća · pobjednik plaća automatski karticom'),
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
}

/// Predmet u moj live: dodaje ga u live koji traje ili je zakazan (od 1 €),
/// a ako ga nemam, otvara novi live s tim predmetom.
Future<void> addToLive(BuildContext context, WidgetRef ref, Device d) async {
  final s = ref.read(appProvider);
  final mine = s.activeLives
      .where((e) => e.$1.hostId == s.currentUserId)
      .map((e) => e.$1)
      .firstOrNull;
  if (mine == null) {
    await CreateLiveShowScreen.open(context, deviceId: d.id);
    return;
  }
  final ok = await runWithLoading(
    context,
    () => ref.read(appProvider.notifier).liveAddLot(mine.id, d.id, 1),
    successMessage: t('Predmet je dodan u live.'),
  );
  if (ok && context.mounted) await LiveRoomScreen.open(context, mine.id);
}

/// Dijalog za maksimalnu ponudu: brzi iznosi (sljedeći korak, +2, +5
/// koraka) ili vlastiti iznos. Vraća iznos ili `null`.
Future<double?> showMaxBidDialog(
  BuildContext context, {
  required double min,
  bool raise = false,
  bool preBid = false,
}) async {
  final controller = TextEditingController(
    text: min == min.roundToDouble()
        ? min.toStringAsFixed(0)
        : min.toStringAsFixed(2),
  );
  final quick = <double>[min];
  for (var i = 0; i < 2; i++) {
    final last = quick.last;
    quick.add(last + LiveLot.increment(last) * (i == 0 ? 2 : 5));
  }
  final amount = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        raise
            ? t('Povisi maksimalnu ponudu')
            : preBid
            ? t('Predlicitacija')
            : t('Maksimalna ponuda'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(
              'Licitiramo umjesto tebe do ovog iznosa — plaćaš samo koliko treba da pobijediš. Drugi ne vide tvoj maksimum.',
            ),
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              for (final q in quick)
                ActionChip(
                  key: ValueKey('max-quick-${q.toStringAsFixed(0)}'),
                  label: Text(formatCredits(q)),
                  onPressed: () => controller.text = q.toStringAsFixed(0),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('live-amount'),
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              suffixText: t('€'),
              helperText: t('Najmanje {0}', [formatCredits(min)]),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t('Odustani')),
        ),
        FilledButton(
          key: const ValueKey('live-amount-ok'),
          onPressed: () => Navigator.pop(
            ctx,
            double.tryParse(controller.text.trim().replaceAll(',', '.')),
          ),
          child: Text(raise ? t('Povisi') : t('Licitiraj')),
        ),
      ],
    ),
  );
  // Kontroler se ne gasi ručno: dijalog ga koristi i dok se zatvara
  // (animacija), a odmah nakon toga može se otvoriti sljedeći prozor.
  return amount;
}

/// "Podsjeti me" za zakazani live (obavijest kad domaćin krene).
Future<void> remindMe(
  BuildContext context,
  WidgetRef ref,
  String showId,
) async {
  if (blockGuest(context)) return;
  try {
    await ref.read(appProvider.notifier).liveRemind(showId);
    showLoopSnackBar(t('Javit ćemo ti kad krene uživo 🔔'));
  } on TradeException catch (e) {
    showLoopSnackBar(e.message, error: true);
  }
}

/// Sažetak završenog livea: prodano, ukupno, najtraženiji predmet, top
/// kupac i najbolji "pogađači" cijene.
class _Recap extends StatelessWidget {
  const _Recap({required this.state, required this.me});
  final LiveState state;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final sold = [
      for (final l in state.lots)
        if (l.status == LotStatus.sold && l.mode != LotMode.giveaway) l,
    ];
    final total = sold.fold<double>(0, (a, l) => a + l.price);
    LotState? hot;
    for (final l in state.lots) {
      if (l.mode == LotMode.auction &&
          l.bids.isNotEmpty &&
          (hot == null || l.bids.length > hot.bids.length)) {
        hot = l;
      }
    }
    final spent = <String, double>{};
    final names = <String, String>{};
    for (final l in sold) {
      final w = l.leader!;
      spent[w.userId] = (spent[w.userId] ?? 0) + l.price;
      names[w.userId] = w.userLabel;
    }
    final top = spent.entries.isEmpty
        ? null
        : spent.entries.reduce((a, b) => b.value > a.value ? b : a);
    Widget row(String emoji, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '$emoji  $text',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
    return Container(
      key: const ValueKey('live-recap'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(
            '📦',
            t('Prodano {0} od {1} predmeta', [
              '${state.soldCount}',
              '${state.lots.length}',
            ]),
          ),
          if (total > 0) row('💶', t('Ukupno {0}', [formatCredits(total)])),
          if (hot != null)
            row(
              '🔥',
              t('Najtraženije: {0} ({1} ponuda)', [
                hot.lot.deviceName,
                '${hot.bids.length}',
              ]),
            ),
          if (top != null)
            row(
              '👑',
              t('Top kupac: {0}', [top.key == me ? t('ti') : names[top.key]!]),
            ),
        ],
      ),
    );
  }
}

/// Gornja traka kao na Whatnotu: domaćin s ocjenom i brzinom slanja,
/// "Prati", broj gledatelja i zatvaranje.
class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.show,
    required this.state,
    required this.host,
    required this.hostName,
  });

  final LiveShow show;
  final LiveState state;
  final AppUser? host;
  final String hostName;

  static const _shadow = [Shadow(blurRadius: 6, color: Colors.black54)];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId;
    final following = s.isFollowing(show.hostId);
    final rating = s.ratingOf(show.hostId);
    final meta = [
      rating.count > 0 ? '★ ${rating.average.toStringAsFixed(1)}' : t('★ Novo'),
      t('🚚 {0} d.', ['${DeliveryMethod.courier.realDays}']),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => PublicProfileScreen.open(context, show.hostId),
            child: UserAvatar(user: host, size: 44),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hostName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    shadows: _shadow,
                  ),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$meta · ',
                        key: const ValueKey('live-host-meta'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          shadows: _shadow,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        show.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          shadows: _shadow,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (me != null && me != show.hostId && !following) ...[
            const SizedBox(width: 6),
            FilledButton(
              key: const ValueKey('live-follow'),
              style: FilledButton.styleFrom(
                backgroundColor: LoopColors.accent,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontFamily: kFontFamily,
                  fontWeight: FontWeight.w900,
                ),
              ),
              onPressed: () async {
                if (blockGuest(context)) return;
                await ref.read(appProvider.notifier).toggleFollow(show.hostId);
                showLoopSnackBar(t('Pratiš {0}', [hostName]));
              },
              child: Text(t('Prati')),
            ),
          ],
          const SizedBox(width: 8),
          if (state.isLive)
            _ViewersChip(state.viewers)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                state.isScheduled ? t('ZAKAZANO') : t('ZAVRŠENO'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          IconButton(
            key: const ValueKey('live-close'),
            tooltip: t('Zatvori'),
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}

/// Desni stupac gumba (kao na Whatnotu): predmeti, srce, dijeljenje,
/// novčanik (kartica i adresa) i trgovina prodavača.
class _SideRail extends ConsumerWidget {
  const _SideRail({
    required this.show,
    required this.state,
    required this.isHost,
    required this.canAct,
    required this.onQueue,
    required this.onHeart,
    this.liked = false,
  });

  final bool liked;
  final LiveShow show;
  final LiveState state;
  final bool isHost;
  final bool canAct;
  final VoidCallback onQueue;
  final VoidCallback onHeart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(
      appProvider.select((s) => s.listingsOf(show.hostId)),
    );
    final upcoming = state.queue.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailButton(
          key: const ValueKey('live-queue'),
          label: t('Predmeti'),
          onTap: onQueue,
          icon: Badge(
            isLabelVisible: upcoming > 0,
            label: Text('$upcoming'),
            child: const Icon(Icons.format_list_bulleted, color: Colors.white),
          ),
        ),
        if (!state.isOver)
          _RailButton(
            key: const ValueKey('live-react-0'),
            label: t('Srce'),
            onTap: onHeart,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(
                scale: Tween(
                  begin: 0.4,
                  end: 1.0,
                ).animate(CurvedAnimation(parent: a, curve: Curves.elasticOut)),
                child: c,
              ),
              child: liked
                  ? const Icon(
                      Icons.favorite,
                      key: ValueKey('liked'),
                      color: Color(0xFFFF4D6D),
                    )
                  : const Icon(
                      Icons.favorite_border,
                      key: ValueKey('not-liked'),
                      color: Colors.white,
                    ),
            ),
          ),
        _RailButton(
          key: const ValueKey('live-share'),
          label: t('Podijeli'),
          onTap: () => shareLink(
            context,
            publicLink(live: show.id),
            text: t('Gledaj "{0}" uživo na LOOP-u', [show.title]),
          ),
          icon: const Icon(Icons.ios_share, color: Colors.white),
        ),
        if (canAct && !isHost)
          _RailButton(
            key: const ValueKey('live-wallet'),
            label: t('Novčanik'),
            onTap: () => ensureCheckout(context, ref, force: true),
            icon: const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.white,
            ),
          ),
        if (listings.isNotEmpty)
          _RailButton(
            key: const ValueKey('live-shop-open'),
            label: t('Trgovina'),
            onTap: onQueue,
            icon: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: ItemThumb(device: listings.first, size: 38),
            ),
          ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(
            data: const IconThemeData(
              size: 26,
              shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
            ),
            child: icon,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Reakcije (srca i emoji) lete prema gore uz desni rub — kao na Whatnotu.
/// Animiraju se samo nove reakcije (ne i one od prije ulaska u sobu).
/// Lokalno srce (moj dodir): [at] = mjesto dodira, null = uz desni rub.
class _Burst {
  _Burst(this.id, this.at);
  final int id;
  final Offset? at;
}

class _FloatingReactions extends StatefulWidget {
  const _FloatingReactions({
    required this.events,
    this.local = const [],
    this.onLocalDone,
  });
  final List<LiveEvent> events;
  final List<_Burst> local;
  final void Function(_Burst)? onLocalDone;

  @override
  State<_FloatingReactions> createState() => _FloatingReactionsState();
}

class _FloatingReactionsState extends State<_FloatingReactions> {
  final _seen = <String>{};
  final _active = <LiveEvent>[];

  @override
  void initState() {
    super.initState();
    _seen.addAll(widget.events.map((e) => e.id));
  }

  @override
  void didUpdateWidget(_FloatingReactions old) {
    super.didUpdateWidget(old);
    final now = DateTime.now();
    for (final e in widget.events) {
      if (_seen.add(e.id) &&
          now.difference(e.at) < const Duration(seconds: 8)) {
        _active.add(e);
      }
    }
    if (_active.length > 24) _active.removeRange(0, _active.length - 24);
  }

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      for (final e in _active)
        _FloatUp(
          key: ValueKey(e.id),
          emoji: e.text,
          seed: stableHash(e.id),
          onDone: () {
            if (mounted) setState(() => _active.remove(e));
          },
        ),
      for (final b in widget.local)
        _FloatUp(
          key: ValueKey('local-${b.id}'),
          emoji: '❤️',
          seed: b.id * 7919,
          onDone: () => widget.onLocalDone?.call(b),
        ),
    ],
  );
}

class _FloatUp extends StatefulWidget {
  const _FloatUp({
    super.key,
    required this.emoji,
    required this.seed,
    required this.onDone,
    this.origin,
  });

  final String emoji;
  final int seed;
  final VoidCallback onDone;

  /// Mjesto dodira (srce leti gore odande); null = uz desni rub.
  final Offset? origin;

  @override
  State<_FloatUp> createState() => _FloatUpState();
}

class _FloatUpState extends State<_FloatUp>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 2200 + widget.seed % 800),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = (widget.seed % 628) / 100;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final v = _c.value;
        final o = widget.origin;
        if (o != null) {
          return Positioned(
            left:
                o.dx -
                16 +
                (widget.seed % 30 - 15) +
                math.sin(v * 6 + phase) * 12,
            top: o.dy - 20 - v * 260,
            child: Opacity(
              opacity: v < 0.7 ? 1 : (1 - v) / 0.3,
              child: Transform.scale(
                scale: 0.6 + 0.7 * math.min(v * 5, 1),
                child: child,
              ),
            ),
          );
        }
        return Positioned(
          right: 18 + (widget.seed % 24) + math.sin(v * 6 + phase) * 10,
          bottom: 20 + v * 300,
          child: Opacity(
            opacity: v < 0.75 ? 1 : (1 - v) / 0.25,
            child: Transform.scale(
              scale: 0.6 + 0.6 * math.min(v * 5, 1),
              child: child,
            ),
          ),
        );
      },
      child: Text(
        widget.emoji,
        style: const TextStyle(
          fontSize: 30,
          shadows: [Shadow(blurRadius: 6, color: Colors.black38)],
        ),
      ),
    );
  }
}

/// Hype-metar 🔥: koliko je živo (ponude, "uzimam", prijave, chat u zadnjih
/// 30 s). Toga na Whatnotu nema.
class _HypeMeter extends StatelessWidget {
  const _HypeMeter(this.hype);
  final double hype;

  @override
  Widget build(BuildContext context) {
    final label = hype >= 0.8
        ? t('🔥🔥 VRUĆE!')
        : hype >= 0.5
        ? t('🔥 Zagrijava se')
        : hype >= 0.2
        ? t('🙂 Živo')
        : t('😴 Mirno');
    return Padding(
      key: const ValueKey('live-hype'),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: hype,
                minHeight: 5,
                color: Color.lerp(const Color(0xFFFFC233), kLiveRed, hype),
                backgroundColor: Colors.white24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Traka "PRODANO" koja proleti preko sobe (kao na Whatnotu).
class _SoldSweep extends StatefulWidget {
  const _SoldSweep({super.key, required this.text});
  final String text;

  @override
  State<_SoldSweep> createState() => _SoldSweepState();
}

class _SoldSweepState extends State<_SoldSweep>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final v = _c.value;
        // Uleti (0–15 %), stoji, izleti (85–100 %).
        final dx = v < 0.15
            ? -1 + v / 0.15
            : v > 0.85
            ? (v - 0.85) / 0.15
            : 0.0;
        return FractionalTranslation(translation: Offset(dx, 0), child: child);
      },
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1FA463),
            borderRadius: BorderRadius.circular(99),
            boxShadow: const [BoxShadow(blurRadius: 16, color: Colors.black45)],
          ),
          child: Text(
            '🔨 ${widget.text}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

/// Brzo dodavanje predmeta u live: naziv i početna cijena.
class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet({this.last});
  final (String, double)? last;

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _name = TextEditingController();
  final _price = TextEditingController(text: '1');

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (name.isEmpty || price == null || price < 1) {
      showLoopSnackBar(t('Upiši naziv i cijenu (barem 1 €).'), error: true);
      return;
    }
    Navigator.pop(context, (name, price));
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.last;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('⚡ Brzo dodaj'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          Text(
            t('Predmet se sprema u Moje predmete i ide na kraj reda.'),
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('quick-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: t('Naziv')),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('quick-price'),
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: t('Početna cijena'),
              suffixText: '€',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (last != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('quick-repeat'),
                onPressed: () => setState(() {
                  _name.text = last.$1;
                  _price.text = last.$2 == last.$2.roundToDouble()
                      ? '${last.$2.toInt()}'
                      : '${last.$2}';
                }),
                icon: const Icon(Icons.replay, size: 18),
                label: Text(t('Ponovi zadnji: {0}', [last.$1])),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('quick-add-confirm'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _submit,
            child: Text(t('Dodaj u live')),
          ),
        ],
      ),
    );
  }
}

/// Polu-prozirna ploča na sredini pozornice.
class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(kRadius),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}

/// Donji panel kao na Whatnotu: tko vodi (ili tko je osvojio), slika i
/// naziv predmeta, stanje i kategorija, "+ dostava", cijena, procjena
/// vrijednosti i odbrojavanje (ili "Prodano").
class _LotCard extends StatelessWidget {
  const _LotCard({
    required this.lot,
    required this.device,
    required this.total,
    required this.lotSeconds,
    required this.now,
    required this.me,
    required this.leaderUser,
    this.result = false,
  });

  final LotState lot;
  final Device? device;
  final int total;
  final int lotSeconds;
  final DateTime now;
  final String? me;

  /// Vodeći (ili dobitnik) — za avatar u statusnom retku.
  final AppUser? leaderUser;

  /// Predmet je završen: prikazuje se dobitnik i "Prodano".
  final bool result;

  static const _shadow = [Shadow(blurRadius: 6, color: Colors.black87)];
  static const _yellow = Color(0xFFFFD166);

  @override
  Widget build(BuildContext context) {
    final left = lot.left(now);
    final secs = (left.inMilliseconds / 1000).ceil();
    final hot =
        !result && left <= LiveShow.extendWindow && lot.mode == LotMode.auction;
    final myMax = lot.maxOf(me);
    final leader = lot.leader;
    final d = device;
    final price = switch (lot.mode) {
      _ when result => lot.price,
      LotMode.auction => lot.price,
      LotMode.dutch => lot.dutchPriceAt(now, lotSeconds),
      LotMode.giveaway => 0.0,
    };
    // Procjena vrijednosti (vrijednost predmeta) — toga na Whatnotu nema.
    final value = d?.price ?? 0;
    final below = value > 0 && price > 0 && price < value
        ? ((1 - price / value) * 100).round()
        : 0;

    // Statusni redak (avatar + tekst).
    final String status;
    var highlight = '';
    if (result) {
      if (leader == null) {
        status = lot.mode == LotMode.giveaway
            ? t('Nitko se nije prijavio')
            : t('Nije prodano');
      } else if (leader.userId == me) {
        status = lot.mode == LotMode.giveaway
            ? t('🎁 Osvojio si nagradu!')
            : t('🏆 Osvojio si!');
      } else {
        status = leader.userLabel;
        highlight = lot.mode == LotMode.giveaway
            ? t(' je izvučen! 🎁')
            : t(' je osvojio!');
      }
    } else {
      status = switch (lot.mode) {
        LotMode.dutch => t('⬇️ Pada cijena · do {0}', [
          formatCredits(lot.lot.floorPrice),
        ]),
        LotMode.giveaway => t('🎁 Nagradna igra · {0} prijava', [
          '${lot.entrants}',
        ]),
        LotMode.auction =>
          leader == null
              ? t('Predmet {0}/{1} · još nema ponuda', [
                  '${lot.index + 1}',
                  '$total',
                ])
              : leader.userId == me
              ? t('🥇 Ti vodiš · tvoj maks {0}', [
                  formatCredits(myMax ?? lot.price),
                ])
              : t('🥇 {0} vodi', [leader.userLabel]),
      };
    }

    Widget chip(String text, {Color color = Colors.white24}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return Padding(
      key: ValueKey(result ? 'live-result' : 'live-lot'),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leader != null) ...[
                UserAvatar(user: leaderUser, size: 22),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: status),
                      if (highlight.isNotEmpty)
                        TextSpan(
                          text: highlight,
                          style: const TextStyle(color: _yellow),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    shadows: _shadow,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: d != null
                    ? ItemThumb(device: d, size: 64)
                    : Container(
                        width: 64,
                        height: 64,
                        color: Colors.white12,
                        child: const Icon(Icons.inventory_2_outlined),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lot.lot.deviceName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        height: 1.15,
                        shadows: _shadow,
                      ),
                    ),
                    if (d != null)
                      Text(
                        '${d.condition.label} · ${d.category.singular}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          shadows: _shadow,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        chip(
                          lot.mode == LotMode.giveaway
                              ? t('besplatno + dostava')
                              : t('+ dostava'),
                        ),
                        if (lot.mode != LotMode.auction)
                          chip('${lot.mode.emoji} ${lot.mode.label}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                key: const ValueKey('live-value'),
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    lot.mode == LotMode.giveaway
                        ? t('Besplatno')
                        : formatCredits(price),
                    key: const ValueKey('live-price'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      shadows: _shadow,
                    ),
                  ),
                  if (value > 0)
                    Text(
                      t('💎 procjena {0}', [formatCredits(value)]),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        shadows: _shadow,
                      ),
                    ),
                  if (result)
                    Text(
                      leader == null ? t('Nije prodano') : t('Prodano'),
                      style: TextStyle(
                        color: leader == null ? Colors.white70 : kLiveRed,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        shadows: _shadow,
                      ),
                    )
                  else ...[
                    if (below >= 5)
                      Text(
                        t('−{0}% ispod procjene', ['$below']),
                        style: const TextStyle(
                          color: Color(0xFF4ADE80),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          shadows: _shadow,
                        ),
                      ),
                    Text(
                      '0:${secs.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: hot ? kLiveRed : Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        shadows: _shadow,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (!result) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (left.inMilliseconds / (lotSeconds * 1000)).clamp(0, 1),
                minHeight: 3,
                color: hot ? kLiveRed : Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
            if (hot)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t('⚡ Ponuda sada vraća sat na 10 s'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    shadows: _shadow,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Chat preko videa kao na Whatnotu: avatar, ime (domaćin s oznakom) i
/// poruka, bez oblačića. Ponude su istaknute, a reakcije (srca) lete uz
/// desni rub umjesto da zatrpaju chat.
class _ChatFeed extends ConsumerWidget {
  const _ChatFeed({
    required this.feed,
    required this.me,
    required this.hostId,
    this.maxHeight = 210,
  });

  final double maxHeight;

  final List<LiveEvent> feed;
  final String? me;
  final String hostId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = [
      for (final e in feed)
        if (!_LiveRoomViewState.isReaction(e)) e,
    ];
    final s = ref.watch(appProvider);
    // Cijeli chat se može listati (najnovije dolje); gore blijedi.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white],
          stops: [0, 0.25],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          key: const ValueKey('live-feed'),
          reverse: true,
          shrinkWrap: true,
          padding: const EdgeInsets.only(top: 40),
          itemCount: lines.length,
          itemBuilder: (_, i) {
            final e = lines[lines.length - 1 - i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _FeedLine(
                event: e,
                user: s.userById(e.userId),
                mine: e.userId == me,
                host: e.userId == hostId,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FeedLine extends StatelessWidget {
  const _FeedLine({
    required this.event,
    required this.user,
    required this.mine,
    required this.host,
  });

  final LiveEvent event;
  final AppUser? user;
  final bool mine;
  final bool host;

  static const _shadow = [Shadow(blurRadius: 6, color: Colors.black87)];

  @override
  Widget build(BuildContext context) {
    final bid = event.type == LiveEventType.bid;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserAvatar(user: user, size: 30),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      mine ? t('Ti') : event.userLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        shadows: _shadow,
                      ),
                    ),
                  ),
                  if (host) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        t('Domaćin'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                bid
                    ? t('licitira {0} 🔨', [formatCredits(event.amount)])
                    : event.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bid ? const Color(0xFFFFD166) : Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  shadows: _shadow,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({required this.controller, required this.onSend});

  final TextEditingController controller;
  final Future<void> Function(String) onSend;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
    child: TextField(
      key: const ValueKey('live-chat'),
      controller: controller,
      maxLength: LiveEvent.maxText,
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.send,
      onSubmitted: onSend,
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        hintText: t('Reci nešto…'),
        hintStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.black26,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: const BorderSide(color: Colors.white70),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: const BorderSide(color: Colors.white70),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: const BorderSide(color: Colors.white, width: 1.5),
        ),
        suffixIcon: IconButton(
          key: const ValueKey('live-send'),
          tooltip: t('Pošalji'),
          onPressed: () => onSend(controller.text),
          icon: const Icon(Icons.send, color: Colors.white, size: 20),
        ),
      ),
    ),
  );
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.lot,
    required this.me,
    this.onStart,
    this.onPreBid,
  });
  final LotState lot;
  final String? me;

  /// Domaćin: pokreni licitaciju ovog predmeta.
  final VoidCallback? onStart;

  /// Gledatelj: predlicitacija (maksimalna ponuda prije početka).
  final VoidCallback? onPreBid;

  @override
  Widget build(BuildContext context) {
    final l = lot;
    final (String status, Color color) = switch (l.status) {
      LotStatus.running => (t('🔴 Licitira se'), kLiveRed),
      LotStatus.upcoming when l.leader != null => (
        l.leader!.userId == me
            ? t('🥇 Ti · {0}', [formatCredits(l.price)])
            : t('Predponuda {0}', [formatCredits(l.price)]),
        l.leader!.userId == me ? LoopColors.success : LoopColors.accent,
      ),
      LotStatus.upcoming => (
        t('Od {0}', [formatCredits(l.lot.startPrice)]),
        LoopColors.textSecondary,
      ),
      LotStatus.sold => (
        t('✅ {0} · {1}', [l.leader!.userLabel, formatCredits(l.price)]),
        LoopColors.success,
      ),
      LotStatus.unsold => (t('Nije prodano'), LoopColors.textSecondary),
      LotStatus.skipped => (t('Preskočeno'), LoopColors.textSecondary),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: l.status == LotStatus.running
            ? kLiveRed
            : LoopColors.surface,
        child: Text(
          '${l.index + 1}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: l.status == LotStatus.running
                ? Colors.white
                : LoopColors.textPrimary,
          ),
        ),
      ),
      title: Text(
        l.mode == LotMode.auction
            ? l.lot.deviceName
            : '${l.mode.emoji} ${l.lot.deviceName}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: onPreBid == null
          ? null
          : Text(
              status,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
      trailing: onStart != null
          ? FilledButton(
              key: ValueKey('live-start-${l.index}'),
              style: FilledButton.styleFrom(
                backgroundColor: kLiveRed,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onStart,
              child: Text(t('Pokreni')),
            )
          : onPreBid != null
          ? OutlinedButton(
              key: ValueKey('live-prebid-${l.index}'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onPreBid,
              child: Text(t('Predlicitiraj')),
            )
          : Text(
              status,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
    );
  }
}

/// Trgovina prodavača u liveu (kao "Shop" na Whatnotu): predmeti za
/// Kupi odmah koje gledatelji mogu kupiti bilo kada tijekom livea.
class _ShowShop extends ConsumerWidget {
  const _ShowShop({required this.hostId, required this.isHost});
  final String hostId;
  final bool isHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    // Predmet dodan u live izlazi iz prodaje, pa su ovdje samo slobodni.
    final items = [
      for (final d in s.listingsOf(hostId))
        if (!d.isDigital) d,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('live-shop'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          t('🛍️ Kupi odmah'),
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        Text(
          isHost
              ? t(
                  'Tvoji predmeti za Kupi odmah — gledatelji ih kupuju tijekom livea.',
                )
              : t('Kupi bez licitiranja, dok live traje.'),
          style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 6),
        for (final d in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ItemThumb(device: d, size: 40),
            title: Text(
              d.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(formatCredits(s.priceForMe(d))),
            trailing: isHost
                ? null
                : FilledButton(
                    key: ValueKey('live-buy-${d.id}'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => confirmAndBuy(context, ref, d),
                    child: Text(t('Kupi')),
                  ),
          ),
      ],
    );
  }
}

/// Domaćin dodaje predmet u live: odabir vlastitog predmeta i početne
/// cijene (ili novi predmet).
class _AddLotSheet extends ConsumerStatefulWidget {
  const _AddLotSheet({required this.showId});
  final String showId;

  @override
  ConsumerState<_AddLotSheet> createState() => _AddLotSheetState();
}

class _AddLotSheetState extends ConsumerState<_AddLotSheet> {
  String? _deviceId;
  LotMode _mode = LotMode.auction;
  final _price = TextEditingController(text: '1');
  final _floor = TextEditingController(text: '1');
  bool _busy = false;

  @override
  void dispose() {
    _price.dispose();
    _floor.dispose();
    super.dispose();
  }

  static double? _parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _add() async {
    final id = _deviceId;
    final price = _mode == LotMode.giveaway ? 0.0 : _parse(_price);
    final floor = _mode == LotMode.dutch ? _parse(_floor) : 1.0;
    if (id == null || price == null || floor == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(appProvider.notifier)
          .liveAddLot(widget.showId, id, price, mode: _mode, floorPrice: floor);
      if (mounted) Navigator.pop(context, true);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final show = s.liveShowById(widget.showId);
    final inShow = {...?show?.lots.map((l) => l.deviceId)};
    final eligible = s.myDevices
        .where(
          (d) =>
              !d.isDigital &&
              s.activeAuctionFor(d.id) == null &&
              !inShow.contains(d.id),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('Dodaj predmet u live'),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            // Popis i postavke se pomiču; gumb "Dodaj u live" je uvijek
            // vidljiv na dnu (na mobitelu je inače bio ispod ruba ekrana).
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RadioGroup<String>(
                      groupValue: _deviceId,
                      onChanged: (v) => setState(() => _deviceId = v),
                      child: Column(
                        children: [
                          for (final d in eligible)
                            RadioListTile<String>(
                              key: ValueKey('live-add-${d.id}'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              value: d.id,
                              secondary: ItemThumb(device: d, size: 40),
                              title: Text(
                                d.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                t('Vrijednost {0}', [formatCredits(d.price)]),
                              ),
                            ),
                          if (eligible.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                t('Nemaš slobodnih predmeta — dodaj novi.'),
                                style: TextStyle(
                                  color: LoopColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('live-add-new'),
                      onPressed: () => AddDeviceScreen.open(context),
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(t('Novi predmet')),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final m in LotMode.values)
                          ChoiceChip(
                            key: ValueKey('lot-mode-${m.name}'),
                            label: Text('${m.emoji} ${t(m.label)}'),
                            selected: _mode == m,
                            onSelected: (_) => setState(() => _mode = m),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        switch (_mode) {
                          LotMode.auction => t(
                            'Klasična licitacija — najviša ponuda pobjeđuje.',
                          ),
                          LotMode.dutch => t(
                            'Cijena pada svake sekunde — prvi koji klikne "Uzmi" kupuje.',
                          ),
                          LotMode.giveaway => t(
                            'Besplatno za sve koji se prijave — dobitnik se izvlači na kraju.',
                          ),
                        },
                        style: TextStyle(
                          color: LoopColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (_mode != LotMode.giveaway)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('live-add-price'),
                              controller: _price,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              decoration: InputDecoration(
                                labelText: t('Početna cijena'),
                                suffixText: t('€'),
                              ),
                            ),
                          ),
                          if (_mode == LotMode.dutch) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                key: const ValueKey('live-add-floor'),
                                controller: _floor,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  labelText: t('Najniža cijena'),
                                  suffixText: t('€'),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('live-add-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: kLiveRed,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _deviceId == null || _busy ? null : _add,
              child: Text(t('Dodaj u live')),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- video

/// Kamera domaćina se nije uključila: razlog i gumb za ponovni pokušaj.
class _CameraRetry extends StatelessWidget {
  const _CameraRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('live-camera-error'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(kRadius),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('live-camera-retry'),
          style: FilledButton.styleFrom(
            backgroundColor: kLiveRed,
            foregroundColor: Colors.white,
          ),
          onPressed: onRetry,
          icon: const Icon(Icons.videocam),
          label: Text(t('Uključi kameru')),
        ),
      ],
    ),
  );
}

/// Oznaka stanja videa (spajanje, pauza, broj gledatelja videa).
class _VideoStatus extends StatelessWidget {
  const _VideoStatus({
    required this.show,
    required this.broadcaster,
    required this.watcher,
    required this.online,
  });

  final LiveShow show;
  final LiveBroadcaster? broadcaster;
  final LiveWatcher? watcher;
  final bool online;

  Widget _pill(String text, {Key? key}) => Container(
    key: key,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!show.video) return const SizedBox.shrink();
    if (!online) {
      return _pill(
        t('📹 Video radi u online verziji'),
        key: const ValueKey('live-video-offline'),
      );
    }
    final b = broadcaster;
    if (b != null) {
      return ValueListenableBuilder<int>(
        valueListenable: b.watching,
        builder: (_, n, _) => _pill(
          t('📡 Video gleda {0}', ['$n']),
          key: const ValueKey('live-video-watching'),
        ),
      );
    }
    final w = watcher;
    if (w == null) return const SizedBox.shrink();
    return ValueListenableBuilder<LiveVideoStatus>(
      valueListenable: w.status,
      builder: (_, status, _) => switch (status) {
        LiveVideoStatus.playing => const SizedBox.shrink(),
        LiveVideoStatus.connecting => _pill(t('📹 Spajam video…')),
        LiveVideoStatus.offline => _pill(t('📹 Video trenutno nije uključen')),
        LiveVideoStatus.blocked => _pill(
          LiveVideoConfig.hasTurn
              ? t('📹 Video se ne spaja — pokušavam ponovno…')
              : t('📹 Video ne prolazi kroz ovu mrežu — probaj isti Wi-Fi'),
          key: const ValueKey('live-video-blocked'),
        ),
      },
    );
  }
}

/// Domaćin: okreni kameru, mikrofon, kamera uključena/isključena.
class _HostControls extends StatelessWidget {
  const _HostControls({required this.broadcaster});
  final LiveBroadcaster broadcaster;

  @override
  Widget build(BuildContext context) {
    final b = broadcaster;
    Widget button(
      String key,
      String tooltip,
      IconData icon,
      VoidCallback onTap, {
      bool off = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: off ? kLiveRed : Colors.black45,
        shape: const CircleBorder(),
        child: IconButton(
          key: ValueKey(key),
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white),
        ),
      ),
    );
    return Column(
      children: [
        button(
          'live-cam-flip',
          t('Okreni kameru'),
          Icons.cameraswitch_outlined,
          () async {
            try {
              await b.switchCamera();
              showLoopSnackBar(
                b.front.value ? t('Prednja kamera') : t('Stražnja kamera'),
              );
            } on LiveCameraException catch (e) {
              showLoopSnackBar(
                e.failed
                    ? t('Druga kamera se nije uključila. Pokušaj ponovno.')
                    : t('Ovaj uređaj ima samo jednu kameru.'),
                error: true,
              );
            } catch (_) {
              showLoopSnackBar(
                t('Kamera se ne može okrenuti na ovom uređaju.'),
                error: true,
              );
            }
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: b.micOn,
          builder: (_, on, _) => button(
            'live-mic',
            on ? t('Isključi mikrofon') : t('Uključi mikrofon'),
            on ? Icons.mic : Icons.mic_off,
            b.toggleMic,
            off: !on,
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: b.cameraOn,
          builder: (_, on, _) => button(
            'live-cam',
            on ? t('Isključi kameru') : t('Uključi kameru'),
            on ? Icons.videocam : Icons.videocam_off,
            b.toggleCamera,
            off: !on,
          ),
        ),
      ],
    );
  }
}
