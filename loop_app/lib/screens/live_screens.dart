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
import '../models/country.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../providers/app_providers.dart';
import '../services/live_service.dart';
import '../services/live_sound/live_sound.dart';
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
import 'seller_screens.dart' show ensureSellerInfo;

/// Crvena boja live aukcija (oznaka UŽIVO, gumb za licitiranje).
const kLiveRed = LoopColors.live;

/// Pozadina listova u liveu (live je uvijek taman).
const kLiveSheet = Color(0xFF17120F);

/// Glavna radnja u liveu (Licitiraj) — narančasta, crvena je samo "uživo".
const kBidOrange = Color(0xFFF26B1D);
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

/// Zadnji brzo dodani predmet ("Ponovi zadnji") za sheet "Dodaj u show".
(String, double)? _lastQuickAdd;

/// "Dodaj u show": predmet iz zalihe ili potpuno novi (naziv i cijena).
/// Radi i za zakazani show, prije nego što domaćin uđe u sobu.
Future<void> showAddToShowSheet(
  BuildContext context,
  WidgetRef ref,
  LiveShow show,
) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t('Dodaj u show'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('add-to-show-stock'),
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(t('Iz zalihe')),
            subtitle: Text(t('Odaberi predmet koji već imaš.')),
            onTap: () => Navigator.pop(ctx, 'stock'),
          ),
          ListTile(
            key: const ValueKey('add-to-show-new'),
            leading: const Icon(Icons.bolt),
            title: Text(t('Novi predmet')),
            subtitle: Text(t('Samo naziv i početna cijena.')),
            onTap: () => Navigator.pop(ctx, 'new'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final app = ref.read(appProvider.notifier);
  if (choice == 'stock') {
    final added = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: kLiveSheet,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _AddLotSheet(showId: show.id),
    );
    if (added == true) showLoopSnackBar(t('Predmet je dodan u live.'));
    return;
  }
  final r = await showModalBottomSheet<(String, double)>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: kLiveSheet,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => _QuickAddSheet(last: _lastQuickAdd),
  );
  if (r == null || !context.mounted) return;
  final (name, price) = r;
  final category =
      suggestCategory(name) ??
      DeviceCategory.values.firstWhere(
        (c) => c.name == show.category,
        orElse: () => DeviceCategory.other,
      );
  final ok = await runWithLoading(context, () async {
    final d = await app.addDevice(
      name: name,
      model: '',
      condition: DeviceCondition.good,
      price: price,
      category: category,
      listOnMarket: false,
    );
    await app.liveAddLot(show.id, d.id, price);
  }, successMessage: null);
  if (!ok) return;
  _lastQuickAdd = r;
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

class _ViewersChip extends StatelessWidget {
  const _ViewersChip(this.count);
  final int count;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$count',
    child: Container(
      key: const ValueKey('live-viewers'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: kLiveRed,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bar_chart, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            count >= 1000 ? '${(count / 1000).toStringAsFixed(1)}k' : '$count',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
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
            category: (_category ?? DeviceCategory.other).name,
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
          category: _category,
          // Neprodano ostaje spremljeno u Moje (ne ide samo na Kupi odmah).
          relistUnsold: false,
        );
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
        builder: (_) => LiveRoomScreen(showId: created!.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
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
              // 3. Predmeti ovog livea: brzo dodaj (sa slikom) ili
              //    "items on screen" (#150, #151… bez slike).
              Text(
                t('Predmeti u ovom liveu ({0}/{1})', [
                  '${_selected.length + _drafts.length}',
                  '$_maxLots',
                ]),
                style: bold,
              ),
              const SizedBox(height: 4),
              Text(
                t(
                  'Dodaj predmete samo za ovaj live. Licitiraju se redom — nakon svake prodaje dolazi sljedeći.',
                ),
                style: TextStyle(color: LoopColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _AddLotButton(
                      key: const ValueKey('live-quick-item'),
                      icon: Icons.add_a_photo_outlined,
                      title: t('Brzo dodaj'),
                      subtitle: t('Predmet sa slikom'),
                      onTap: _addQuick,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AddLotButton(
                      key: const ValueKey('live-on-screen'),
                      icon: Icons.tag,
                      title: t('Items on screen'),
                      subtitle: t('#150, #151… kao 1 predmet'),
                      onTap: _addOnScreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
                                  label: Text(
                                    sec <= 10
                                        ? '⚡ ${t('{0} s', ['$sec'])}'
                                        : t('{0} s', ['$sec']),
                                  ),
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
                    '• Live traje dok si uživo — završavaš ga ti (ili kad izađeš).\n• Ti biraš predmet i pokrećeš licitaciju od {0} s.\n• Svaka ponuda dodaje 2 s na sat (brze licitacije: 5 ili 10 s).\n• Pobjednik plaća automatski karticom, a dostava kreće na njegovu adresu.\n• Provizija je 10 % samo od razlike iznad početne cijene.',
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
            ],
          ),
        ),
      ),
      // Gumb za objavu uvijek je vidljiv na dnu ekrana.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 568),
              child: FilledButton.icon(
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
  const _DraftLot(
    this.name,
    this.price, {
    this.photo,
    this.from,
    this.count = 1,
  });
  final String name;
  final double price;
  final String? photo;

  /// "Items on screen": jedan predmet s [count] komada, brojevi od
  /// [from] (#150, #151…). `null` = obični predmet.
  final int? from;
  final int count;
  bool get onScreen => from != null;

  /// Zadnji broj u nizu (za nastavak brojanja).
  int? get last => from == null ? null : from! + count - 1;
}

/// Veliki gumb za dodavanje predmeta u live.
class _AddLotButton extends StatelessWidget {
  const _AddLotButton({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: LoopColors.surface,
    borderRadius: BorderRadius.circular(kRadius),
    child: InkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: kLiveRed.withValues(alpha: 0.12),
              child: Icon(icon, color: kLiveRed, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
      ),
    ),
  );
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
                color: const Color(0xFF17120F),
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
            lot.onScreen ? '${lot.name} #${lot.from}–#${lot.last}' : lot.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            lot.onScreen
                ? t('Items on screen · {0} brojeva · od {1}', [
                    '${lot.count}',
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
          t('⚡ Brzo dodaj predmet'),
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

  /// Najviše brojeva u jednom nizu (svejedno je jedan predmet).
  static const max = 200;

  @override
  State<_OnScreenSheet> createState() => _OnScreenSheetState();
}

class _OnScreenSheetState extends State<_OnScreenSheet> {
  late final _name = TextEditingController(text: t('Predmet'));
  late final _from = TextEditingController(text: '${widget.start}');
  late final _count = TextEditingController(text: '10');
  final _price = TextEditingController(text: '1');

  @override
  void dispose() {
    for (final c in [_name, _from, _count, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final from = int.tryParse(_from.text.trim());
    final count = int.tryParse(_count.text.trim());
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (name.isEmpty ||
        from == null ||
        from < 0 ||
        count == null ||
        count < 1 ||
        price == null ||
        price < 1) {
      showLoopSnackBar(
        t('Upiši naziv, broj, količinu i cijenu (barem 1 €).'),
        error: true,
      );
      return;
    }
    if (count > _OnScreenSheet.max) {
      showLoopSnackBar(
        t('Najviše {0} brojeva u nizu.', ['${_OnScreenSheet.max}']),
        error: true,
      );
      return;
    }
    Navigator.pop(context, _DraftLot(name, price, from: from, count: count));
  }

  @override
  Widget build(BuildContext context) {
    final from = int.tryParse(_from.text) ?? widget.start;
    final count = int.tryParse(_count.text) ?? 0;
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
            t('🔢 Items on screen'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          Text(
            t(
              'Jedan predmet s brojevima, bez slike — pokazuješ ih na kameri. Nakon svake prodaje na ekranu se pojavi sljedeći broj.',
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
                  key: const ValueKey('on-screen-count'),
                  controller: _count,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('Koliko (do {0})', ['${_OnScreenSheet.max}']),
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
          if (count > 0)
            Text(
              t('{0} #{1} … #{2}', [
                _name.text.trim(),
                '$from',
                '${from + count - 1}',
              ]),
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
      successMessage: t('Uživo si! 🔴'),
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
      color: const Color(0xFF26272C),
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
                        color: const Color(0xFF26272C),
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
                      icon: Icons.inventory_2_outlined,
                      label: t('Dodaj iz mojih predmeta'),
                      onTap: () => _addItem(show),
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
                      key: 'live-quick-add-tile',
                      icon: Icons.bolt,
                      label: t('Brzo dodaj'),
                      onTap: () => _quickAdd(show),
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

  /// Domaćin dodaje predmet u live (iz svojih predmeta ili novi).
  Future<void> _addItem(LiveShow show) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: kLiveSheet,
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
      backgroundColor: kLiveSheet,
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
            title: l.mode == LotMode.dutch
                ? t('Kupljeno! 🎉')
                : t('Osvojio si! 🎉'),
            subtitle: t('Plaćeno karticom · odaberi dostavu'),
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

  /// Trgovina livea (kao Douyin): predmeti na aukciji (predlicitacija) i
  /// prodavačevi predmeti za Kupi odmah, u dvije kartice.
  void _showQueue(LiveState st, bool isHost) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: kLiveSheet,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (ctx) => _LiveShopSheet(
      showId: st.show.id,
      isHost: isHost,
      onStart: (i) {
        Navigator.pop(ctx);
        _startLot(i);
      },
      onPreBid: (l) async {
        final mine = l.leader?.userId == ref.read(appProvider).currentUserId;
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
      },
    ),
  );

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
                              // Završen live: sažetak točno u sredini.
                              padding: EdgeInsets.fromLTRB(
                                16,
                                16,
                                st.isOver ? 16 : 72,
                                16,
                              ),
                              child: center,
                            ),
                          ),
                          if (showSweep) ...[
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ConfettiBurst(
                                  key: ValueKey('live-confetti-${sweep.index}'),
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
                                    s.userById(sweep.leader!.userId)?.handle ??
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
                                            c.maxHeight * (isHost ? 0.7 : 0.55),
                                          ),
                                        ),
                                        if (show.canModerate(me?.id) &&
                                            !composing)
                                          _ChatFilterChips(
                                            value: _chatFilter,
                                            onChanged: (f) =>
                                                setState(() => _chatFilter = f),
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
                            backgroundColor: LoopColors.buyNow,
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
                    // Voditelju reakcije ne trebaju (srca i tako lete preko
                    // videa) — više mjesta za chat i upravljanje.
                    if (!st.isOver && !composing && !isHost)
                      _QuickReactions(
                        emojis: _quick,
                        onReact: _react,
                        muted: _muted,
                        onSound: _toggleSound,
                      ),
                    // Douyin: dolje trgovina (vrećica), chat, srce, dijeljenje.
                    _DouyinBar(
                      controller: _chat,
                      focusNode: _chatFocus,
                      onSend: _send,
                      showChat: !st.isOver,
                      guest: !canAct,
                      onLogin: () => blockGuest(context),
                      bagCount:
                          st.queue.length +
                          s
                              .listingsOf(show.hostId)
                              .where((d) => !d.isDigital)
                              .length,
                      onBag: () => _showQueue(st, isHost),
                      liked: _liked,
                      onHeart: st.isOver || isHost ? null : _toggleLike,
                      showWallet: !isHost,
                      onShare: () => shareLink(
                        context,
                        publicLink(live: show.id),
                        text: t('Gledaj "{0}" uživo na Subhastu', [show.title]),
                      ),
                    ),
                    if (!composing && !st.isOver)
                      _FlashBar(hostId: show.hostId, now: now),
                    if (!composing && cur != null)
                      _LotCard(
                        lot: cur,
                        device: s.deviceById(cur.lot.deviceId),
                        total: show.lots.length,
                        lotSeconds: cur.lot.seconds ?? show.lotSeconds,
                        now: now,
                        me: me?.id,
                        leaderUser: s.userById(cur.leader?.userId),
                        isHost: isHost,
                      )
                    else if (!composing && done != null && !st.isOver)
                      _LotCard(
                        lot: done,
                        device: s.deviceById(done.lot.deviceId),
                        total: show.lots.length,
                        lotSeconds: done.lot.seconds ?? show.lotSeconds,
                        now: now,
                        me: me?.id,
                        leaderUser: s.userById(done.leader?.userId),
                        result: true,
                      ),
                    if (!composing)
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
              tooltip: t('⚡ Brzo dodaj'),
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
          backgroundColor: LoopColors.buyNow,
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

  Widget _leading(LotState cur, String? me) => Container(
    key: const ValueKey('live-leading'),
    height: 54,
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

  Widget _bidRow(LotState cur) {
    // Kao Whatnot: lijevo bijela obrubljena pilula "Iznos" (vlastita
    // ponuda), desno široka pilula "Licitiraj: X »".
    return Row(
      children: [
        SizedBox(
          height: 52,
          child: OutlinedButton(
            key: const ValueKey('live-bid-custom'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: Colors.white70, width: 1.5),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              textStyle: const TextStyle(
                fontFamily: kFontFamily,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            onPressed: _busy ? null : () => _customBid(cur),
            child: Text(t('Iznos')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            key: const ValueKey('live-bid'),
            style: FilledButton.styleFrom(
              backgroundColor: kBidOrange,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontFamily: kFontFamily,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            onPressed: _busy ? null : () => _bid(cur.minNext),
            child: Text(
              '${t('Licitiraj {0}', [formatCredits(cur.minNext)])}  »',
            ),
          ),
        ),
      ],
    );
  }

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
    final meta = rating.count > 0
        ? '★ ${rating.average.toStringAsFixed(1)}'
        : t('★ Novo');
    return Padding(
      key: const ValueKey('live-compact-header'),
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => PublicProfileScreen.open(context, show.hostId),
            child: UserAvatar(user: host, size: 30),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: GestureDetector(
              onTap: () => PublicProfileScreen.open(context, show.hostId),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // Zastavica države domaćina.
                    host == null
                        ? hostName
                        : '${countryOf(host!.country).flag} $hostName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      shadows: _shadow,
                    ),
                  ),
                  Text(
                    show.verifiedOnly
                        ? '$meta · ${t('Provjereni kupci')} · ${show.title}'
                        : '$meta · ${show.title}',
                    key: const ValueKey('live-host-meta'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      shadows: _shadow,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (me != show.hostId) ...[
            const SizedBox(width: 6),
            FilledButton(
              key: const ValueKey('live-follow'),
              // Kao Whatnot: "Prati" je pilula u boji akcenta.
              style: FilledButton.styleFrom(
                backgroundColor: kBidOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.16),
                disabledForegroundColor: Colors.white,
                minimumSize: const Size(56, 30),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
                shape: const StadiumBorder(),
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
                      showLoopSnackBar(t('Pratiš {0}', [hostName]));
                    },
              child: Text(t(following ? 'Pratim' : 'Prati')),
            ),
          ],
          const SizedBox(width: 6),
          if (state.isLive)
            InkWell(
              key: const ValueKey('live-viewers-open'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                backgroundColor: kLiveSheet,
                constraints: const BoxConstraints(maxWidth: 520),
                builder: (_) => _ViewersSheet(showId: show.id),
              ),
              child: _ViewersChip(state.viewers),
            )
          else
            Text(
              state.isScheduled ? t('ZAKAZANO') : t('ZAVRŠENO'),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          IconButton(
            key: const ValueKey('live-close'),
            tooltip: t('Zatvori'),
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white,
              size: 24,
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

/// Brzo dodavanje predmeta u live: naziv i početna cijena.
class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet({this.last});
  final (String, double)? last;

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
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
                  _name.text = _nextName(last.$1);
                  _price.text = last.$2 == last.$2.roundToDouble()
                      ? '${last.$2.toInt()}'
                      : '${last.$2}';
                }),
                icon: const Icon(Icons.replay, size: 18),
                label: Text(t('Ponovi zadnji: {0}', [_nextName(last.$1)])),
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

  static const _shadow = [Shadow(blurRadius: 6, color: Colors.black87)];
  static const _yellow = Color(0xFFFFD166);

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
        LotMode.giveaway =>
          lot.lot.followersOnly
              ? t('🎁 Giveaway · samo pratitelji · {0} prijava', [
                  '${lot.entrants}',
                ])
              : t('🎁 Nagradna igra · {0} prijava', ['${lot.entrants}']),
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

    // Velika kartica trenutnog predmeta na dnu (tamni poluprozirni panel).
    return Container(
      key: ValueKey(result ? 'live-result' : 'live-lot'),
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 0),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xE6131419),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leader != null) ...[
                UserAvatar(user: leaderUser, size: 18),
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
                    fontSize: 13,
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
                    ? ItemThumb(device: d, size: 44)
                    : Container(
                        width: 44,
                        height: 44,
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
                        fontSize: 13,
                        height: 1.15,
                        shadows: _shadow,
                      ),
                    ),
                    // Digitalni proizvod u liveu: odmah nakon pobjede/plaćanja.
                    if (d != null && d.isDigital)
                      Padding(
                        key: const ValueKey('lot-digital-badge'),
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          t('⬇️ Digitalno · preuzimanje odmah, bez dostave'),
                          style: const TextStyle(
                            color: Color(0xFF6CB4FF),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (d != null)
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${d.condition.label} · ${d.category.singular}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                shadows: _shadow,
                              ),
                            ),
                          ),
                          if (!result && !isHost) ...[
                            const SizedBox(width: 6),
                            // Zaštita kupca: mali štit, dodir objašnjava.
                            InkWell(
                              key: const ValueKey('buyer-protection'),
                              onTap: () =>
                                  BuyerProtectionBadge.explain(context),
                              child: const Icon(
                                Icons.verified_user,
                                size: 16,
                                color: Color(0xFF4ADE80),
                              ),
                            ),
                          ],
                        ],
                      ),
                    const SizedBox(height: 4),
                    // Samo kad je predmet posebne vrste (pada cijena, igra).
                    if (lot.mode != LotMode.auction)
                      chip('${lot.mode.emoji} ${lot.mode.label}'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: Column(
                  key: const ValueKey('live-value'),
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          lot.mode == LotMode.giveaway
                              ? t('Besplatno')
                              : formatCredits(price),
                          key: const ValueKey('live-price'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 25,
                            height: 1.05,
                            shadows: _shadow,
                          ),
                        ),
                      ),
                    ),
                    if (value > 0)
                      Text(
                        t('💎 procjena {0}', [formatCredits(value)]),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          shadows: _shadow,
                        ),
                      ),
                    if (result)
                      Text(
                        leader == null
                            ? t('Nije prodano')
                            : leader.userId == me
                            ? t('Osvojeno 🎉')
                            : t('Prodano'),
                        style: TextStyle(
                          color: leader == null ? Colors.white70 : kLiveRed,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          shadows: _shadow,
                        ),
                      )
                    else ...[
                      // Samo kad je razlika velika (inače je šum).
                      if (below >= 30)
                        Text(
                          t('−{0}% ispod procjene', ['$below']),
                          style: const TextStyle(
                            color: Color(0xFF4ADE80),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            shadows: _shadow,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // Traka vremena: smanjuje se, u zadnjim sekundama crveno treperi,
          // a svaka ponuda iskoči kao "+2 s".
          if (!result && lot.mode == LotMode.auction)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _TimeBar(
                left: left,
                total: Duration(seconds: lotSeconds),
                end: lot.end,
                hot: hot,
              ),
            ),
        ],
      ),
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
                    ? t('licitira {0} 🔨', [formatCredits(event.amount)])
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
          (d) => s.activeAuctionFor(d.id) == null && !inShow.contains(d.id),
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
                    // Većina koristi običnu licitaciju — posebne vrste
                    // (pada cijena, nagradna igra) su pod "Napredno".
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        key: const ValueKey('lot-advanced'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        initiallyExpanded: _mode != LotMode.auction,
                        title: Text(
                          _mode == LotMode.auction
                              ? t('Napredno: pada cijena, nagradna igra')
                              : '${_mode.emoji} ${t(_mode.label)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        children: [
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
                        ],
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
    required this.onShare,
    this.showWallet = false,
    required this.guest,
    required this.onLogin,
  });

  /// Novčanik uz srce i dijeljenje (gledatelji).
  final bool showWallet;
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
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(10, 4, composing ? 10 : 6, 6),
    child: Row(
      children: [
        if (!composing) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('live-queue'),
              borderRadius: BorderRadius.circular(10),
              onTap: onBag,
              child: Ink(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xCC202127),
                ),
                child: Center(
                  child: Badge(
                    isLabelVisible: bagCount > 0,
                    label: Text('$bagCount'),
                    backgroundColor: kLiveRed,
                    child: const Icon(
                      Icons.shopping_bag,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
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
                    hintText: t('Reci nešto…'),
                    hintStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xA6202127),
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
                      key: const ValueKey('live-send'),
                      tooltip: t('Pošalji'),
                      onPressed: () => onSend(controller.text),
                      icon: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (onHeart != null && !composing)
          IconButton(
            key: const ValueKey('live-react-0'),
            tooltip: t('Srce'),
            onPressed: onHeart,
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
                      size: 24,
                    )
                  : const Icon(
                      Icons.favorite_border,
                      key: ValueKey('not-liked'),
                      color: Colors.white,
                      size: 24,
                    ),
            ),
          ),
        if (showWallet && !composing && guest)
          IconButton(
            key: const ValueKey('live-wallet-login'),
            tooltip: t('Novčanik'),
            onPressed: onLogin,
            icon: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        if (showWallet && !composing && !guest)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: WalletChip(dark: true),
          ),
        if (!composing)
          IconButton(
            key: const ValueKey('live-share'),
            tooltip: t('Podijeli'),
            onPressed: onShare,
            icon: const Icon(Icons.ios_share, color: Colors.white, size: 22),
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

  static const _white = Color(0xFFF5EDE6);
  static const _muted = Color(0xFFB3A69B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final show = s.liveShowById(showId);
    if (show == null) return const SizedBox.shrink();
    final st = s.liveStateOf(show, DateTime.now());
    final me = s.currentUserId;
    final host = s.userById(show.hostId);
    final shop = [
      for (final d in s.listingsOf(show.hostId))
        if (!d.isDigital) d,
    ];
    final h = MediaQuery.sizeOf(context).height;

    Widget thumb(Device? d, int n, {bool running = false}) => SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: d != null
                  ? ItemThumb(device: d, size: 72)
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
                  fontWeight: FontWeight.w900,
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
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
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  price,
                  style: TextStyle(
                    color: priceColor,
                    fontWeight: FontWeight.w900,
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
    final auctionTab = ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        if (!isHost && st.queue.any((l) => l.mode == LotMode.auction))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              t(
                'Predlicitiraj predmet koji tek dolazi — tvoja maksimalna ponuda vrijedi kad krene.',
              ),
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
        if (lots.isEmpty)
          Text(
            t('Još nema predmeta na aukciji.'),
            style: const TextStyle(color: _muted),
          ),
        for (final l in lots)
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
              LotStatus.running => t('🔴 Licitira se sada'),
              LotStatus.upcoming when l.leader != null =>
                l.leader!.userId == me
                    ? t('🥇 Tvoja predponuda vodi')
                    : t('Predponuda: {0}', [l.leader!.userLabel]),
              LotStatus.upcoming => null,
              LotStatus.sold => t('✅ Prodano · {0}', [l.leader!.userLabel]),
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
    final shopTab = ListView(
      key: const ValueKey('live-shop'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            isHost
                ? t(
                    'Tvoji predmeti za Kupi odmah — gledatelji ih kupuju tijekom livea.',
                  )
                : t('Kupi bez licitiranja, dok live traje.'),
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ),
        if (shop.isEmpty)
          Text(
            t('Prodavač nema predmeta za Kupi odmah.'),
            style: const TextStyle(color: _muted),
          ),
        for (final (i, d) in shop.indexed)
          row(
            key: ValueKey('live-shop-row-${d.id}'),
            image: thumb(d, i + 1),
            title: d.name,
            price: formatCredits(s.priceForMe(d)),
            priceColor: const Color(0xFF4ADE80),
            note: d.condition.label,
            action: isHost
                ? null
                : FilledButton(
                    key: ValueKey('live-buy-${d.id}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: LoopColors.buyNow,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => confirmAndBuy(context, ref, d),
                    child: Text(t('Kupi')),
                  ),
          ),
      ],
    );

    return DefaultTabController(
      length: 2,
      child: SizedBox(
        height: h * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  UserAvatar(user: host, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('Predmeti u liveu'),
                          style: const TextStyle(
                            color: _white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          host?.handle ?? show.hostLabel,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (!isHost) const WalletChip(dark: true),
                ],
              ),
            ),
            // Bez Kupi odmah: samo predmeti na aukciji (bez kartica).
            if (kBuyNowEnabled)
              TabBar(
                labelColor: _white,
                unselectedLabelColor: _muted,
                indicatorColor: kBidOrange,
                dividerColor: Colors.white12,
                labelStyle: const TextStyle(
                  fontFamily: kFontFamily,
                  fontWeight: FontWeight.w900,
                ),
                tabs: [
                  Tab(
                    key: const ValueKey('live-tab-auction'),
                    text: t('🔨 Na aukciji ({0})', ['${lots.length}']),
                  ),
                  Tab(
                    key: const ValueKey('live-tab-shop'),
                    text: t('🛍️ Kupi odmah ({0})', ['${shop.length}']),
                  ),
                ],
              ),
            Expanded(
              child: kBuyNowEnabled
                  ? TabBarView(children: [auctionTab, shopTab])
                  : auctionTab,
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
                      done ? t('🎉 Dobitnik!') : t('🎁 Izvlačenje…'),
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
    final secs = (widget.left.inMilliseconds / 1000).ceil();
    final f = widget.total.inMilliseconds == 0
        ? 0.0
        : (widget.left.inMilliseconds / widget.total.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    return AnimatedBuilder(
      animation: Listenable.merge([_blink, _bonus]),
      builder: (context, _) {
        final color = widget.hot
            ? Color.lerp(kLiveRed, const Color(0xFFFFB3C1), _blink.value)!
            : kBidOrange;
        final b = _bonus.value;
        return SizedBox(
          height: 22,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              // Glatko smanjivanje između otkucaja.
              TweenAnimationBuilder<double>(
                tween: Tween(end: f),
                duration: const Duration(milliseconds: 400),
                builder: (context, v, _) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    height: 22,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: widget.hot
                          ? [
                              BoxShadow(
                                color: kLiveRed.withValues(
                                  alpha: 0.6 * (1 - _blink.value),
                                ),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(
                        widget.hot ? Icons.bolt : Icons.timer_outlined,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          // Kratko — na uskom ekranu se dugi tekst rezao.
                          widget.hot ? t('Ponuda +2 s!') : t('Preostalo'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      Text(
                        '$secs s',
                        key: const ValueKey('live-secs'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // "+2 s" iskoči iznad trake i odleti gore.
              if (_bonus.isAnimating)
                Positioned(
                  right: 6,
                  top: -18 - 22 * b,
                  child: Opacity(
                    opacity: (1 - b).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale:
                          0.8 +
                          0.6 *
                              Curves.elasticOut.transform(
                                (b * 2).clamp(0.0, 1.0),
                              ),
                      child: Container(
                        key: const ValueKey('live-bonus'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4ADE80),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '+$_added s',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
