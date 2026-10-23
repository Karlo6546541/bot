import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../providers/app_providers.dart';
import '../services/live_service.dart';
import '../services/live_video.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/countdown.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/story_canvas.dart';
import '../widgets/trade_actions.dart';
import '../widgets/live_video_view.dart';
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

class _ViewersChip extends StatelessWidget {
  const _ViewersChip(this.count);
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.visibility, size: 14, color: Colors.white),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------- pokretanje livea

/// Prodavatelj slaže live: naslov, predmeti s početnim cijenama (neobavezno —
/// mogu se dodavati i tijekom livea), trajanje licitacije i početak.
class CreateLiveShowScreen extends ConsumerStatefulWidget {
  const CreateLiveShowScreen({super.key});

  /// Testno: live se može pokrenuti odmah, bez podataka prodavatelja
  /// (traže se tek za isplatu zarade).
  static Future<void> open(BuildContext context) async {
    if (blockGuest(context)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CreateLiveShowScreen()),
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

  /// `null` = kreće odmah.
  DateTime? _startsAt;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggle(Device d) => setState(() {
    _error = null;
    if (_selected.remove(d.id)) return;
    if (_selected.length >= LiveShow.maxLots) {
      _error = t('Live može imati najviše {0} predmeta.', [
        '${LiveShow.maxLots}',
      ]);
      return;
    }
    _selected.add(d.id);
    // Kao na Whatnotu: licitacija kreće od 1 €.
    _prices.putIfAbsent(d.id, () => TextEditingController(text: '1'));
  });

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
    final later = _startsAt != null;
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
          ),
      successMessage: later ? t('Live je zakazan') : t('Uživo si! 🔴'),
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
    final bold = const TextStyle(fontWeight: FontWeight.w800);

    return Scaffold(
      appBar: AppBar(title: Text(t('Novi live'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF2D55), Color(0xFF8E2DE2)],
                  ),
                  borderRadius: BorderRadius.circular(kRadius),
                ),
                child: Row(
                  children: [
                    const Text('🔴', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t(
                          'Idi uživo, pokazuj predmete i pokreći licitacije. Live traje dok si uživo.',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('live-title'),
                controller: _title,
                maxLength: LiveShow.maxTitle,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: t('Naslov livea'),
                  hintText: t('npr. Retro igre od 1 €'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t('Predmeti ({0}/{1})', [
                  '${_selected.length}',
                  '${LiveShow.maxLots}',
                ]),
                style: bold,
              ),
              Text(
                t(
                  'Neobavezno: odaberi predmete unaprijed i upiši početnu cijenu. Predmete možeš dodavati i tijekom livea.',
                ),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 8),
              if (eligible.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    key: const ValueKey('live-new-item'),
                    onPressed: () => AddDeviceScreen.open(context),
                    icon: const Icon(Icons.add),
                    label: Text(t('Dodaj predmet')),
                  ),
                ),
              for (final d in eligible)
                _LotChoice(
                  device: d,
                  order: _selected.indexOf(d.id) + 1,
                  price: _prices[d.id],
                  onTap: () => _toggle(d),
                ),
              const SizedBox(height: 8),
              Material(
                color: LoopColors.surface,
                borderRadius: BorderRadius.circular(kRadius),
                child: SwitchListTile(
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
              ),
              const SizedBox(height: 16),
              Text(t('Licitacija po predmetu'), style: bold),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final sec in LiveShow.lotDurations)
                    ChoiceChip(
                      key: ValueKey('live-secs-$sec'),
                      label: Text(t('{0} s', ['$sec'])),
                      selected: _secs == sec,
                      onSelected: (_) => setState(() => _secs = sec),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(t('Početak'), style: bold),
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
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(formatDateTime(_startsAt!)),
                  subtitle: Text(t('Pratitelji dobivaju obavijest odmah.')),
                  trailing: TextButton(
                    onPressed: _pickTime,
                    child: Text(t('Promijeni')),
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
                    '• Live traje dok si uživo — završavaš ga ti (ili kad izađeš).\n• Ti biraš predmet i pokrećeš licitaciju od {0} s.\n• Ponuda u zadnjih 10 s vraća sat na 10 s.\n• Pobjednik plaća karticom, ti dobivaš cijelu ponudu.\n• Ako nitko ne ponudi, predmet ostaje tebi.',
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: LiveRoomView(showId: showId),
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

  static const _reactions = ['🔥', '👏', '😍', '💸'];

  AppController get _app => ref.read(appProvider.notifier);

  @override
  void initState() {
    super.initState();
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
      setState(() => _broadcaster = b);
      try {
        await b.start();
      } catch (_) {
        if (mounted) setState(() => _broadcaster = null);
        await b.stop();
        showLoopSnackBar(
          t('Dopusti pristup kameri i mikrofonu da gledatelji vide video.'),
          error: true,
        );
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

  Future<void> _bid(double amount) async {
    if (blockGuest(context) || _busy) return;
    setState(() => _busy = true);
    try {
      // Bez potvrde u SnackBaru (prekrio bi chat) — gumb postaje "Vodiš".
      await _app.liveBid(widget.showId, amount);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _take() async {
    if (blockGuest(context) || _busy) return;
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
    setState(() => _busy = true);
    try {
      await _app.liveEnter(widget.showId);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Pogodi cijenu": tko je najbliže konačnoj cijeni, dobiva priznanje u
  /// sobi (Whatnot to nema).
  Future<void> _guess() async {
    if (blockGuest(context)) return;
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('🎯 Pogodi konačnu cijenu')),
        content: TextField(
          key: const ValueKey('live-guess-amount'),
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            suffixText: t('€'),
            helperText: t('Najbliži pogodak se objavljuje u sobi'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Odustani')),
          ),
          FilledButton(
            key: const ValueKey('live-guess-ok'),
            onPressed: () => Navigator.pop(
              ctx,
              double.tryParse(controller.text.trim().replaceAll(',', '.')),
            ),
            child: Text(t('Pošalji')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;
    try {
      await _app.liveGuess(widget.showId, amount);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    }
  }

  Future<void> _customBid(double min) async {
    if (blockGuest(context)) return;
    final controller = TextEditingController(
      text: min == min.roundToDouble()
          ? min.toStringAsFixed(0)
          : min.toStringAsFixed(2),
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Tvoja ponuda')),
        content: TextField(
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
            child: Text(t('Licitiraj')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount != null && mounted) await _bid(amount);
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
          const SizedBox(height: 8),
          for (final l in st.lots)
            _QueueRow(
              lot: l,
              onStart: isHost && st.canStart && l.status == LotStatus.upcoming
                  ? () {
                      Navigator.pop(ctx);
                      _startLot(l.index);
                    }
                  : null,
            ),
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
    } else if (cur == null && done != null) {
      // Pauza između predmeta: rezultat prethodnog i što slijedi.
      final winner = done.leader;
      final iWon = winner != null && winner.userId == me?.id;
      center = _Panel(
        key: const ValueKey('live-result'),
        children: [
          Text(
            switch ((done.mode, winner == null, iWon)) {
              (LotMode.giveaway, true, _) => t('Nitko se nije prijavio'),
              (_, true, _) => t('Nije prodano'),
              (LotMode.giveaway, _, true) => t('🎁 Osvojio si nagradu!'),
              (LotMode.giveaway, _, false) => t('🎁 Izvučen je dobitnik!'),
              (_, _, true) => t('🏆 Osvojio si!'),
              _ => t('🎉 PRODANO!'),
            },
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 24,
            ),
          ),
          if (winner != null)
            Text(
              done.mode == LotMode.giveaway
                  ? winner.userLabel
                  : '${winner.userLabel} · ${formatCredits(done.price)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (done.guessWinner case final g?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                g.userId == me?.id
                    ? t('🎯 Najbliže si pogodio cijenu ({0})', [
                        formatCredits(g.amount),
                      ])
                    : t('🎯 {0} je najbliže pogodio cijenu ({1})', [
                        g.userLabel,
                        formatCredits(g.amount),
                      ]),
                key: const ValueKey('live-guess-winner'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFC233)),
              ),
            ),
          if (iWon)
            Text(
              t('Odaberi dostavu u Obavijestima.'),
              style: const TextStyle(color: Colors.white70),
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
    } else if (cur == null) {
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
            fallback: StoryBackdrop(
              gradient: _stageGradient(stageDevice),
              device: stageDevice,
            ),
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
                      hostName: host?.handle ?? show.hostLabel,
                      hostAvatar: UserAvatar(user: host, size: 36),
                      onQueue: () => _showQueue(st, isHost),
                    ),
                    if (st.isLive) _HypeMeter(st.hype),
                    Expanded(
                      child: Stack(
                        children: [
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: center,
                            ),
                          ),
                          Positioned(
                            left: 12,
                            top: 4,
                            child: _VideoStatus(
                              show: show,
                              broadcaster: _broadcaster,
                              watcher: _watcher,
                              online: ref.watch(liveSignalingProvider) != null,
                            ),
                          ),
                          if (_broadcaster case final b?)
                            Positioned(
                              right: 8,
                              top: 4,
                              child: _HostControls(broadcaster: b),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: _ChatFeed(feed: st.feed, me: me?.id),
                    ),
                    if (cur != null)
                      _LotCard(
                        lot: cur,
                        device: s.deviceById(cur.lot.deviceId),
                        total: show.lots.length,
                        lotSeconds: show.lotSeconds,
                        now: now,
                        me: me?.id,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: _actions(show, st, cur, isHost, canAct, me?.id),
                    ),
                    if (canAct && !st.isOver)
                      _ChatInput(
                        controller: _chat,
                        reactions: _reactions,
                        onSend: _send,
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
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      );
      final end = OutlinedButton(
        key: const ValueKey('live-end'),
        style: outlined,
        onPressed: () => _end(st.isScheduled),
        child: Text(st.isScheduled ? t('Otkaži') : t('Završi')),
      );
      if (st.isScheduled) return Align(alignment: Alignment.center, child: end);
      final next = st.next;
      return Row(
        children: [
          Expanded(
            child: cur == null && next == null
                ? FilledButton.icon(
                    key: const ValueKey('live-add-first'),
                    style: FilledButton.styleFrom(
                      backgroundColor: kLiveRed,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: () => _addItem(show),
                    icon: const Icon(Icons.add),
                    label: Text(t('Dodaj predmet')),
                  )
                : FilledButton.icon(
                    key: const ValueKey('live-start-next'),
                    style: FilledButton.styleFrom(
                      backgroundColor: kLiveRed,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white24,
                      disabledForegroundColor: Colors.white70,
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: st.canStart && next != null
                        ? () => _startLot(next.index)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      cur != null
                          ? t('Licitacija traje…')
                          : t('Licitiraj: {0}', [next!.lot.deviceName]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
          if (cur != null || next != null) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              key: const ValueKey('live-add-item'),
              style: outlined,
              onPressed: () => _addItem(show),
              child: const Icon(Icons.add),
            ),
          ],
          const SizedBox(width: 8),
          end,
        ],
      );
    }
    if (cur == null) return const SizedBox.shrink();
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
    final guessed = cur.guesses.any((g) => g.userId == me);
    final guessButton = guessed
        ? Text(
            t('🎯 Tvoja procjena: {0}', [
              formatCredits(
                cur.guesses.firstWhere((g) => g.userId == me).amount,
              ),
            ]),
            style: const TextStyle(color: Color(0xFFFFC233), fontSize: 12),
          )
        : TextButton.icon(
            key: const ValueKey('live-guess'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFFC233),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _guess,
            icon: const Text('🎯'),
            label: Text(t('Pogodi konačnu cijenu')),
          );
    if (cur.leader?.userId == me) {
      return Column(children: [_leading(cur), guessButton]);
    }
    return Column(children: [_bidRow(cur), guessButton]);
  }

  Widget _leading(LotState cur) {
    return Container(
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
                child: Text(t('Iznos')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          t('Ponuda je obvezujuća · plaćaš karticom ako pobijediš'),
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
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
    final guessers = [
      for (final l in state.lots)
        if (l.status == LotStatus.sold) ?l.guessWinner,
    ];
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
          if (guessers.isNotEmpty)
            row(
              '🎯',
              t('Najbolji pogađači: {0}', [
                {for (final g in guessers) g.userLabel}.join(', '),
              ]),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.show,
    required this.state,
    required this.hostName,
    required this.hostAvatar,
    required this.onQueue,
  });

  final LiveShow show;
  final LiveState state;
  final String hostName;
  final Widget hostAvatar;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = state.queue.length;
    final me = ref.watch(appProvider.select((s) => s.currentUserId));
    final following = ref.watch(
      appProvider.select((s) => s.isFollowing(show.hostId)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('live-close'),
            tooltip: t('Zatvori'),
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
          GestureDetector(
            onTap: () => PublicProfileScreen.open(context, show.hostId),
            child: hostAvatar,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        hostName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (me != null && me != show.hostId && !following) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(99),
                            child: InkWell(
                              key: const ValueKey('live-follow'),
                              borderRadius: BorderRadius.circular(99),
                              onTap: () async {
                                if (blockGuest(context)) return;
                                await ref
                                    .read(appProvider.notifier)
                                    .toggleFollow(show.hostId);
                                showLoopSnackBar(t('Pratiš {0}', [hostName]));
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                child: Text(
                                  t('Prati'),
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  show.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (state.isLive) ...[
            const LiveBadge(),
            const SizedBox(width: 6),
            _ViewersChip(state.viewers),
          ] else
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
            key: const ValueKey('live-share'),
            tooltip: t('Podijeli live'),
            visualDensity: VisualDensity.compact,
            onPressed: () => shareLink(
              context,
              publicLink(live: show.id),
              text: t('Gledaj "{0}" uživo na LICIT-u', [show.title]),
            ),
            icon: const Icon(Icons.ios_share, color: Colors.white, size: 20),
          ),
          IconButton(
            key: const ValueKey('live-queue'),
            tooltip: t('Predmeti u liveu'),
            visualDensity: VisualDensity.compact,
            onPressed: onQueue,
            icon: Badge(
              isLabelVisible: upcoming > 0,
              label: Text('$upcoming'),
              child: const Icon(
                Icons.format_list_numbered,
                color: Colors.white,
              ),
            ),
          ),
        ],
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

/// Predmet koji se licitira: cijena, tko vodi i odbrojavanje.
class _LotCard extends StatelessWidget {
  const _LotCard({
    required this.lot,
    required this.device,
    required this.total,
    required this.lotSeconds,
    required this.now,
    required this.me,
  });

  final LotState lot;
  final Device? device;
  final int total;
  final int lotSeconds;
  final DateTime now;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final left = lot.left(now);
    final secs = (left.inMilliseconds / 1000).ceil();
    final hot = left <= LiveShow.suddenDeath && lot.mode == LotMode.auction;
    final leader = lot.leader;
    final d = device;
    final price = switch (lot.mode) {
      LotMode.auction => lot.price,
      LotMode.dutch => lot.dutchPriceAt(now, lotSeconds),
      LotMode.giveaway => 0.0,
    };
    // Procjena vrijednosti (vrijednost predmeta) — toga na Whatnotu nema.
    final value = d?.price ?? 0;
    final below = value > 0 && price > 0 && price < value
        ? ((1 - price / value) * 100).round()
        : 0;
    return Container(
      key: const ValueKey('live-lot'),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: hot ? kLiveRed : Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (d != null) ItemThumb(device: d, size: 40),
              if (d != null) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lot.lot.deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      switch (lot.mode) {
                        LotMode.dutch => t('⬇️ Pada cijena · do {0}', [
                          formatCredits(lot.lot.floorPrice),
                        ]),
                        LotMode.giveaway => t(
                          '🎁 Nagradna igra · {0} prijava',
                          ['${lot.entrants}'],
                        ),
                        LotMode.auction =>
                          leader == null
                              ? t('Predmet {0}/{1} · još nema ponuda', [
                                  '${lot.index + 1}',
                                  '$total',
                                ])
                              : leader.userId == me
                              ? t('🥇 Ti vodiš')
                              : t('🥇 {0} vodi', [leader.userLabel]),
                      },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
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
                    ),
                  ),
                  Text(
                    '0:${secs.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: hot ? kLiveRed : Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (left.inMilliseconds / (lotSeconds * 1000)).clamp(0, 1),
              minHeight: 4,
              color: hot ? kLiveRed : Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
          if (value > 0) ...[
            const SizedBox(height: 6),
            Wrap(
              key: const ValueKey('live-value'),
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  t('💎 Procjena {0}', [formatCredits(value)]),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                if (below >= 5) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1FA463),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      t('−{0}% ispod procjene', ['$below']),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (hot) ...[
            const SizedBox(height: 4),
            Text(
              t('⚡ Ponuda sada vraća sat na 10 s'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Zadnje poruke i ponude (starije blijede).
class _ChatFeed extends StatelessWidget {
  const _ChatFeed({required this.feed, required this.me});

  final List<LiveEvent> feed;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final last = feed.length > 6 ? feed.sublist(feed.length - 6) : feed;
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        key: const ValueKey('live-feed'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < last.length; i++)
            Opacity(
              opacity: 0.45 + 0.55 * (i + 1) / last.length,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _FeedLine(event: last[i], mine: last[i].userId == me),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedLine extends StatelessWidget {
  const _FeedLine({required this.event, required this.mine});
  final LiveEvent event;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final bid = event.type == LiveEventType.bid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bid ? kLiveRed.withValues(alpha: 0.85) : Colors.black45,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: mine ? t('Ti') : event.userLabel,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(
              text: bid
                  ? t(' licitira {0}', [formatCredits(event.amount)])
                  : '  ${event.text}',
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.reactions,
    required this.onSend,
  });

  final TextEditingController controller;
  final List<String> reactions;
  final Future<void> Function(String) onSend;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
    child: Row(
      children: [
        Expanded(
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
              hintText: t('Napiši nešto…'),
              hintStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: Colors.white12,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(99),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(99),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(99),
                borderSide: const BorderSide(color: Colors.white54),
              ),
              suffixIcon: IconButton(
                key: const ValueKey('live-send'),
                tooltip: t('Pošalji'),
                onPressed: () => onSend(controller.text),
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
        for (var i = 0; i < reactions.length; i++)
          IconButton(
            key: ValueKey('live-react-$i'),
            visualDensity: VisualDensity.compact,
            onPressed: () => onSend(reactions[i]),
            icon: Text(reactions[i], style: const TextStyle(fontSize: 20)),
          ),
      ],
    ),
  );
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.lot, this.onStart});
  final LotState lot;

  /// Domaćin: pokreni licitaciju ovog predmeta.
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final l = lot;
    final (String status, Color color) = switch (l.status) {
      LotStatus.running => (t('🔴 Licitira se'), kLiveRed),
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
          : Text(
              status,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
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
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: RadioGroup<String>(
                groupValue: _deviceId,
                onChanged: (v) => setState(() => _deviceId = v),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in eligible)
                      RadioListTile<String>(
                        key: ValueKey('live-add-${d.id}'),
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
                          style: TextStyle(color: LoopColors.textSecondary),
                        ),
                      ),
                  ],
                ),
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
              child: Text(switch (_mode) {
                LotMode.auction => t(
                  'Klasična licitacija — najviša ponuda pobjeđuje.',
                ),
                LotMode.dutch => t(
                  'Cijena pada svake sekunde — prvi koji klikne "Uzmi" kupuje.',
                ),
                LotMode.giveaway => t(
                  'Besplatno za sve koji se prijave — dobitnik se izvlači na kraju.',
                ),
              }, style: TextStyle(color: LoopColors.textSecondary, fontSize: 12)),
            ),
            if (_mode != LotMode.giveaway)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('live-add-price'),
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
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
