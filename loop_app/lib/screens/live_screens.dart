import '../config/design_variant.dart';
import '../widgets/vision_live_controls.dart';
import 'device_detail_screen.dart';
import '../widgets/live_shop_widgets.dart' show liveShopProducts;
import '../widgets/vision_glass.dart';
import 'host_console.dart';
import '../config/backend_config.dart';
import 'cloud_commerce_screen.dart';
import 'package:uuid/uuid.dart';
import '../config/features.dart';
import '../services/app_location/app_location.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../widgets/trust_widgets.dart';
import '../models/app_user.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/live_service.dart';
import '../services/live_sound/live_sound.dart';
import '../services/live_video.dart';
import '../services/trade_service.dart';
import '../models/live_boost.dart';
import 'live_promote_sheet.dart';
import 'show_checklist_screen.dart';
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
import 'deliveries_screen.dart';
import 'public_profile_screen.dart';
import 'seller_screens.dart' show ensureSellerInfo;

/// Crvena boja live aukcija (oznaka UŽIVO, gumb za licitiranje).
const kLiveRed = LoopColors.live;

/// Pozadina listova u liveu (live je uvijek taman).
const kLiveSheet = Color(0xF21C1C22);

/// Plava za radnje u liveu; crvena označava emitiranje uživo.
const kBidOrange = Color(0xFF0066CC);
const _defaultStage = [Color(0xFF28282D), Color(0xFF08080A)];

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
/// Popis gledatelja (Gledaju / Aktivnost). Domaćin i moderatori mogu
/// utišati ili ukloniti gledatelja; samo domaćin postavlja moderatore.
class _ViewersSheet extends ConsumerWidget {
  const _ViewersSheet({required this.showId, this.embedded = false});
  final String showId;

  /// Ugrađeno u pult (desni stupac): bez fiksne visine lista.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final show = s.liveShowById(showId);
    if (show == null) return const SizedBox.shrink();
    final st = s.liveStateOf(show, DateTime.now());
    final me = s.currentUserId;
    final canMod = show.canModerate(me);
    final isHost = show.hostId == me;
    final app = ref.read(appProvider.notifier);

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } on TradeException catch (e) {
        showLoopSnackBar(e.message, error: true);
      }
    }

    Widget row(String userId) {
      final u = s.userById(userId);
      final muted = st.muted.contains(userId);
      final banned = st.banned.contains(userId);
      final mod = show.isMod(userId);
      final canAct = canMod && userId != me && (isHost || !mod);
      return ListTile(
        key: ValueKey('viewer-$userId'),
        dense: true,
        leading: UserAvatar(user: u, size: 32),
        title: Text(
          u?.handle ?? '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          [
            if (mod) t('Moderator'),
            if (muted) t('Utišan'),
            if (banned) t('Uklonjen'),
          ].join(' · '),
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: canAct
            ? PopupMenuButton<String>(
                key: ValueKey('viewer-menu-$userId'),
                icon: const Icon(Icons.more_vert, color: Colors.white70),
                onSelected: (v) => run(() async {
                  switch (v) {
                    case 'mute':
                      await app.liveModerate(showId, modMute, userId);
                    case 'unmute':
                      await app.liveModerate(showId, modUnmute, userId);
                    case 'ban':
                      await app.liveModerate(showId, modBan, userId);
                    case 'mod':
                      await app.liveSetMod(showId, userId, !mod);
                  }
                }),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    key: ValueKey('viewer-${muted ? 'unmute' : 'mute'}'),
                    value: muted ? 'unmute' : 'mute',
                    child: Text(muted ? t('Vrati glas') : t('Utišaj u chatu')),
                  ),
                  PopupMenuItem(
                    key: const ValueKey('viewer-ban'),
                    value: 'ban',
                    child: Text(t('Ukloni iz showa')),
                  ),
                  if (isHost)
                    PopupMenuItem(
                      key: const ValueKey('viewer-mod'),
                      value: 'mod',
                      child: Text(
                        mod
                            ? t('Skini moderatora')
                            : t('Postavi za moderatora'),
                      ),
                    ),
                ],
              )
            : null,
      );
    }

    String when(LiveEvent e) {
      final what = switch (e.type) {
        LiveEventType.bid => t('licitira {0}', [formatCredits(e.amount)]),
        LiveEventType.take => t('uzima'),
        LiveEventType.enter => t('prijavljen na nagradnu igru'),
        _ => t('ušao/ušla'),
      };
      return '${e.userLabel} $what';
    }

    return DefaultTabController(
      length: 2,
      child: SizedBox(
        height: embedded ? null : MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            TabBar(
              indicatorColor: LoopColors.accent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: [
                Tab(
                  key: const ValueKey('viewers-tab-watching'),
                  text: t('Gledaju ({0})', ['${st.viewerIds.length}']),
                ),
                Tab(
                  key: const ValueKey('viewers-tab-activity'),
                  text: t('Aktivnost'),
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  st.viewerIds.isEmpty
                      ? Center(
                          child: Text(
                            t('Još nitko ne gleda.'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView(
                          children: [for (final id in st.viewerIds) row(id)],
                        ),
                  st.activity.isEmpty
                      ? Center(
                          child: Text(
                            t('Još nema aktivnosti.'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final e in st.activity)
                              ListTile(
                                dense: true,
                                title: Text(
                                  when(e),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                trailing: Text(
                                  formatDateTime(e.at),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flash ponuda: kratki popust na predmet s fiksnom cijenom koji vrijedi
/// uz aukciju. Gledatelji vide traku s odbrojavanjem i kupuju jednim dodirom.
Future<void> showFlashSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: kLiveSheet,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => const _FlashSheet(),
    );

class _FlashSheet extends ConsumerStatefulWidget {
  const _FlashSheet();

  @override
  ConsumerState<_FlashSheet> createState() => _FlashSheetState();
}

class _FlashSheetState extends ConsumerState<_FlashSheet> {
  String? _deviceId;
  int _percent = 20;
  int _seconds = 60;
  bool _busy = false;

  Future<void> _start() async {
    final id = _deviceId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(appProvider.notifier)
          .setDiscount(id, _percent, duration: Duration(seconds: _seconds));
      showLoopSnackBar(t('Flash ponuda je počela!'));
      if (mounted) Navigator.pop(context);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId ?? '';
    final items = [
      for (final d in s.listingsOf(me))
        if (!d.isDigital) d,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Flash ponuda'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'Kratki popust na predmet s fiksnom cijenom. Aukcija teče dalje.',
              ),
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final p in const [10, 20, 30, 50])
                  ChoiceChip(
                    key: ValueKey('flash-pct-$p'),
                    label: Text('−$p %'),
                    selected: _percent == p,
                    onSelected: (_) => setState(() => _percent = p),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final sec in const [30, 60, 120, 300])
                  ChoiceChip(
                    key: ValueKey('flash-secs-$sec'),
                    label: Text(
                      sec < 60
                          ? t('{0} s', ['$sec'])
                          : t('{0} min', ['${sec ~/ 60}']),
                    ),
                    selected: _seconds == sec,
                    onSelected: (_) => setState(() => _seconds = sec),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              t('Predmet'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  t('Nemaš predmeta na Kupi odmah.'),
                  style: const TextStyle(color: Colors.white60),
                ),
              )
            else
              RadioGroup<String>(
                groupValue: _deviceId,
                onChanged: (v) => setState(() => _deviceId = v),
                child: Column(
                  children: [
                    for (final d in items.take(30))
                      RadioListTile<String>(
                        key: ValueKey('flash-item-${d.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          d.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          formatCredits(d.askPrice),
                          style: const TextStyle(color: Colors.white60),
                        ),
                        value: d.id,
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('flash-start'),
              style: FilledButton.styleFrom(
                backgroundColor: kLiveRed,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _busy || _deviceId == null ? null : _start,
              icon: const Icon(Icons.bolt),
              label: Text(t('Pokreni flash')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Traka s aktivnom flash ponudom domaćina (odbrojavanje + Kupi).
class _FlashBar extends ConsumerWidget {
  const _FlashBar({required this.hostId, required this.now});
  final String hostId;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final flash = [
      for (final d in s.listingsOf(hostId))
        if (!d.isDigital &&
            d.discountUntil != null &&
            d.discountActiveAt(now) &&
            d.discountUntil!.difference(now) <= const Duration(minutes: 10))
          d,
    ];
    if (flash.isEmpty) return const SizedBox.shrink();
    final d = flash.first;
    final mine = s.currentUserId == hostId;
    return Padding(
      key: const ValueKey('live-flash-bar'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xE6FF2D55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t('Flash −{0} % · {1}', ['${d.discountPercent}', d.name]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        formatCredits(d.priceAt(now)),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AuctionCountdown(
                        endsAt: d.discountUntil!,
                        showIcon: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!mine)
              FilledButton(
                key: const ValueKey('live-flash-buy'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(72, 40),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => confirmAndBuy(context, ref, d),
                child: Text(t('Kupi')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Giveaway (nagradna igra): predmet, trajanje do 5 minuta i "samo
/// pratitelji". Pokreće se odmah ako ništa drugo ne teče, inače ide na red.
Future<void> showGiveawaySheet(
  BuildContext context,
  WidgetRef ref,
  LiveShow show,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: kLiveSheet,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => _GiveawaySheet(showId: show.id),
  );
}

class _GiveawaySheet extends ConsumerStatefulWidget {
  const _GiveawaySheet({required this.showId});
  final String showId;

  @override
  ConsumerState<_GiveawaySheet> createState() => _GiveawaySheetState();
}

class _GiveawaySheetState extends ConsumerState<_GiveawaySheet> {
  String? _deviceId;
  int _seconds = 120;
  bool _followersOnly = false;
  bool _busy = false;

  Future<void> _start() async {
    final id = _deviceId;
    if (id == null) return;
    setState(() => _busy = true);
    final app = ref.read(appProvider.notifier);
    try {
      await app.liveAddLot(
        widget.showId,
        id,
        0,
        mode: LotMode.giveaway,
        seconds: _seconds,
        followersOnly: _followersOnly,
      );
      final s = ref.read(appProvider);
      final show = s.liveShowById(widget.showId)!;
      final st = s.liveStateOf(show, DateTime.now());
      if (st.canStart) {
        await app.liveStartLot(widget.showId, index: show.lots.length - 1);
        showLoopSnackBar(t('Giveaway je počeo!'));
      } else {
        showLoopSnackBar(t('Giveaway je dodan na red.'));
      }
      if (mounted) Navigator.pop(context);
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
          (d) => s.activeAuctionFor(d.id) == null && !inShow.contains(d.id),
        )
        .toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('Giveaway'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'Gledatelji se prijave, a dobitnik se izvlači na kraju. Pošiljku plaćaš ti.',
              ),
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final sec in LiveLot.giveawaySeconds)
                  ChoiceChip(
                    key: ValueKey('giveaway-secs-$sec'),
                    label: Text(t('{0} min', ['${sec ~/ 60}'])),
                    selected: _seconds == sec,
                    onSelected: (_) => setState(() => _seconds = sec),
                  ),
              ],
            ),
            SwitchListTile(
              key: const ValueKey('giveaway-followers'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                t('Samo pratitelji'),
                style: const TextStyle(color: Colors.white),
              ),
              value: _followersOnly,
              onChanged: (v) => setState(() => _followersOnly = v),
            ),
            const SizedBox(height: 4),
            Text(
              t('Predmet'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (eligible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  t('Nemaš predmeta koje možeš pokloniti.'),
                  style: const TextStyle(color: Colors.white60),
                ),
              )
            else
              RadioGroup<String>(
                groupValue: _deviceId,
                onChanged: (v) => setState(() => _deviceId = v),
                child: Column(
                  children: [
                    for (final d in eligible.take(30))
                      RadioListTile<String>(
                        key: ValueKey('giveaway-item-${d.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          d.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        value: d.id,
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('giveaway-start'),
              style: FilledButton.styleFrom(
                backgroundColor: kLiveRed,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _busy || _deviceId == null ? null : _start,
              icon: const Icon(Icons.card_giftcard),
              label: Text(t('Pokreni giveaway')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zadnji brzo dodani predmet ("Ponovi zadnji").
(String, double)? _lastQuickAdd;

/// "Dodaj predmet" u live ili zakazani show: jedan prozor — novi predmet
/// (naziv i cijena, sprema se sam), svoj predmet jednim dodirom ili
/// brojevi na ekranu (#150, #151…).
Future<void> showAddToShowSheet(
  BuildContext context,
  WidgetRef ref,
  LiveShow show,
) async {
  final r = await showModalBottomSheet<_AddResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: kLiveSheet,
    constraints: BoxConstraints(
      maxWidth: 520,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (_) =>
        appThemed(_QuickAddSheet(showId: show.id, last: _lastQuickAdd)),
  );
  if (r == null || !context.mounted) return;
  final app = ref.read(appProvider.notifier);
  if (r.onScreen) {
    final lot = await showModalBottomSheet<_DraftLot>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => appThemed(
        _OnScreenSheet(start: LiveService.nextOnScreen(show)?.number ?? 1),
      ),
    );
    if (lot == null || !context.mounted) return;
    await runWithLoading(context, () async {
      final d = await app.addDevice(
        name: lot.name,
        model: '',
        condition: DeviceCondition.good,
        price: lot.price,
        category: DeviceCategory.fromName(show.category),
        listOnMarket: false,
      );
      await app.liveAddLot(
        show.id,
        d.id,
        lot.price,
        name: '${lot.name} #${lot.from}',
      );
    }, successMessage: t('Brojevi su spremni u liveu.'));
    return;
  }
  final category =
      suggestCategory(r.name) ??
      DeviceCategory.values.firstWhere(
        (c) => c.name == show.category,
        orElse: () => DeviceCategory.other,
      );
  final ok = await runWithLoading(context, () async {
    final id =
        r.deviceId ??
        (await app.addDevice(
          name: r.name,
          model: '',
          condition: DeviceCondition.good,
          price: r.price,
          category: category,
          listOnMarket: false,
        )).id;
    await app.liveAddLot(show.id, id, r.price);
  }, successMessage: null);
  if (!ok) return;
  if (r.deviceId == null) _lastQuickAdd = (r.name, r.price);
  showLoopSnackBar(t('Predmet je dodan u live.'));
}

/// Gledatelji i aktivnost ugrađeni u pult za voditelja.
class ViewersPanel extends StatelessWidget {
  const ViewersPanel({super.key, required this.showId});
  final String showId;

  @override
  Widget build(BuildContext context) =>
      _ViewersSheet(showId: showId, embedded: true);
}

// ---------------------------------------------------------- pokretanje livea

/// Prodavatelj slaže live kao na Whatnotu: naslovna slika, naslov,
/// kategorija, početak (odmah ili zakazano), predmeti (neobavezno — mogu se
/// dodavati i tijekom livea) i postavke.
class CreateLiveShowScreen extends ConsumerStatefulWidget {
  const CreateLiveShowScreen({super.key, this.deviceId});

  /// Predmet koji je odmah odabran (npr. "Novi predmet → Live").
  final String? deviceId;

  static Future<void> open(BuildContext context, {String? deviceId}) async {
    if (blockGuest(context, place: 'new=live')) return;
    if (!await ensureSellerInfo(context) || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const AppPlace('new=live').settings,
        builder: (_) => CreateLiveShowScreen(deviceId: deviceId),
      ),
    );
  }

  @override
  ConsumerState<CreateLiveShowScreen> createState() =>
      _CreateLiveShowScreenState();
}

class _CreateLiveShowScreenState extends ConsumerState<CreateLiveShowScreen> {
  final _creationRequest = const Uuid().v4();
  final _title = TextEditingController();

  /// Odabrani predmeti redom kojim će se licitirati.
  final _selected = <String>[];

  /// Predmeti ovog livea (brzo dodani ili "items on screen") — spremaju se
  /// tek kad live krene.
  final _drafts = <_DraftLot>[];
  final _prices = <String, TextEditingController>{};
  int _secs = 30;

  /// Domaćin prenosi video s kamere (kao na Whatnotu).
  bool _video = true;

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

  int get _free => _maxLots - _selected.length - _drafts.length;

  Future<void> _addQuick() async {
    if (_free <= 0) {
      setState(
        () =>
            _error = t('Live može imati najviše {0} predmeta.', ['$_maxLots']),
      );
      return;
    }
    final lot = await showModalBottomSheet<_DraftLot>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => const _QuickLotSheet(),
    );
    if (lot != null && mounted) {
      setState(() {
        _error = null;
        _drafts.add(lot);
      });
    }
  }

  Future<void> _addOnScreen() async {
    if (_free <= 0) {
      setState(
        () =>
            _error = t('Live može imati najviše {0} predmeta.', ['$_maxLots']),
      );
      return;
    }
    // Nastavi brojanje od zadnjeg niza.
    var next = 1;
    for (final l in _drafts.reversed) {
      if (l.last case final last?) {
        next = last + 1;
        break;
      }
    }
    final lot = await showModalBottomSheet<_DraftLot>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _OnScreenSheet(start: next),
    );
    if (lot != null && mounted) {
      setState(() {
        _error = null;
        _drafts.add(lot);
      });
    }
  }

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
    if (blockGuest(context, place: 'new=live')) return;
    if (!await ensureSellerInfo(context) || !mounted) return;
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
    String? onlineRoom;
    final backend = BackendConfig.cloudLiveEnabled
        ? ref.read(preparedLiveBackendProvider)
        : null;
    final app = ref.read(appProvider.notifier);
    final ok = await runWithLoading(
      context,
      () async {
        if (backend != null) {
          final state = ref.read(appProvider);
          final lots = <Map<String, dynamic>>[];
          for (final (id, price) in items) {
            final d = state.deviceById(id);
            if (d == null) throw StateError('ITEM_NOT_FOUND');
            lots.add({
              'title': '${d.name} ${d.model}'.trim(),
              'start_cents': (price * 100).round(),
              'source_device_id': id,
              'image_url': d.imagePaths.firstOrNull,
            });
          }
          for (final draft in _drafts) {
            for (var k = 0; k < draft.count; k++) {
              lots.add({
                'title': draft.onScreen
                    ? '${draft.name} #${draft.from! + k}'
                    : draft.name,
                'start_cents': (draft.price * 100).round(),
                'image_url': draft.photo,
              });
            }
          }
          final room = await backend.prepareRoom(
            title: _title.text,
            category:
                (_category ??
                        suggestCategory(_title.text) ??
                        DeviceCategory.other)
                    .name,
            cover: _cover,
            startsAt: _startsAt,
            seconds: _secs,
            video: _video,
            lots: lots,
            requestId: _creationRequest,
          );
          onlineRoom = room['id'] as String;
          return;
        }
        // Predmeti ovog livea: tek sad se spremaju (redom). Items on
        // screen = jedan predmet s više komada; svaki broj je jedna
        // licitacija (#150, #151…).
        final all = [...items];
        final names = <String?>[for (final _ in items) null];
        for (final l in _drafts) {
          final d = await app.addDevice(
            name: l.name,
            model: '',
            condition: DeviceCondition.good,
            price: l.price,
            category:
                _category ?? suggestCategory(l.name) ?? DeviceCategory.other,
            imagePaths: [?l.photo],
            listOnMarket: false,
            quantity: l.count,
          );
          for (var k = 0; k < l.count; k++) {
            all.add((d.id, l.price));
            names.add(l.onScreen ? '${l.name} #${l.from! + k}' : null);
          }
        }
        created = await app.createLiveShow(
          title: _title.text,
          items: all,
          names: names,
          lotSeconds: _secs,
          startsAt: _startsAt,
          video: _video,
          coverPath: _cover,
          category: _category ?? suggestCategory(_title.text),
          // Neprodano ostaje spremljeno u Moje (ne ide samo na Kupi odmah).
          relistUnsold: false,
          sells: _sells,
          shop: _shop,
        );
        // Promocija odabrana u čarobnjaku (plaća se karticom).
        if (_promo > 0) {
          try {
            await app.liveBoost(
              created!.id,
              _startsAt == null ? BoostKind.quick : BoostKind.show,
              _promo.toDouble(),
            );
          } on TradeException catch (e) {
            showLoopSnackBar(e.message, error: true);
          }
        }
      },
      // Bez obavijesti: soba se odmah otvara (obavijest bi prekrila gumbe
      // na dnu sobe).
      successMessage: null,
    );
    if (!ok || !mounted) return;
    if (onlineRoom != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          settings: AppPlace('cloud=live&room=$onlineRoom').settings,
          builder: (_) => CloudCommerceScreen(
            initialRoom: onlineRoom,
            liveOnly: true,
            client: backend!.client,
          ),
        ),
      );
      return;
    }
    if (created == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => _startsAt != null
            // Zakazani show: popis pripreme (predmeti, kupci, kreni).
            ? ShowChecklistScreen(showId: created!.id)
            : LiveRoomScreen(showId: created!.id),
      ),
    );
  }

  /// Što se prodaje: stvari (aukcije), digitalno (Kupi odmah) ili oboje.
  final LiveSells _sells = LiveSells.physical;

  /// Kupi odmah iz prodavačeve trgovine u liveu (zadano isključeno).
  bool _shop = false;

  /// Promocija odmah pri kreiranju: iznos u € (0 = bez promocije).
  int _promo = 0;

  /// Korak čarobnjaka (0…[_steps] - 1).
  int _step = 0;
  static const _steps = 2;

  /// Smije li se na sljedeći korak.
  bool get _canNext => _step != 0 || _title.text.trim().length >= 3;

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _error = null;
        _step--;
      });
    }
  }

  Widget _heading(String title, [String? subtitle]) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 30,
            height: 1.1,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 15),
          ),
        ],
      ],
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        color: LoopColors.textSecondary,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    ),
  );

  /// 1. Ime, naslovnica, kategorija i kada.
  List<Widget> _basicsStep() => [
    _heading(t('Daj showu ime')),
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
          child: TextField(
            key: const ValueKey('live-title'),
            controller: _title,
            maxLength: LiveShow.maxTitle,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: t('Naslov showa'),
              hintText: t('npr. Retro igre od 1 €'),
            ),
          ),
        ),
      ],
    ),
    _label(t('Kada kreće show?')),
    Row(
      children: [
        Expanded(
          child: ChoiceChip(
            key: const ValueKey('live-now'),
            showCheckmark: false,
            label: SizedBox(
              width: double.infinity,
              child: Text(t('Odmah'), textAlign: TextAlign.center),
            ),
            selected: _startsAt == null,
            onSelected: (_) => setState(() => _startsAt = null),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ChoiceChip(
            key: const ValueKey('live-later'),
            showCheckmark: false,
            label: SizedBox(
              width: double.infinity,
              child: Text(
                _startsAt == null ? t('Zakaži') : formatDateTime(_startsAt!),
                textAlign: TextAlign.center,
              ),
            ),
            selected: _startsAt != null,
            onSelected: (_) => _pickTime(),
          ),
        ),
      ],
    ),
    if (_startsAt != null)
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: TextButton(
          key: const ValueKey('live-when'),
          onPressed: _pickTime,
          child: Text(t('Datum i vrijeme')),
        ),
      ),
    _label(t('Kategorija')),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final sec in ItemSection.values)
          if (sec != ItemSection.digital)
            for (final c in sec.categories)
              ChoiceChip(
                key: ValueKey('live-cat-${c.name}'),
                label: Text(c.label),
                showCheckmark: false,
                selected: _category == c,
                onSelected: (_) =>
                    setState(() => _category = _category == c ? null : c),
              ),
      ],
    ),
  ];

  /// 2. Predmeti + sve dodatno sklonjeno pod "Više postavki".
  List<Widget> _itemsStep(AppState s) => [
    _heading(
      t('Dodaj predmete'),
      t('Licitiraju se redom. Možeš ih dodati i tijekom showa.'),
    ),
    ..._lotsSection(s),
    const SizedBox(height: 12),
    // Kupi odmah u liveu: gledatelji kupuju iz tvoje trgovine bez licitacije.
    Builder(
      builder: (_) {
        final n = s.listingsOf(s.currentUserId ?? '').length;
        return SwitchListTile(
          key: const ValueKey('live-shop-toggle'),
          contentPadding: EdgeInsets.zero,
          value: _shop,
          onChanged: (v) => setState(() => _shop = v),
          title: Text(
            t('Prodaj i iz moje trgovine'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            n == 0
                ? t('Još nemaš oglasa u trgovini (Kupi odmah).')
                : t('Gledatelji mogu odmah kupiti tvojih {0} oglasa.', ['$n']),
          ),
        );
      },
    ),
    Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey('live-more'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          t('Više postavki'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        children: _moreOptions(s),
      ),
    ),
  ];

  /// Predmeti za licitaciju: jedan gumb za novi predmet, a svoje predmete
  /// dodaješ jednim dodirom (bez spremanja unaprijed).
  List<Widget> _lotsSection(AppState s) {
    final mine = s.myDevices
        .where(
          (d) =>
              !d.isDigital &&
              !_selected.contains(d.id) &&
              s.activeAuctionFor(d.id) == null,
        )
        .toList();
    return [
      FilledButton.icon(
        key: const ValueKey('live-quick-item'),
        onPressed: _addQuick,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(t('Dodaj predmet')),
      ),
      const SizedBox(height: 12),
      for (final id in _selected)
        if (s.deviceById(id) case final d?)
          _LotChoice(
            device: d,
            order: _selected.indexOf(id) + 1,
            price: _prices[id],
            onTap: () => _toggle(d),
          ),
      for (final (i, l) in _drafts.indexed)
        _DraftRow(
          key: ValueKey('live-draft-$i'),
          lot: l,
          order: _selected.length + i + 1,
          onRemove: () => setState(() => _drafts.removeAt(i)),
        ),
      if (mine.isNotEmpty) ...[
        _label(t('Ili jednim dodirom iz svojih predmeta')),
        for (final d in mine)
          _LotChoice(device: d, order: 0, price: null, onTap: () => _toggle(d)),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey('live-on-screen'),
          onPressed: _addOnScreen,
          child: Text(t('Brojevi na ekranu (#150, #151…)')),
        ),
      ),
    ];
  }

  /// Rijetko potrebne opcije: video, sat, promocija. Live je samo za
  /// licitacije — Kupi odmah proizvodi se ne prodaju u liveu.
  List<Widget> _moreOptions(AppState s) => [
    SwitchListTile(
      key: const ValueKey('live-video'),
      contentPadding: EdgeInsets.zero,
      value: _video,
      onChanged: (v) => setState(() => _video = v),
      title: Text(
        t('Video uživo s kamere'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    _label(t('Licitacija po predmetu')),
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
    // Promocija odmah: zakazani show → do kraja showa, live odmah → boost.
    _label(_startsAt == null ? t('Brzi boost (15 min)') : t('Promocija showa')),
    Wrap(
      key: const ValueKey('live-promo'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in [0, if (_startsAt == null) 3, 5, 10, 20])
          ChoiceChip(
            key: ValueKey('live-promo-$v'),
            showCheckmark: false,
            label: Text(
              v == 0
                  ? t('Bez promocije')
                  : '${formatCredits(v.toDouble())} · ~${LiveBoost.estimatedReach(v.toDouble())}',
            ),
            selected: _promo == v,
            onSelected: (_) => setState(() => _promo = v),
          ),
      ],
    ),
    if (_promo > 0)
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          t('Plaća se karticom pri objavi; show ima oznaku "Promovirano".'),
          style: TextStyle(color: LoopColors.textSecondary, fontSize: 12),
        ),
      ),
    const SizedBox(height: 8),
  ];

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final last = _step == _steps - 1;
    final body = _step == 0 ? _basicsStep() : _itemsStep(s);

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const ValueKey('wizard-back'),
            tooltip: t('Natrag'),
            onPressed: _back,
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
          title: Text(t('Novi live')),
          centerTitle: true,
          actions: [
            IconButton(
              key: const ValueKey('wizard-close'),
              tooltip: t('Zatvori'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              key: ValueKey('wizard-step-$_step'),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                ...body,
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
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t('{0} od {1}', ['${_step + 1}', '$_steps']),
                      key: const ValueKey('wizard-count'),
                      style: TextStyle(
                        color: LoopColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: last
                          ? FilledButton(
                              key: const ValueKey('live-go'),
                              style: FilledButton.styleFrom(
                                backgroundColor: kLiveRed,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _submit,
                              child: Text(
                                _startsAt == null
                                    ? t('Kreni uživo')
                                    : t('Zakaži live'),
                              ),
                            )
                          : FilledButton(
                              key: const ValueKey('wizard-next'),
                              onPressed: _canNext
                                  ? () => setState(() {
                                      _error = null;
                                      _step++;
                                    })
                                  : null,
                              child: Text(t('Dalje')),
                            ),
                    ),
                  ],
                ),
              ),
            ),
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

/// Predmet ovog livea prije spremanja.
class _DraftLot {
  const _DraftLot(this.name, this.price, {this.photo, this.from});
  final String name;
  final double price;
  final String? photo;

  /// "Items on screen": prvi broj niza (#150); sljedeći se u liveu dodaju
  /// sami ("Sljedeći #N"). `null` = obični predmet.
  final int? from;
  int get count => 1;
  bool get onScreen => from != null;

  /// Zadnji broj u nizu (za nastavak brojanja).
  int? get last => from == null ? null : from! + count - 1;
}

/// Redak predmeta ovog livea (prije spremanja).
class _DraftRow extends StatelessWidget {
  const _DraftRow({
    super.key,
    required this.lot,
    required this.order,
    required this.onRemove,
  });
  final _DraftLot lot;
  final int order;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final number = lot.from;
    final thumb = SizedBox.square(
      dimension: 44,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: lot.photo != null
            ? LocalPhoto(
                path: lot.photo!,
                cacheWidth: 120,
                fallback: Container(color: LoopColors.peach),
              )
            : Container(
                color: const Color(0xFF000000),
                alignment: Alignment.center,
                child: Text(
                  '#${number ?? order}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: LoopColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        child: ListTile(
          leading: thumb,
          title: Text(
            lot.onScreen ? '${lot.name} #${lot.from}' : lot.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            lot.onScreen
                ? t('Items on screen · brojevi idu sami · od {0}', [
                    formatCredits(lot.price),
                  ])
                : '${t('Predmet sa slikom')} · ${t('od {0}', [formatCredits(lot.price)])}',
          ),
          trailing: IconButton(
            tooltip: t('Ukloni'),
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ),
      ),
    );
  }
}

/// Brzo dodavanje predmeta u novi live: slika, naziv, početna cijena.
class _QuickLotSheet extends ConsumerStatefulWidget {
  const _QuickLotSheet();

  @override
  ConsumerState<_QuickLotSheet> createState() => _QuickLotSheetState();
}

class _QuickLotSheetState extends ConsumerState<_QuickLotSheet> {
  final _name = TextEditingController();
  final _price = TextEditingController(text: '1');
  String? _photo;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final paths = await ref.read(imageStoreProvider).pick(limit: 1);
      if (paths.isNotEmpty && mounted) setState(() => _photo = paths.first);
    } catch (e) {
      showLoopSnackBar(
        t('Fotografiju nije moguće učitati: {0}', [e]),
        error: true,
      );
    }
  }

  void _submit() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (name.isEmpty || price == null || price < 1) {
      showLoopSnackBar(t('Upiši naziv i cijenu (barem 1 €).'), error: true);
      return;
    }
    Navigator.pop(context, _DraftLot(name, price, photo: _photo));
  }

  @override
  Widget build(BuildContext context) => Padding(
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
          t('Brzo dodaj predmet'),
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: const ValueKey('quick-lot-photo'),
              borderRadius: BorderRadius.circular(14),
              onTap: _pick,
              child: Container(
                width: 92,
                height: 92,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: LoopColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: LoopColors.peach, width: 1.5),
                ),
                child: _photo != null
                    ? LocalPhoto(
                        path: _photo!,
                        cacheWidth: 240,
                        fallback: const SizedBox.shrink(),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            color: LoopColors.textSecondary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t('Slika'),
                            style: TextStyle(
                              color: LoopColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('quick-lot-name'),
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: t('Naziv')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('quick-lot-price'),
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: t('Početna cijena'),
                      suffixText: '€',
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton(
          key: const ValueKey('quick-lot-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: _submit,
          child: Text(t('Dodaj u live')),
        ),
      ],
    ),
  );
}

/// "Items on screen" (kao Whatnot): niz predmeta bez slike s rednim
/// brojem — #150, #151… Prodaje se redom, pa se nakon svake prodaje na
/// ekranu pojavi sljedeći broj.
class _OnScreenSheet extends StatefulWidget {
  const _OnScreenSheet({required this.start});
  final int start;

  @override
  State<_OnScreenSheet> createState() => _OnScreenSheetState();
}

class _OnScreenSheetState extends State<_OnScreenSheet> {
  late final _name = TextEditingController(text: t('Predmet'));
  late final _from = TextEditingController(text: '${widget.start}');
  final _price = TextEditingController(text: '1');

  @override
  void dispose() {
    for (final c in [_name, _from, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final from = int.tryParse(_from.text.trim());
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (name.isEmpty ||
        from == null ||
        from < 0 ||
        price == null ||
        price < 1) {
      showLoopSnackBar(
        t('Upiši naziv, početni broj i cijenu (barem 1 €).'),
        error: true,
      );
      return;
    }
    Navigator.pop(context, _DraftLot(name, price, from: from));
  }

  @override
  Widget build(BuildContext context) {
    final from = int.tryParse(_from.text) ?? widget.start;
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
            t('Items on screen'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          Text(
            t(
              'Predmeti s brojevima, bez slike — pokazuješ ih na kameri. Brojevi idu sami: nakon svake prodaje stisneš "Sljedeći #N". Nema ograničenja.',
            ),
            style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('on-screen-name'),
            controller: _name,
            decoration: InputDecoration(labelText: t('Naziv')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('on-screen-from'),
                  controller: _from,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('Od broja'),
                    prefixText: '#',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('on-screen-price'),
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: t('Početna'),
                    suffixText: '€',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t('Prvi: {0} #{1} · zatim #{2}, #{3}… bez ograničenja', [
              _name.text.trim(),
              '$from',
              '${from + 1}',
              '${from + 2}',
            ]),
            key: const ValueKey('on-screen-preview'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('on-screen-confirm'),
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
                                selected
                                    ? t(
                                        'U liveu kao #{0} · upiši početnu cijenu',
                                        ['$order'],
                                      )
                                    : device.isListed && kBuyNowEnabled
                                    ? t('Kupi odmah · {0}', [
                                        formatCredits(device.price),
                                      ])
                                    : t('Spremljeno · dodirni za live'),
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
                      LengthLimitingTextInputFormatter(9),
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
        MaterialPageRoute<void>(
          settings: AppPlace.of('live', showId).settings,
          builder: (_) => LiveRoomScreen(showId: showId),
        ),
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
      body: Consumer(
        builder: (context, ref, _) {
          final s = ref.watch(appProvider);
          final show = s.liveShowById(showId);
          final host = show != null && show.hostId == s.currentUserId;
          final wide = MediaQuery.sizeOf(context).width >= kHostConsoleWidth;
          final room = LiveRoomView(showId: showId);
          if (!host || !wide) return room;
          // Domaćin na velikom ekranu: predmeti | video | statistika.
          return Theme(
            data: buildLiveTheme(),
            child: Row(
              key: const ValueKey('host-console'),
              children: [
                SizedBox(width: 320, child: HostLotsPanel(showId: showId)),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: room,
                    ),
                  ),
                ),
                SizedBox(width: 340, child: HostStatsPanel(showId: showId)),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// Soba livea (kao Whatnot): pozornica s predmetom, odbrojavanje, veliki
/// gumb za licitiranje, chat i red predmeta. Domaćin vidi gumb za kraj.
/// U swipe feedu je aktivna samo soba na ekranu ([active]): samo ona broji
/// gledatelja i osvježava odbrojavanje.
class LiveRoomView extends StatelessWidget {
  const LiveRoomView({super.key, required this.showId, this.active = true});
  final String showId;
  final bool active;

  // Tamna tema IZNAD stanja sobe: i listovi koje soba otvara (predmeti,
  // dodavanje…) su tamni s čitljivim svijetlim tekstom.
  @override
  Widget build(BuildContext context) => Theme(
    data: buildLiveTheme(),
    child: _LiveRoomBody(showId: showId, active: active),
  );
}

class _LiveRoomBody extends ConsumerStatefulWidget {
  const _LiveRoomBody({required this.showId, required this.active});
  final String showId;
  final bool active;

  @override
  ConsumerState<_LiveRoomBody> createState() => _LiveRoomViewState();
}

class _LiveRoomViewState extends ConsumerState<_LiveRoomBody> {
  Timer? _timer;
  DateTime _watchAt = DateTime.now();
  DateTime _joinedAt = DateTime.now();
  DateTime _beatAt = DateTime.now();
  final _shopDrawer = GlobalKey<VisionLiveShopOverlayState>();
  final _chat = TextEditingController();
  late final _chatFocus = FocusNode()..addListener(_chatFocusChanged);
  void _chatFocusChanged() {
    if (mounted) setState(() {});
  }

  bool _busy = false;

  /// Video: domaćin šalje kameru, gledatelj prima (samo dok je soba
  /// aktivna i live nije završio).
  LiveBroadcaster? _broadcaster;
  LiveWatcher? _watcher;

  /// Reakcije: šalju se kao kratka poruka, a u sobi lete uz desni rub.
  static const _reactions = ['❤️', '🔥', '😮', '💸', '👏', '😍', '🎉'];

  /// Brze reakcije u redu iznad trake (srce je zaseban gumb).
  static const _quick = ['🔥', '😮', '💸', '👏', '😍'];
  final _rnd = math.Random();
  DateTime _reactSentAt = DateTime(2000);

  /// Brza reakcija: 2–4 emojija na nasumičnim mjestima (veličina, nagib,
  /// put), ostalima se šalje jedna (najviše jedna u 1,2 s).
  void _react(String emoji) {
    final user = ref.read(appProvider).currentUser;
    if (user == null || user.isGuest) {
      blockGuest(context);
      return;
    }
    LiveSound.pop();
    _burst(emoji, 2 + _rnd.nextInt(3));
    final me = ref.read(appProvider).currentUser;
    final now = DateTime.now();
    if (me != null &&
        !me.isGuest &&
        now.difference(_reactSentAt) > const Duration(milliseconds: 1200)) {
      _reactSentAt = now;
      _app.liveChat(widget.showId, emoji).catchError((_) {});
    }
  }

  /// Lokalni prasak emojija uz desni rub (bez slanja).
  void _burst(String emoji, int count) {
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < count; i++) {
        _bursts.add(_Burst(_burstId++, null, emoji));
      }
      if (_bursts.length > 40) _bursts.removeRange(0, _bursts.length - 40);
    });
  }

  bool _muted = false;

  /// Filter chata za voditelja: sve / pitanja / ponude.
  _ChatFilter _chatFilter = _ChatFilter.all;

  void _toggleSound() {
    setState(() => _muted = !_muted);
    LiveSound.muted = _muted;
    ref.read(storageProvider).setLiveMuted(_muted);
    if (!_muted) LiveSound.bid();
  }

  /// Zadnjih 5 s licitacije u kojoj sudjelujem: "tik" svake sekunde.
  int? _tickLot;
  int? _tickSec;

  void _countdownTick(LotState? cur, String? me, DateTime now) {
    final end = cur?.end;
    if (cur == null || end == null || me == null) return;
    if (!cur.bids.any((b) => b.userId == me)) return;
    final left = end.difference(now).inMilliseconds;
    if (left <= 0 || left > 5000) return;
    final sec = (left / 1000).ceil();
    if (_tickLot == cur.index && _tickSec == sec) return;
    _tickLot = cur.index;
    _tickSec = sec;
    LiveSound.tick(last: sec == 1);
  }

  /// Tuđa ponuda u liveu: mali prasak 🔥/💸 (nasumično) — soba "živi".
  int _seenBids = -1;

  void _bidBursts(LotState? cur, String? me) {
    final n = cur?.bids.length ?? 0;
    if (_seenBids >= 0 && n > _seenBids && cur!.bids.last.userId != me) {
      final emoji = ['🔥', '💸', '😮'][_rnd.nextInt(3)];
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _burst(emoji, 1 + _rnd.nextInt(2)),
      );
    }
    _seenBids = n;
  }

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
    final user = ref.read(appProvider).currentUser;
    if (user == null || user.isGuest) return;
    setState(() {
      if (like) _liked = true;
      for (var i = 0; i < count; i++) {
        _bursts.add(_Burst(_burstId++, at, '❤️'));
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
    final user = ref.read(appProvider).currentUser;
    if (user == null || user.isGuest) {
      blockGuest(context);
      return;
    }
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
    _muted = ref.read(storageProvider).liveMuted;
    LiveSound.muted = _muted;
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(_LiveRoomBody old) {
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
      successMessage: t('Uživo si!'),
    );
    if (ok && mounted) await _startVideo();
  }

  /// Potvrda prije pokretanja prijenosa: gledatelji dobivaju obavijest.
  Future<void> _confirmGoLive() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: kLiveSheet,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('Pokrenuti prijenos?'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t('Pratitelji i svi koji su označili show dobit će obavijest.'),
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('live-go-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: kLiveRed,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('Idi uživo')),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t('Odustani')),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && mounted) await _goLiveNow();
  }

  /// "Live opcije" voditelja: tamne pločice po tri u retku.
  void _showHostOptions(LiveShow show) {
    Widget tile(
      BuildContext ctx, {
      required String key,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color? color,
    }) => Material(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.pop(ctx);
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color ?? Colors.white, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color ?? Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: kLiveSheet,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Live opcije'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 12),
                StatefulBuilder(
                  builder: (_, setLocal) {
                    final on =
                        ref
                            .read(appProvider)
                            .liveShowById(show.id)
                            ?.verifiedOnly ??
                        false;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                          child: SwitchListTile(
                            key: const ValueKey('live-verified-toggle'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              t('Samo provjereni kupci'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              t(
                                'Licitirati mogu samo kupci s karticom koji su već kupovali ili imaju potvrđenu e-poštu. Ostali mogu gledati.',
                              ),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                            value: on,
                            onChanged: (v) async {
                              try {
                                await _app.liveSetVerifiedOnly(show.id, v);
                                setLocal(() {});
                              } on TradeException catch (e) {
                                showLoopSnackBar(e.message, error: true);
                              }
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.15,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    tile(
                      ctx,
                      key: 'live-add-item',
                      icon: Icons.add,
                      label: t('Dodaj predmet'),
                      onTap: () => _quickAdd(show),
                    ),
                    tile(
                      ctx,
                      key: 'live-shop-tile',
                      icon: show.shop
                          ? Icons.storefront
                          : Icons.storefront_outlined,
                      label: show.shop
                          ? t('Isključi trgovinu')
                          : t('Uključi trgovinu'),
                      onTap: () async {
                        try {
                          await _app.liveSetShop(show.id, !show.shop);
                          showLoopSnackBar(
                            show.shop
                                ? t('Trgovina je isključena u liveu.')
                                : t(
                                    'Gledatelji sada mogu kupiti tvoje predmete odmah.',
                                  ),
                          );
                        } on TradeException catch (e) {
                          showLoopSnackBar(e.message, error: true);
                        }
                      },
                    ),
                    tile(
                      ctx,
                      key: 'live-viewers-tile',
                      icon: Icons.groups_outlined,
                      label: t('Gledatelji'),
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        isScrollControlled: true,
                        backgroundColor: kLiveSheet,
                        constraints: const BoxConstraints(maxWidth: 520),
                        builder: (_) => _ViewersSheet(showId: show.id),
                      ),
                    ),
                    tile(
                      ctx,
                      key: 'live-flash-tile',
                      icon: Icons.bolt,
                      label: t('Flash ponuda'),
                      onTap: () => showFlashSheet(context, ref),
                    ),
                    tile(
                      ctx,
                      key: 'live-giveaway-tile',
                      icon: Icons.card_giftcard,
                      label: t('Giveaway'),
                      onTap: () => showGiveawaySheet(context, ref, show),
                    ),
                    tile(
                      ctx,
                      key: 'live-promote-tile',
                      icon: Icons.trending_up,
                      label: t('Promoviraj'),
                      onTap: () => showPromoteSheet(context, ref, show),
                    ),
                    tile(
                      ctx,
                      key: 'live-share-tile',
                      icon: Icons.ios_share,
                      label: t('Podijeli'),
                      onTap: () => shareLink(
                        context,
                        publicLink(live: show.id),
                        text: t('Gledaj "{0}" uživo na Subhastu', [show.title]),
                      ),
                    ),
                    tile(
                      ctx,
                      key: 'live-raid-tile',
                      icon: Icons.rocket_launch_outlined,
                      label: t('Raid'),
                      onTap: () => _raid(show),
                    ),
                    tile(
                      ctx,
                      key: 'live-end',
                      icon: Icons.stop_circle_outlined,
                      label: t('Završi live'),
                      color: kLiveRed,
                      onTap: () => _end(false),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startLot([int? index]) async {
    try {
      await _app.liveStartLot(widget.showId, index: index);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    }
  }

  /// "Items on screen": sljedeći broj se doda i odmah licitira.
  Future<void> _nextNumber(LiveShow show) async {
    try {
      await _app.liveStartNextNumber(show.id);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    }
  }

  /// Dodavanje usred livea: isti prozor kao "Dodaj u show".
  Future<void> _quickAdd(LiveShow show) =>
      showAddToShowSheet(context, ref, show);

  /// Predmeti koji su već prodani kad smo ušli ili koje smo već proslavili.
  Set<int>? _seenSold;

  /// Kratka traka "PRODANO" za ostale gledatelje.
  LotState? _sweep;
  DateTime? _sweepAt;

  /// Izvlačenje nagradne igre: predmet, imena prijavljenih, dobitnik.
  (LotState, List<String>, String)? _spin;
  DateTime? _spinAt;

  /// Whatnot: kad predmet ode, pobjednik dobiva slavlje preko cijelog
  /// ekrana, a ostali traku "PRODANO @kupac · cijena".
  int? _leadLot;
  bool _wasLeading = false;
  DateTime? _outbidAt;
  int _outbids = 0;

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
      final giveaway = l.mode == LotMode.giveaway;
      if (giveaway) {
        // Nagradna igra: bubanj s imenima prijavljenih se vrti i stane na
        // dobitniku (svi gledatelji ga vide).
        final names = <String>{
          for (final e in ref.read(storageProvider).liveEventsOf(st.show.id))
            if (e.type == LiveEventType.enter && e.lot == l.index) e.userLabel,
        }.toList();
        _spin = (l, names, l.leader!.userLabel);
        _spinAt = DateTime.now();
      }
      if (l.leader!.userId == me) {
        final device = ref.read(appProvider).deviceById(l.lot.deviceId);
        Future<void>.delayed(
          giveaway ? _GiveawaySpin.duration : Duration.zero,
        ).then((_) {
          if (!mounted) return;
          LiveSound.win();
          _burst('🎉', 4);
          _burst('💸', 3);
        });
        // Kod nagradne igre čestitka tek kad bubanj stane.
        Future<void>.delayed(
          giveaway ? _GiveawaySpin.duration : Duration.zero,
        ).then((_) {
          if (!mounted) return;
          showCelebration(
            context,
            title: l.mode == LotMode.dutch ? t('Kupljeno!') : t('Osvojio si!'),
            subtitle: t('Plaćeno karticom · prodavač šalje paket'),
            device: device,
            amount: l.price,
          );
        });
      } else if (!giveaway) {
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
      if (s.currentUser == null ||
          s.currentUser!.isGuest ||
          s.currentUser!.seller == null) {
        setState(
          () => _cameraError = t('Za live je potreban račun prodavača.'),
        );
        return;
      }
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
    _chatFocus.dispose();
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
    // Javljanje svake minute: prosječno vrijeme gledanja u analitici.
    if (now.difference(_watchAt) >= const Duration(minutes: 1)) {
      final seconds = now.difference(_watchAt).inSeconds;
      _watchAt = now;
      _app.liveWatchPing(widget.showId, seconds);
    }
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
              !s.liveLotSettled(show, l.index) &&
              (me == show.hostId || l.leader?.userId == me),
        );
    if (due) _app.settleLive();
  }

  Future<void> _bid(double amount, {int? lot}) async {
    if (blockGuest(context) || _busy) return;
    if (!await ensureCard(context, ref) || !mounted) return;
    setState(() => _busy = true);
    try {
      // Bez potvrde u SnackBaru (prekrio bi chat) — gumb postaje "Vodiš".
      final leading = await _app.liveBid(widget.showId, amount, lot: lot);
      if (leading) LiveSound.bid();
      if (!leading) {
        showLoopSnackBar(
          t('Netko ima višu maksimalnu ponudu — povisi!'),
          error: true,
        );
      } else if (lot != null) {
        showLoopSnackBar(t('Predlicitacija je spremljena'));
      }
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _take() async {
    if (blockGuest(context) || _busy) return;
    if (!await ensureCard(context, ref) || !mounted) return;
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
    if (!await ensureCard(context, ref) || !mounted) return;
    setState(() => _busy = true);
    try {
      await _app.liveEnter(widget.showId);
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || blockGuest(context)) return;
    try {
      await _app.liveChat(widget.showId, text);
      _chat.clear();
      _chatFocus.unfocus();
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

  /// Raid: odaberi live u koji šalješ gledatelje; tvoj show se završava.
  Future<void> _raid(LiveShow show) async {
    final s = ref.read(appProvider);
    final targets = _app.liveRaidTargets(show.id);
    final target = await showModalBottomSheet<LiveShow>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: kLiveSheet,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            key: const ValueKey('live-raid-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('Raid'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t(
                  'Pošalji svoje gledatelje u drugi live. Tvoj show se tada završava.',
                ),
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              if (targets.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    t('Trenutno nema drugih liveova uživo.'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final other in targets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(14),
                            child: ListTile(
                              key: ValueKey('live-raid-${other.id}'),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              leading: const Icon(
                                Icons.live_tv,
                                color: kLiveRed,
                              ),
                              title: Text(
                                other.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${s.userById(other.hostId)?.handle ?? ''} · '
                                '${t('{0} gledatelja', ['${s.liveStateOf(other).viewers}'])}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              trailing: const Icon(
                                Icons.rocket_launch_outlined,
                                color: Colors.white,
                              ),
                              onTap: () => Navigator.pop(ctx, other),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;
    await runWithLoading(
      context,
      () => _app.liveRaid(show.id, target.id),
      successMessage: t('Gledatelji su poslani u "{0}"', [target.title]),
    );
  }

  /// Trgovina livea (kao Douyin): predmeti na aukciji (predlicitacija) i
  /// prodavačevi predmeti za Kupi odmah, u dvije kartice.
  void _showQueue(LiveState st, bool isHost) =>
      _shopDrawer.currentState?.open();

  Widget _shopContent(LiveState st, bool isHost, VoidCallback onClose) {
    return _LiveShopSheet(
      showId: st.show.id,
      isHost: isHost,
      onStart: (i) {
        onClose();
        _startLot(i);
      },
      onPreBid: (l) async {
        final mine = l.leader?.userId == ref.read(appProvider).currentUserId;
        final min = mine
            ? (l.maxOf(l.leader!.userId) ?? l.price) +
                  LiveLot.increment(l.price)
            : l.minNext;
        final amount = await showMaxBidDialog(
          context,
          min: min,
          preBid: true,
          raise: mine,
        );
        if (amount == null || !mounted) return;
        onClose();
        await _bid(amount, lot: l.index);
      },
    );
  }

  void _showRoomTools(LiveShow show, LiveState st, bool canAct) {
    _chatFocus.unfocus();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: kLiveSheet,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setLocal) => SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t('Live opcije'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (st.current != null && st.current!.mode == LotMode.auction)
                    ListTile(
                      key: const ValueKey('live-bid-custom'),
                      leading: const Icon(Icons.tune, color: Colors.white),
                      title: Text(
                        t('Tvoja ponuda'),
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _customBid(st.current!);
                      },
                    ),
                  if (ref.read(appProvider).currentUserId != show.hostId)
                    ListTile(
                      key: const ValueKey('live-shop-boost'),
                      leading: const Icon(
                        Icons.rocket_launch_outlined,
                        color: Colors.white,
                      ),
                      title: Text(
                        t('Boostaj show'),
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        showPromoteSheet(context, ref, show);
                      },
                    ),
                  if (ref.read(appProvider).currentUserId != show.hostId)
                    ListTile(
                      key: const ValueKey('live-react-0'),
                      leading: Icon(
                        _liked ? Icons.favorite : Icons.favorite_border,
                        color: Colors.white,
                      ),
                      title: Text(
                        t('Srce'),
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleLike();
                      },
                    ),
                  _QuickReactions(
                    emojis: _quick,
                    onReact: (emoji) {
                      Navigator.pop(ctx);
                      _react(emoji);
                    },
                    muted: _muted,
                    onSound: () {
                      _toggleSound();
                      setLocal(() {});
                    },
                  ),
                  if (st.hype >= .2) _HypeMeter(st.hype),
                  if (show.canModerate(ref.read(appProvider).currentUserId))
                    _ChatFilterChips(
                      value: _chatFilter,
                      onChanged: (value) {
                        setState(() => _chatFilter = value);
                        setLocal(() {});
                      },
                    ),
                  ListTile(
                    key: const ValueKey('live-share'),
                    leading: const Icon(Icons.ios_share, color: Colors.white),
                    title: Text(
                      t('Podijeli'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (ref.read(appProvider).currentUserId != show.hostId) {
                        _app.liveShared(show.id);
                      }
                      shareLink(
                        context,
                        publicLink(live: show.id),
                        text: t('Gledaj "{0}" uživo na Subhastu', [show.title]),
                      );
                    },
                  ),
                  if (!canAct)
                    ListTile(
                      key: const ValueKey('live-wallet-login'),
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: Colors.white,
                      ),
                      title: Text(
                        t('Novčanik'),
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        blockGuest(context);
                      },
                    )
                  else
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: WalletChip(dark: true),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final composing = _chatFocus.hasFocus;
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
    // Nadmašen: kratka vibracija i crveni bljesak.
    final leadingNow = cur != null && cur.leader?.userId == me?.id;
    if (widget.active &&
        cur != null &&
        _leadLot == cur.index &&
        _wasLeading &&
        !leadingNow) {
      _outbidAt = now;
      _outbids++;
      LiveSound.outbid();
    }
    _leadLot = cur?.index;
    _wasLeading = leadingNow;
    if (widget.active) {
      _countdownTick(cur, me?.id, now);
      _bidBursts(cur, me?.id);
    }
    final flash =
        _outbidAt != null &&
        now.difference(_outbidAt!) < const Duration(milliseconds: 900);
    final spin = _spin;
    final showSpin =
        spin != null &&
        _spinAt != null &&
        now.difference(_spinAt!) <
            _GiveawaySpin.duration + const Duration(seconds: 2);
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
              onPressed: _confirmGoLive,
              icon: const Icon(Icons.videocam),
              label: Text(t('Kreni uživo sada')),
            )
          else ...[
            if (s.wantsReminder(show.id))
              Text(
                t('Javit ćemo ti kad krene'),
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
          if (!isHost && st.raidTo != null)
            if (s.liveShowById(st.raidTo!) case final next?
                when !s.liveStateOf(next, now).isOver) ...[
              const SizedBox(height: 10),
              Container(
                key: const ValueKey('live-raid-invite'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kBidOrange.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      t('Raid! {0} vas šalje u "{1}"', [
                        host?.handle ?? '',
                        next.title,
                      ]),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const ValueKey('live-raid-go'),
                      style: FilledButton.styleFrom(
                        backgroundColor: kBidOrange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => LiveRoomScreen(showId: next.id),
                        ),
                      ),
                      icon: const Icon(Icons.rocket_launch_outlined),
                      label: Text(t('Idi u live')),
                    ),
                  ],
                ),
              ),
            ],
          const SizedBox(height: 10),
          _Recap(state: st, me: me?.id),
          if (won > 0) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => DeliveriesScreen.open(context),
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(t('Osvojio si {0} · prati pošiljku', ['$won'])),
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

    return VisionLiveShopOverlay(
      key: _shopDrawer,
      drawerBuilder: (_, close) => _shopContent(st, isHost, close),
      child: ColoredBox(
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
                _
                    when stageDevice != null &&
                        stageDevice.imagePaths.isNotEmpty =>
                  LocalPhoto(
                    path: stageDevice.imagePaths.first,
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
                                // Završen live: sažetak točno u sredini.
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  st.isOver ? 16 : 72,
                                  16,
                                ),
                                child: composing
                                    ? const SizedBox.shrink()
                                    : center,
                              ),
                            ),
                            if (showSweep) ...[
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ConfettiBurst(
                                    key: ValueKey(
                                      'live-confetti-${sweep.index}',
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 48,
                                child: IgnorePointer(
                                  child: _SoldSweep(
                                    key: ValueKey('live-sold-${sweep.index}'),
                                    text: t('Prodano {0} za {1}', [
                                      s
                                              .userById(sweep.leader!.userId)
                                              ?.handle ??
                                          '?',
                                      formatCredits(sweep.price),
                                    ]),
                                  ),
                                ),
                              ),
                            ],
                            if (showSpin)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: _GiveawaySpin(
                                    key: ValueKey('live-spin-${spin.$1.index}'),
                                    names: spin.$2,
                                    winner: spin.$3,
                                  ),
                                ),
                              ),
                            if (flash)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: _OutbidFlash(
                                    key: ValueKey('live-outbid-$_outbids'),
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
                                child: _HostControls(
                                  broadcaster: b,
                                  onMore: () => _showHostOptions(show),
                                ),
                              ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              width: 130,
                              height: 380,
                              child: IgnorePointer(
                                child: _FloatingReactions(
                                  // Svoja srca crtam odmah (lokalno).
                                  events: [
                                    for (final e in st.feed)
                                      if (isReaction(e) && e.userId != me?.id)
                                        e,
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
                                          emoji: b.emoji,
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
                            // Chat zauzima najviše pola slobodnog prostora;
                            // kad je live gotov, ostaje samo sažetak.
                            if (!st.isOver)
                              Positioned(
                                left: 12,
                                right: 12,
                                top: 0,
                                bottom: 4,
                                child: LayoutBuilder(
                                  builder: (_, c) => Align(
                                    alignment: Alignment.bottomLeft,
                                    child: ConstrainedBox(
                                      // Voditelj čita chat dok vodi live: veći
                                      // i širi prozor, veći tekst.
                                      constraints: BoxConstraints(
                                        maxWidth: isHost ? 300 : 220,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _ChatFeed(
                                            show: show,
                                            muted: st.muted,
                                            banned: st.banned,
                                            moderator: show.canModerate(me?.id),
                                            feed: st.feed,
                                            me: me?.id,
                                            hostId: show.hostId,
                                            filter: _chatFilter,
                                            large: isHost,
                                            maxHeight: math.min(
                                              isHost ? 280 : 150,
                                              c.maxHeight *
                                                  (isHost ? 0.7 : 0.55),
                                            ),
                                          ),
                                        ],
                                      ),
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
                              backgroundColor: const Color(0xFF1E7E34),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(42),
                            ),
                            onPressed: () => DeliveriesScreen.open(context),
                            icon: const Icon(Icons.local_shipping_outlined),
                            label: Text(
                              t('Osvojio si {0} · prodavač šalje paket', [
                                '${pending.length}',
                              ]),
                            ),
                          ),
                        ),
                      if (!composing && !st.isOver)
                        _FlashBar(hostId: show.hostId, now: now),
                      _DouyinBar(
                        controller: _chat,
                        focusNode: _chatFocus,
                        onSend: _send,
                        showChat: !st.isOver,
                        guest: !canAct,
                        onLogin: () => blockGuest(context),
                        bagCount:
                            st.lots
                                .where(
                                  (lot) =>
                                      lot.status == LotStatus.upcoming ||
                                      lot.status == LotStatus.running,
                                )
                                .length +
                            (show.shop
                                ? liveShopProducts(s, show.hostId).length
                                : 0),
                        onBag: () => _showQueue(st, isHost),
                        liked: _liked,
                        onHeart: st.isOver || isHost ? null : _toggleLike,
                        onMore: () => _showRoomTools(show, st, canAct),
                      ),
                      if (!composing)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                          child: VisionGlass(
                            dark: true,
                            radius: 28,
                            padding: const EdgeInsets.fromLTRB(0, 0, 0, 18),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (cur != null)
                                  _LotCard(
                                    lot: cur,
                                    device: s.deviceById(cur.lot.deviceId),
                                    total: show.lots.length,
                                    lotSeconds:
                                        cur.lot.seconds ?? show.lotSeconds,
                                    now: now,
                                    me: me?.id,
                                    leaderUser: s.userById(cur.leader?.userId),
                                    isHost: isHost,
                                  )
                                else if (done != null && !st.isOver)
                                  _LotCard(
                                    lot: done,
                                    device: s.deviceById(done.lot.deviceId),
                                    total: show.lots.length,
                                    lotSeconds:
                                        done.lot.seconds ?? show.lotSeconds,
                                    now: now,
                                    me: me?.id,
                                    leaderUser: s.userById(done.leader?.userId),
                                    result: true,
                                  ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    0,
                                  ),
                                  child: _actions(
                                    show,
                                    st,
                                    cur,
                                    isHost,
                                    canAct,
                                    me?.id,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      VisionShopHandle(
                        key: ValueKey(
                          kSimpleDesign ? 'live-controls' : 'live-queue',
                        ),
                        onNavigate: (index) {
                          if (kSimpleDesign && index == 3) return;
                          if (kSimpleDesign && index == 0) {
                            ref
                                .read(homeFilterProvider.notifier)
                                .select('for-you');
                          }
                          if (index == 1 && blockGuest(context)) return;
                          ref.read(homeTabProvider.notifier).select(
                            switch (index) {
                              1 => 4,
                              2 => kSimpleDesign ? 3 : 2,
                              _ => 0,
                            },
                          );
                          Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst);
                        },
                        label: t('Povuci gore za shop · {0} predmeta', [
                          '${st.queue.length + (show.shop ? liveShopProducts(s, show.hostId).length : 0)}',
                        ]),
                        onOpen: () => _showQueue(st, isHost),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
            child:
                cur == null &&
                    next == null &&
                    LiveService.nextOnScreen(show) != null
                ? FilledButton.icon(
                    key: const ValueKey('live-next-number'),
                    style: big,
                    onPressed: st.canStart ? () => _nextNumber(show) : null,
                    icon: const Icon(Icons.tag),
                    label: Text(
                      t('Sljedeći: {0}', [
                        LiveService.nextOnScreen(show)!.name,
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : cur == null && next == null
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
          if (cur != null && cur.mode == LotMode.giveaway) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              key: const ValueKey('live-giveaway-end'),
              style: outlined,
              onPressed: () async {
                try {
                  await _app.liveEndGiveaway(show.id);
                } on TradeException catch (e) {
                  showLoopSnackBar(e.message, error: true);
                }
              },
              child: Text(t('Izvuci sada')),
            ),
          ],
          if (cur != null || next != null) ...[
            const SizedBox(width: 8),
            // Brzo dodavanje: jedna kompaktna ikona (bez dugog natpisa).
            IconButton.filledTonal(
              key: const ValueKey('live-quick-add'),
              tooltip: t('Brzo dodaj'),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
                minimumSize: const Size(52, 52),
              ),
              onPressed: () => _quickAdd(show),
              icon: const Icon(Icons.bolt),
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('live-host-menu'),
            tooltip: t('Više'),
            onPressed: () => _showHostOptions(show),
            icon: const Icon(Icons.more_vert, color: Colors.white),
          ),
        ],
      );
    }
    if (cur == null) {
      if (!st.isLive) return const SizedBox.shrink();
      return FilledButton(
        key: const ValueKey('live-awaiting'),
        style: FilledButton.styleFrom(
          disabledBackgroundColor: const Color(0xCC202127),
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size.fromHeight(44),
          textStyle: const TextStyle(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 13,
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
          backgroundColor: const Color(0xFF1E7E34),
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
                color: const Color(0xFF1E7E34),
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
              child: Text(t('Sudjeluj besplatno')),
            );
    }
    if (cur.leader?.userId == me) return _leading(cur, me);
    return _bidRow(cur);
  }

  Widget _leading(LotState cur, String? me) => Container(
    key: const ValueKey('live-leading'),
    height: 54,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFF1E7E34),
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

  Widget _bidRow(LotState cur) => VisionBidSlider(
    key: const ValueKey('live-bid'),
    confirmationKey: (cur.index, cur.minNext),
    label: t('Povuci za ponudu ({0})', [formatCredits(cur.minNext)]),
    semanticLabel: t('Licitiraj {0}', [formatCredits(cur.minNext)]),
    onConfirm: _busy ? null : () => _bid(cur.minNext),
  );

  /// Vlastiti iznos ponude: cijena na ekranu odmah skoči na taj iznos.
  Future<void> _customBid(LotState cur) async {
    if (blockGuest(context)) return;
    final c = TextEditingController(
      text: _fmtAmount(cur.minNext + LiveLot.increment(cur.minNext) * 4),
    );
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            scrollable: true,
            title: Text(t('Tvoja ponuda')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Najmanje {0} · cijena odmah skače na tvoj iznos.', [
                    formatCredits(cur.minNext),
                  ]),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('live-custom-amount'),
                  controller: c,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    suffixText: '€',
                    errorText: error,
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
                key: const ValueKey('live-custom-ok'),
                style: FilledButton.styleFrom(backgroundColor: kBidOrange),
                onPressed: () {
                  final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
                  if (v == null || v < cur.minNext) {
                    setD(
                      () => error = t('Najmanje {0}', [
                        formatCredits(cur.minNext),
                      ]),
                    );
                    return;
                  }
                  Navigator.pop(ctx, v);
                },
                child: Text(t('Licitiraj')),
              ),
            ],
          ),
        );
      },
    );
    c.dispose();
    if (amount != null && mounted) await _bid(amount);
  }

  static String _fmtAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
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
              LengthLimitingTextInputFormatter(9),
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
    showLoopSnackBar(t('Javit ćemo ti kad krene uživo'));
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final me = s.currentUserId;
    final following = s.isFollowing(show.hostId);
    return Padding(
      key: const ValueKey('live-compact-header'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: VisionGlass(
              dark: true,
              radius: 99,
              padding: const EdgeInsets.only(left: 14, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () =>
                          PublicProfileScreen.open(context, show.hostId),
                      child: Tooltip(
                        message: show.title,
                        child: Text(
                          hostName,
                          key: const ValueKey('live-host-meta'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (me != show.hostId)
                    TextButton(
                      key: const ValueKey('live-follow'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(44, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      onPressed: following
                          ? null
                          : () async {
                              if (blockGuest(context)) return;
                              await ref
                                  .read(appProvider.notifier)
                                  .toggleFollow(show.hostId);
                              await ref
                                  .read(appProvider.notifier)
                                  .liveFollowedFromShow(show.id);
                            },
                      child: Text(t(following ? 'Pratim' : 'Prati')),
                    )
                  else
                    const SizedBox(height: 36),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (state.isLive)
            InkWell(
              key: const ValueKey('live-viewers-open'),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                backgroundColor: kLiveSheet,
                builder: (_) => _ViewersSheet(showId: show.id),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: kLiveRed,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '● ${state.viewers}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 10),
          VisionGlass(
            dark: true,
            radius: 99,
            child: IconButton(
              key: const ValueKey('live-close'),
              tooltip: t('Zatvori'),
              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reakcije (srca i emoji) lete prema gore uz desni rub — kao na Whatnotu.
/// Animiraju se samo nove reakcije (ne i one od prije ulaska u sobu).
/// Lokalno srce (moj dodir): [at] = mjesto dodira, null = uz desni rub.
class _Burst {
  _Burst(this.id, this.at, this.emoji);
  final int id;
  final Offset? at;
  final String emoji;
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
          emoji: b.emoji,
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
        // Nasumičan put: odmak od ruba, širina vijuganja, nagib i veličina
        // ovise o [seed], pa svaka reakcija leti malo drukčije.
        final sway = 8.0 + widget.seed % 14;
        final tilt = ((widget.seed ~/ 7) % 41 - 20) / 100;
        return Positioned(
          right: 10 + (widget.seed % 64) + math.sin(v * 6 + phase) * sway,
          bottom: 20 + v * (260 + widget.seed % 90),
          child: Opacity(
            opacity: v < 0.75 ? 1 : (1 - v) / 0.25,
            child: Transform.rotate(
              angle: tilt * math.sin(v * 4 + phase),
              child: Transform.scale(
                scale:
                    (0.6 + 0.6 * math.min(v * 5, 1)) *
                    (0.8 + (widget.seed % 50) / 100),
                child: child,
              ),
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
        ? t('VRUĆE!')
        : hype >= 0.5
        ? t('Zagrijava se')
        : hype >= 0.2
        ? t('Živo')
        : t('Mirno');
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFFC233), width: 2),
            boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black54)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Čekić udari (zamah na početku animacije).
              AnimatedBuilder(
                animation: _c,
                builder: (_, child) {
                  final v = (_c.value / 0.3).clamp(0.0, 1.0);
                  final angle = -0.9 * (1 - Curves.elasticOut.transform(v));
                  return Transform.rotate(
                    angle: angle,
                    alignment: Alignment.bottomRight,
                    child: child,
                  );
                },
                child: const Text('🔨', style: TextStyle(fontSize: 34)),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
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

/// Crveni bljesak rubova ekrana kad te netko nadmaši.
class _OutbidFlash extends StatefulWidget {
  const _OutbidFlash({super.key});

  @override
  State<_OutbidFlash> createState() => _OutbidFlashState();
}

class _OutbidFlashState extends State<_OutbidFlash>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) {
      final a = (1 - _c.value) * 0.55;
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.1,
            colors: [
              Colors.transparent,
              kLiveRed.withValues(alpha: a),
            ],
            stops: const [0.55, 1],
          ),
        ),
      );
    },
  );
}

/// Što domaćin dodaje u live: novi predmet (naziv), svoj predmet ili
/// "brojeve na ekranu".
typedef _AddResult = ({
  String? deviceId,
  String name,
  double price,
  bool onScreen,
});

/// Jedan prozor za dodavanje u live: upiši naziv i cijenu (predmet se sam
/// sprema) ili jednim dodirom dodaj svoj predmet.
class _QuickAddSheet extends ConsumerStatefulWidget {
  const _QuickAddSheet({required this.showId, this.last});
  final String showId;
  final (String, double)? last;

  @override
  ConsumerState<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<_QuickAddSheet> {
  /// "Item on screen": sljedeći broj (Predmet #150 → Predmet #151).
  static String _nextName(String name) {
    final m = RegExp(r'^(.*#)(\d+)$').firstMatch(name);
    return m == null ? name : '${m.group(1)}${int.parse(m.group(2)!) + 1}';
  }

  final _name = TextEditingController();
  final _price = TextEditingController(text: '1');

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  double? get _priceValue =>
      double.tryParse(_price.text.trim().replaceAll(',', '.'));

  void _submit() {
    final name = _name.text.trim();
    final price = _priceValue;
    if (name.isEmpty || price == null || price < 1) {
      showLoopSnackBar(t('Upiši naziv i cijenu (barem 1 €).'), error: true);
      return;
    }
    Navigator.pop<_AddResult>(context, (
      deviceId: null,
      name: name,
      price: price,
      onScreen: false,
    ));
  }

  void _pick(Device d) {
    final price = _priceValue;
    Navigator.pop<_AddResult>(context, (
      deviceId: d.id,
      name: d.name,
      price: price == null || price < 1 ? 1 : price,
      onScreen: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.last;
    final s = ref.watch(appProvider);
    final show = s.liveShowById(widget.showId);
    final inShow = {...?show?.lots.map((l) => l.deviceId)};
    final mine = s.myDevices
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
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('Dodaj predmet'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('quick-name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: t('Naziv')),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('quick-price'),
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                      _name.text = _nextName(last.$1);
                      _price.text = last.$2 == last.$2.roundToDouble()
                          ? '${last.$2.toInt()}'
                          : '${last.$2}';
                    }),
                    icon: const Icon(Icons.replay, size: 18),
                    label: Text(t('Ponovi zadnji: {0}', [_nextName(last.$1)])),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('quick-add-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: kLiveRed,
                  foregroundColor: Colors.white,
                ),
                onPressed: _submit,
                child: Text(t('Dodaj u live')),
              ),
              if (mine.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(
                  t('Ili jednim dodirom iz svojih predmeta'),
                  style: TextStyle(
                    color: LoopColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  key: const ValueKey('live-mine'),
                  children: [
                    for (final d in mine)
                      ListTile(
                        key: ValueKey('live-add-${d.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: ItemThumb(device: d, size: 44),
                        title: Text(
                          d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.add_circle_outline),
                        onTap: () => _pick(d),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              TextButton(
                key: const ValueKey('quick-on-screen'),
                onPressed: () => Navigator.pop<_AddResult>(context, (
                  deviceId: null,
                  name: '',
                  price: 0,
                  onScreen: true,
                )),
                child: Text(t('Brojevi na ekranu (#150, #151…)')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Polu-prozirna ploča na sredini pozornice.
class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
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
    this.isHost = false,
  });

  /// Domaćin ne vidi zaštitu kupca ni novčanik.
  final bool isHost;

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

  @override
  Widget build(BuildContext context) {
    final left = lot.left(now);
    final hot =
        !result && left <= LiveShow.hotWindow && lot.mode == LotMode.auction;
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
            ? t('Osvojio si nagradu!')
            : t('Osvojio si!');
      } else {
        status = leader.userLabel;
        highlight = lot.mode == LotMode.giveaway
            ? t('je izvučen!')
            : t(' je osvojio!');
      }
    } else {
      status = switch (lot.mode) {
        LotMode.dutch => t('⬇️ Pada cijena · do {0}', [
          formatCredits(lot.lot.floorPrice),
        ]),
        LotMode.giveaway =>
          lot.lot.followersOnly
              ? t('Giveaway · samo pratitelji · {0} prijava', [
                  '${lot.entrants}',
                ])
              : t('Nagradna igra · {0} prijava', ['${lot.entrants}']),
        LotMode.auction =>
          leader == null
              ? t('Predmet {0}/{1} · još nema ponuda', [
                  '${lot.index + 1}',
                  '$total',
                ])
              : leader.userId == me
              ? t('Ti vodiš · tvoj maks {0}', [
                  formatCredits(myMax ?? lot.price),
                ])
              : t('{0} vodi', [leader.userLabel]),
      };
    }

    if (kSimpleDesign) {
      final progress = (left.inMilliseconds / (lotSeconds * 1000)).clamp(
        0.0,
        1.0,
      );
      return Padding(
        key: ValueKey(result ? 'live-result' : 'live-lot'),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    lot.lot.deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
                if (!result && !isHost)
                  IconButton(
                    key: const ValueKey('buyer-protection'),
                    tooltip: t('Zaštita kupca'),
                    onPressed: () => BuyerProtectionBadge.explain(context),
                    icon: const Icon(
                      Icons.verified_user_outlined,
                      color: Color(0xFF86F6D3),
                      size: 17,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        lot.mode == LotMode.giveaway
                            ? t('Besplatno')
                            : formatCredits(price),
                        key: const ValueKey('live-price'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w200,
                          fontSize: 48,
                          letterSpacing: -1.8,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!result && lot.mode == LotMode.auction)
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: progress, end: progress),
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 350),
                            builder: (_, value, _) => CircularProgressIndicator(
                              value: value,
                              strokeWidth: 2.5,
                              backgroundColor: Colors.white12,
                              color: hot ? kLiveRed : Colors.white,
                            ),
                          ),
                        ),
                        Text(
                          '${(left.inMilliseconds / 1000).ceil()}',
                          key: const ValueKey('live-secs'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Text(
              '$status$highlight',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
            if (d?.isDigital ?? false)
              Padding(
                key: const ValueKey('lot-digital-badge'),
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t('⬇️ Digitalno · preuzimanje odmah, bez dostave'),
                  style: const TextStyle(
                    color: Color(0xFF64B0FF),
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Column(
      key: ValueKey(result ? 'live-result' : 'live-lot'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!result && lot.mode == LotMode.auction)
          _TimeBar(
            left: left,
            total: Duration(seconds: lotSeconds),
            end: lot.end,
            hot: hot,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$status$highlight',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFAEAEB6),
                        fontSize: 12,
                      ),
                    ),
                    if (d?.isDigital ?? false)
                      Padding(
                        key: const ValueKey('lot-digital-badge'),
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          t('⬇️ Digitalno · preuzimanje odmah, bez dostave'),
                          style: const TextStyle(
                            color: Color(0xFF64B0FF),
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 84,
                child: Column(
                  key: const ValueKey('live-value'),
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      t('Trenutno').toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF98989F),
                        fontSize: 9,
                        letterSpacing: .5,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        lot.mode == LotMode.giveaway
                            ? t('Besplatno')
                            : formatCredits(price),
                        key: const ValueKey('live-price'),
                        style: const TextStyle(
                          color: Color(0xFFFFD60A),
                          fontWeight: FontWeight.w700,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    if (!result && lot.mode == LotMode.auction)
                      Text(
                        '${(left.inMilliseconds / 1000).ceil()} s',
                        key: const ValueKey('live-secs'),
                        style: TextStyle(
                          color: hot ? kLiveRed : Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    if (!result && !isHost)
                      InkWell(
                        key: const ValueKey('buyer-protection'),
                        onTap: () => BuyerProtectionBadge.explain(context),
                        child: const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Icon(
                            Icons.verified_user_outlined,
                            color: Color(0xFF30D158),
                            size: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Chat preko videa kao na Whatnotu: avatar, ime (domaćin s oznakom) i
/// poruka, bez oblačića. Ponude su istaknute, a reakcije (srca) lete uz
/// desni rub umjesto da zatrpaju chat.
class _ChatFilterChips extends StatelessWidget {
  const _ChatFilterChips({required this.value, required this.onChanged});
  final _ChatFilter value;
  final ValueChanged<_ChatFilter> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Wrap(
      spacing: 6,
      children: [
        for (final f in _ChatFilter.forModerators)
          ChoiceChip(
            key: ValueKey('chat-filter-${f.name}'),
            label: Text(t(f.label)),
            selected: f == value,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            labelStyle: TextStyle(
              color: f == value ? LoopColors.onAccent : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            backgroundColor: const Color(0x99202127),
            selectedColor: LoopColors.accent,
            side: BorderSide.none,
            onSelected: (_) => onChanged(f),
          ),
      ],
    ),
  );
}

enum _ChatFilter {
  all('Sve'),
  questions('Pitanja'),
  bids('Ponude'),
  mods('Mod'),
  muted('Utišani');

  const _ChatFilter(this.label);
  final String label;

  /// Filteri za domaćina i moderatore (samo oni vide "Utišani").
  static const forModerators = values;

  bool accepts(LiveEvent e, LiveShow show, Set<String> muted) => switch (this) {
    all => true,
    questions => e.type == LiveEventType.chat && e.text.contains('?'),
    bids => e.type == LiveEventType.bid || e.type == LiveEventType.take,
    mods => show.canModerate(e.userId),
    _ => muted.contains(e.userId),
  };
}

class _ChatFeed extends ConsumerWidget {
  const _ChatFeed({
    required this.feed,
    required this.me,
    required this.hostId,
    this.maxHeight = 210,
    this.large = false,
    this.filter = _ChatFilter.all,
    required this.show,
    this.muted = const {},
    this.banned = const {},
    this.moderator = false,
  });

  final double maxHeight;
  final _ChatFilter filter;
  final LiveShow show;
  final Set<String> muted;
  final Set<String> banned;

  /// Domaćin ili moderator (vidi i utišane poruke kad je filter "Utišani").
  final bool moderator;

  /// Veći tekst (voditelj).
  final bool large;

  final List<LiveEvent> feed;
  final String? me;
  final String hostId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = [
      for (final e in feed)
        if (!_LiveRoomViewState.isReaction(e) &&
            filter.accepts(e, show, muted) &&
            // Utišani i uklonjeni: poruke vidi samo moderator (filter Utišani).
            (filter == _ChatFilter.muted && moderator ||
                (!muted.contains(e.userId) && !banned.contains(e.userId))))
          e,
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
              padding: const EdgeInsets.only(bottom: 3),
              child: Container(
                padding: const EdgeInsets.fromLTRB(3, 2, 8, 3),

                child: _FeedLine(
                  event: e,
                  user: s.userById(e.userId),
                  mine: e.userId == me,
                  host: e.userId == hostId,
                  mod: show.isMod(e.userId),
                  large: large,
                ),
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
    this.mod = false,
    this.large = false,
  });

  final bool mod;
  final bool large;
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
        UserAvatar(user: user, size: large ? 28 : 20),
        const SizedBox(width: 6),
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
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: large ? 12.5 : 10.5,
                        fontWeight: FontWeight.w700,
                        shadows: _shadow,
                      ),
                    ),
                  ),
                  if (host || mod) ...[
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
                        host ? t('Domaćin') : t('Mod'),
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
                    ? t('licitira {0}', [formatCredits(event.amount)])
                    : event.text,
                maxLines: large ? 4 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bid ? const Color(0xFFFFD166) : Colors.white,
                  fontSize: large ? 14.5 : 12.5,
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
        t('Video radi u online verziji'),
        key: const ValueKey('live-video-offline'),
      );
    }
    final b = broadcaster;
    if (b != null) {
      return ValueListenableBuilder<int>(
        valueListenable: b.watching,
        builder: (_, n, _) => _pill(
          t('Video gleda {0}', ['$n']),
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
        LiveVideoStatus.connecting => _pill(t('Spajam video…')),
        LiveVideoStatus.offline => _pill(t('Video trenutno nije uključen')),
        LiveVideoStatus.blocked => _pill(
          LiveVideoConfig.hasTurn
              ? t('Video se ne spaja — pokušavam ponovno…')
              : t('Video ne prolazi kroz ovu mrežu — probaj isti Wi-Fi'),
          key: const ValueKey('live-video-blocked'),
        ),
      },
    );
  }
}

/// Domaćin: okreni kameru, mikrofon, kamera uključena/isključena.
class _HostControls extends StatelessWidget {
  const _HostControls({required this.broadcaster, required this.onMore});
  final LiveBroadcaster broadcaster;
  final VoidCallback onMore;

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
        button('live-rail-more', t('Više'), Icons.more_horiz, onMore),
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

/// Donja traka livea u stilu Douyina: narančasta vrećica (trgovina livea s
/// brojem predmeta), chat, srce i dijeljenje.
/// Brze reakcije (🔥 😮 💸 👏 😍) iznad trake + prekidač zvuka.
class _QuickReactions extends StatelessWidget {
  const _QuickReactions({
    required this.emojis,
    required this.onReact,
    required this.muted,
    required this.onSound,
  });

  final List<String> emojis;
  final void Function(String)? onReact;
  final bool muted;
  final VoidCallback onSound;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
    child: Row(
      children: [
        if (onReact != null)
          for (final e in emojis)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _ReactionChip(
                key: ValueKey('live-reaction-$e'),
                emoji: e,
                onTap: () => onReact!(e),
              ),
            ),
        const Spacer(),
        IconButton(
          key: const ValueKey('live-sound'),
          tooltip: muted ? t('Uključi zvuk') : t('Utišaj zvuk'),
          visualDensity: VisualDensity.compact,
          onPressed: onSound,
          icon: Icon(
            muted ? Icons.volume_off : Icons.volume_up,
            color: Colors.white70,
            size: 22,
          ),
        ),
      ],
    ),
  );
}

/// Emoji gumb koji "poskoči" na dodir.
class _ReactionChip extends StatefulWidget {
  const _ReactionChip({super.key, required this.emoji, required this.onTap});
  final String emoji;
  final VoidCallback onTap;

  @override
  State<_ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<_ReactionChip>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      _c.forward(from: 0);
      widget.onTap();
    },
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.scale(
        scale: 1 + 0.35 * math.sin(_c.value * math.pi),
        child: child,
      ),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        child: Text(
          widget.emoji,
          style: const TextStyle(
            fontSize: 20,
            shadows: [Shadow(blurRadius: 5, color: Colors.black54)],
          ),
        ),
      ),
    ),
  );
}

class _DouyinBar extends StatelessWidget {
  const _DouyinBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.showChat,
    required this.bagCount,
    required this.onBag,
    required this.liked,
    required this.onHeart,
    required this.onMore,
    required this.guest,
    required this.onLogin,
  });

  final bool guest;
  final VoidCallback onLogin;

  /// Pisanje u chatu (kao Whatnot): polje preko cijele širine s "Aa",
  /// bez vrećice, srca i dijeljenja.
  bool get composing => focusNode.hasFocus;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function(String) onSend;
  final bool showChat;
  final int bagCount;
  final VoidCallback onBag;
  final bool liked;
  final VoidCallback? onHeart;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    child: Row(
      children: [
        Expanded(
          child: showChat
              ? TextField(
                  key: const ValueKey('live-chat'),
                  readOnly: guest,
                  canRequestFocus: !guest,
                  onTap: guest ? onLogin : null,
                  controller: controller,
                  focusNode: focusNode,
                  scrollPadding: const EdgeInsets.all(12),
                  maxLength: LiveEvent.maxText,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.send,
                  onSubmitted: onSend,
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: t('Pitaj prodavača uživo…'),
                    hintStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0x9928282D),
                    // Pisanje: "Aa" lijevo, kao na Whatnotu.
                    prefixIcon: composing
                        ? Padding(
                            padding: const EdgeInsets.all(6),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.18,
                              ),
                              child: const Text(
                                'Aa',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
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
                      borderSide: const BorderSide(color: Colors.white38),
                    ),
                    suffixIcon: IconButton(
                      key: ValueKey(
                        composing ? 'live-send' : 'live-room-tools',
                      ),
                      tooltip: composing ? t('Pošalji') : t('Više'),
                      onPressed: composing
                          ? () => onSend(controller.text)
                          : onMore,
                      icon: Icon(
                        composing ? Icons.send : Icons.more_horiz,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    ),
  );
}

/// Trgovina livea (Douyin): numerirani predmeti s velikom slikom, cijenom
/// i gumbom — kartica "Na aukciji" (predlicitacija, domaćin pokreće) i
/// "Kupi odmah" (kupnja bilo kada tijekom livea).
class _LiveShopSheet extends ConsumerWidget {
  const _LiveShopSheet({
    required this.showId,
    required this.isHost,
    required this.onStart,
    required this.onPreBid,
  });

  final String showId;
  final bool isHost;
  final void Function(int index) onStart;
  final Future<void> Function(LotState lot) onPreBid;

  static const _white = Color(0xFFF5F5F7);
  static const _muted = Color(0xFFAEAEB6);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final show = s.liveShowById(showId);
    if (show == null) return const SizedBox.shrink();
    final st = s.liveStateOf(show, DateTime.now());
    final me = s.currentUserId;

    Widget thumb(Device? d, int n, {bool running = false}) => SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: d != null
                  ? ItemThumb(device: d, size: 56)
                  : const ColoredBox(color: Colors.white12),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: running ? kLiveRed : Colors.black.withValues(alpha: 0.7),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomRight: Radius.circular(10),
                ),
              ),
              child: Text(
                running ? t('UŽIVO') : '$n',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Widget row({
      required Key key,
      required Widget image,
      required String title,
      required String price,
      required Color priceColor,
      String? note,
      Widget? action,
    }) => Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .15)),
      ),
      child: Row(
        children: [
          image,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _white,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  price,
                  style: TextStyle(
                    color: priceColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                if (note != null)
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action],
        ],
      ),
    );

    final lots = st.lots;
    bool finished(LotState l) =>
        l.status == LotStatus.sold ||
        l.status == LotStatus.unsold ||
        l.status == LotStatus.skipped;
    final auctionLots = [
      for (final l in lots)
        if (l.mode != LotMode.giveaway && !finished(l)) l,
    ];
    final giveawayLots = [
      for (final l in lots)
        if (l.mode == LotMode.giveaway) l,
    ];
    final soldLots = [
      for (final l in lots)
        if (l.mode != LotMode.giveaway && finished(l)) l,
    ];
    Widget lotTab(
      List<LotState> list,
      String empty, {
      bool hint = false,
    }) => ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        if (hint && !isHost && st.queue.any((l) => l.mode == LotMode.auction))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              t(
                'Predlicitiraj predmet koji tek dolazi — tvoja maksimalna ponuda vrijedi kad krene.',
              ),
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
        if (list.isEmpty) Text(empty, style: const TextStyle(color: _muted)),
        for (final l in list)
          row(
            key: ValueKey('live-lot-row-${l.index}'),
            image: thumb(
              s.deviceById(l.lot.deviceId),
              l.index + 1,
              running: l.status == LotStatus.running,
            ),
            title: l.mode == LotMode.auction
                ? l.lot.deviceName
                : '${l.mode.emoji} ${l.lot.deviceName}',
            price: switch (l.status) {
              LotStatus.upcoming when l.leader == null => t('Od {0}', [
                formatCredits(l.lot.startPrice),
              ]),
              _ => formatCredits(l.price),
            },
            priceColor: l.status == LotStatus.sold
                ? _muted
                : const Color(0xFFFFA24C),
            note: switch (l.status) {
              LotStatus.running => t('Licitira se sada'),
              LotStatus.upcoming when l.leader != null =>
                l.leader!.userId == me
                    ? t('Tvoja predponuda vodi')
                    : t('Predponuda: {0}', [l.leader!.userLabel]),
              LotStatus.upcoming => null,
              LotStatus.sold => t('Prodano · {0}', [l.leader!.userLabel]),
              LotStatus.unsold => t('Nije prodano'),
              LotStatus.skipped => t('Preskočeno'),
            },
            action: isHost && st.canStart && l.status == LotStatus.upcoming
                ? FilledButton(
                    key: ValueKey('live-start-${l.index}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: kLiveRed,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => onStart(l.index),
                    child: Text(t('Pokreni')),
                  )
                : !isHost &&
                      !st.isOver &&
                      l.status == LotStatus.upcoming &&
                      l.mode == LotMode.auction
                ? FilledButton(
                    key: ValueKey('live-prebid-${l.index}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: kBidOrange,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => onPreBid(l),
                    child: Text(t('Predlicitiraj')),
                  )
                : null,
          ),
      ],
    );
    final auctionTab = lotTab(
      auctionLots,
      t('Još nema predmeta na aukciji.'),
      hint: true,
    );
    // Kupi odmah vidi se samo kad je prodavač uključio trgovinu u liveu.
    final products = show.shop
        ? liveShopProducts(s, show.hostId)
        : const <Device>[];
    final shopTab = ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        if (products.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              t('Trgovina još nema oglasa.'),
              style: const TextStyle(color: _muted),
            ),
          ),
        for (final device in products)
          row(
            key: ValueKey('live-shop-product-${device.id}'),
            image: thumb(device, products.indexOf(device) + 1),
            title: device.name,
            price: formatCredits(s.priceForMe(device)),
            priceColor: const Color(0xFFFFD60A),
            action: FilledButton(
              key: ValueKey('live-shop-buy-${device.id}'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0A84FF),
                foregroundColor: Colors.white,
                minimumSize: const Size(70, 40),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                shape: const StadiumBorder(),
              ),
              onPressed: () => isHost
                  ? DeviceDetailScreen.open(context, device)
                  : confirmAndBuy(context, ref, device),
              child: Text(isHost ? t('Detalji') : t('Kupi odmah')),
            ),
          ),
        TextButton.icon(
          key: const ValueKey('live-open-seller-shop'),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
          onPressed: () => PublicProfileScreen.open(context, show.hostId),
          icon: const Icon(Icons.storefront_outlined, size: 18),
          label: Text(t('Otvori shop')),
        ),
      ],
    );
    return DefaultTabController(
      length:
          (show.shop ? 1 : 0) +
          1 +
          (giveawayLots.isNotEmpty ? 1 : 0) +
          (soldLots.isNotEmpty ? 1 : 0),
      // Prodavač najprije vidi red licitacija, gledatelj trgovinu.
      initialIndex: show.shop && isHost ? 1 : 0,
      child: SizedBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Shop and auction queue stay inside the broadcast.
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: .10)),
              ),
              child: TabBar(
                isScrollable: giveawayLots.isNotEmpty || soldLots.isNotEmpty,
                tabAlignment: giveawayLots.isNotEmpty || soldLots.isNotEmpty
                    ? TabAlignment.start
                    : TabAlignment.fill,
                labelColor: _white,
                unselectedLabelColor: _muted,
                indicatorColor: kBidOrange,
                indicator: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(11),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontFamily: kFontFamily,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  if (show.shop)
                    Tab(
                      height: 36,
                      key: const ValueKey('live-tab-shop'),
                      text: t('Kupi odmah ({0})', ['${products.length}']),
                    ),
                  Tab(
                    height: 36,
                    key: const ValueKey('live-tab-auction'),
                    text: t('Aukcija ({0})', ['${auctionLots.length}']),
                  ),
                  if (giveawayLots.isNotEmpty)
                    Tab(
                      height: 36,
                      key: const ValueKey('live-tab-giveaway'),
                      text: t('Giveaway ({0})', ['${giveawayLots.length}']),
                    ),
                  if (soldLots.isNotEmpty)
                    Tab(
                      height: 36,
                      key: const ValueKey('live-tab-sold'),
                      text: t('Prodano ({0})', ['${soldLots.length}']),
                    ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  if (show.shop) shopTab,
                  auctionTab,
                  if (giveawayLots.isNotEmpty)
                    lotTab(giveawayLots, t('Nema giveawaya u ovom showu.')),
                  if (soldLots.isNotEmpty)
                    lotTab(soldLots, t('Još ništa nije prodano.')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Izvlačenje nagradne igre: imena prijavljenih se vrte kao bubanj,
/// usporavaju i stanu na dobitniku — zatim konfete i "Dobitnik!".
class _GiveawaySpin extends StatefulWidget {
  const _GiveawaySpin({super.key, required this.names, required this.winner});

  final List<String> names;
  final String winner;

  /// Koliko se bubanj vrti (čestitka dobitniku dolazi nakon toga).
  static const duration = Duration(milliseconds: 4200);

  @override
  State<_GiveawaySpin> createState() => _GiveawaySpinState();
}

class _GiveawaySpinState extends State<_GiveawaySpin>
    with SingleTickerProviderStateMixin {
  static const _row = 44.0;
  static const _gold = Color(0xFFFFC233);

  late final _c = AnimationController(
    vsync: this,
    duration: _GiveawaySpin.duration,
  )..forward();

  /// Bubanj: imena ponovljena nekoliko krugova, dobitnik na kraju.
  late final List<String> _reel = () {
    final others = [
      for (final n in widget.names)
        if (n != widget.winner) n,
    ];
    final pool = others.isEmpty ? [widget.winner] : others;
    final r = math.Random(widget.winner.hashCode);
    return [
      for (var i = 0; i < 28; i++) pool[r.nextInt(pool.length)],
      widget.winner,
    ];
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final done = _c.isCompleted;
        // Brzo pa sve sporije (kao kolo sreće).
        final pos =
            Curves.easeOutQuart.transform(_c.value) * (_reel.length - 1);
        final base = pos.floor();
        final frac = pos - base;
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x88000000)),
            if (done) const ConfettiBurst(),
            Center(
              child: Container(
                width: 260,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xEE17120F),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _gold, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withValues(alpha: done ? 0.6 : 0.25),
                      blurRadius: done ? 30 : 16,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      done ? t('Dobitnik!') : t('Izvlačenje…'),
                      style: const TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Prozor bubnja: tri reda, srednji je odabrani.
                    SizedBox(
                      height: _row * 3,
                      child: ClipRect(
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: _row,
                              height: _row,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _gold.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _gold),
                                ),
                              ),
                            ),
                            for (var k = -1; k <= 2; k++)
                              if (base + k >= 0 && base + k < _reel.length)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: _row * (1 + k - frac),
                                  height: _row,
                                  child: Center(
                                    child: Text(
                                      _reel[base + k],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: k == 0 || (k == 1 && frac > 0.5)
                                            ? Colors.white
                                            : Colors.white38,
                                        fontWeight: FontWeight.w900,
                                        fontSize: done && k == 0 ? 20 : 17,
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      done
                          ? t('{0} osvaja nagradu!', [widget.winner])
                          : t('{0} prijavljenih', ['${widget.names.length}']),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Traka preostalog vremena licitacije s brojem sekundi. U zadnjim
/// sekundama je crvena i treperi; kad ponuda produlji sat, iskoči "+2 s".
class _TimeBar extends StatefulWidget {
  const _TimeBar({
    required this.left,
    required this.total,
    required this.end,
    required this.hot,
  });

  final Duration left;
  final Duration total;
  final DateTime? end;
  final bool hot;

  @override
  State<_TimeBar> createState() => _TimeBarState();
}

class _TimeBarState extends State<_TimeBar> with TickerProviderStateMixin {
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final _bonus = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  int _added = 0;

  @override
  void initState() {
    super.initState();
    if (widget.hot) _blink.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_TimeBar old) {
    super.didUpdateWidget(old);
    if (widget.hot && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    } else if (!widget.hot && _blink.isAnimating) {
      _blink
        ..stop()
        ..value = 0;
    }
    // Sat je produljen (nova ponuda) → "+N s".
    final was = old.end;
    final now = widget.end;
    if (was != null && now != null && now.isAfter(was)) {
      _added = now.difference(was).inSeconds;
      _bonus.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    _bonus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.total.inMilliseconds == 0
        ? 0.0
        : (widget.left.inMilliseconds / widget.total.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    return AnimatedBuilder(
      animation: Listenable.merge([_blink, _bonus]),
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          Container(height: 3, color: Colors.white12),
          FractionallySizedBox(
            widthFactor: f,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.hot
                      ? [kLiveRed, const Color(0xFFFFD60A)]
                      : [const Color(0xFF0A84FF), const Color(0xFFFFD60A)],
                ),
              ),
            ),
          ),
          if (_bonus.isAnimating)
            Positioned(
              right: 12,
              top: -18,
              child: Opacity(
                opacity: 1 - _bonus.value,
                child: Text(
                  '+$_added s',
                  key: const ValueKey('live-bonus'),
                  style: const TextStyle(
                    color: Color(0xFFFFD60A),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
