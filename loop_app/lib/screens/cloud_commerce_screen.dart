import 'live_screens.dart';
import '../widgets/item_image.dart';
import '../services/app_location/app_location.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../services/live_backend.dart';
import '../services/commerce_backend.dart';
import '../services/stripe_backend.dart';
import '../widgets/live_media/live_media.dart';
import 'login_screen.dart';

/// Explicit online route. Legacy local orders and bids are never written here.
class CloudCommerceScreen extends StatefulWidget {
  const CloudCommerceScreen({
    super.key,
    this.client,
    this.onRequireLogin,
    this.enableRealtime = true,
    this.onLoadError,
    this.initialTab = 0,
    this.initialRoom,
    this.initialOrder,
    this.liveOnly = false,
    this.embedded = false,
  });
  final SupabaseClient? client;
  final int initialTab;
  final String? initialRoom;
  final String? initialOrder;
  final bool liveOnly;
  final bool embedded;
  final Future<void> Function()? onRequireLogin;
  final bool enableRealtime;
  final void Function(Object)? onLoadError;
  @override
  State<CloudCommerceScreen> createState() => _CloudCommerceState();
}

class _CloudCommerceState extends State<CloudCommerceScreen> {
  SupabaseClient get db => widget.client ?? Supabase.instance.client;
  LiveBackend get live => LiveBackend(db);
  CommerceBackend get commerce => CommerceBackend(db);
  String? get uid => db.auth.currentUser?.id;
  String? roomId;
  int tab = 0;
  bool busy = false, loading = true, failed = false;
  bool refreshing = false;
  List<Map<String, dynamic>> rooms = [],
      messages = [],
      lots = [],
      products = [],
      orders = [];
  Map<String, dynamic>? connection;
  Timer? timer;
  StreamSubscription<AuthState>? auth;
  RealtimeChannel? channel;
  final input = TextEditingController();
  @override
  void initState() {
    super.initState();
    tab = widget.initialTab >= 0 && widget.initialTab <= 2
        ? widget.initialTab
        : 0;
    auth = db.auth.onAuthStateChange.listen((_) {
      connection = null;
      cardKnown = false;
      cardLast4 = null;
      unawaited(_loadCard());
      _refresh();
      if (roomId != null) _video();
    });
    unawaited(_loadCard());
    roomId = widget.initialRoom;
    if (roomId != null) {
      if (widget.enableRealtime) channel = live.watch(roomId!, _refresh);
      unawaited(_video());
    }
    _refresh();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    auth?.cancel();
    input.dispose();
    final c = channel;
    if (c != null) db.removeChannel(c);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (refreshing || !mounted) return;
    refreshing = true;
    final selectedRoom = roomId;
    try {
      final rs = await db
          .from('live_rooms')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      List<Map<String, dynamic>> ms = [], ls = [], ps = [], os = [];
      if (selectedRoom != null) {
        ms = await live.messages(selectedRoom);
        ls = await db
            .from('live_lots')
            .select()
            .eq('room_id', selectedRoom)
            .order('position')
            .order('id');
      } else if (tab == 1) {
        ps = await db
            .from('commerce_products')
            .select()
            .eq('active', true)
            .order('created_at', ascending: false)
            .limit(50);
      } else if (tab == 2 && uid != null) {
        os = await commerce.orders(id: widget.initialOrder);
      }
      if (!mounted || selectedRoom != roomId) return;
      setState(() {
        rooms = rs;
        messages = ms;
        lots = ls;
        products = ps;
        orders = os;
        failed = false;
        loading = false;
      });
    } catch (error) {
      widget.onLoadError?.call(error);
      if (mounted) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    } finally {
      refreshing = false;
    }
  }

  Future<bool> _login() async {
    if (uid != null) return true;
    if (widget.onRequireLogin != null) {
      await widget.onRequireLogin!();
    } else {
      AppLocation.rememberForLogin(
        roomId != null
            ? 'cloud=live&room=${Uri.encodeQueryComponent(roomId!)}'
            : 'cloud=${tab == 2
                  ? 'orders'
                  : tab == 1
                  ? 'catalog'
                  : 'live'}',
      );
      await LoginScreen.open(context);
    }
    if (mounted) await _refresh();
    return mounted && uid != null;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(paymentActionErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _ask(String title, {String hint = ''}) async {
    final field = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text.trim()),
            child: const Text('Potvrdi'),
          ),
        ],
      ),
    );
    // Keep the controller alive through dialog dismissal animation.
    Future<void>.delayed(const Duration(seconds: 1), field.dispose);
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _open(String id) async {
    final old = channel;
    if (old != null) await db.removeChannel(old);
    if (!mounted) return;
    setState(() {
      roomId = id;
      connection = null;
      messages = [];
      lots = [];
    });
    if (widget.enableRealtime) channel = live.watch(id, _refresh);
    await _refresh();
    await _video();
  }

  Future<void> _video() async {
    final selected = roomId;
    if (selected == null) return;
    if (rooms.where((r) => r['id'] == selected).firstOrNull?['video_enabled'] ==
        false) {
      return;
    }
    try {
      final value = await live.videoToken(selected);
      if (mounted && selected == roomId) setState(() => connection = value);
    } catch (_) {
      /* Room may be scheduled or the host has not connected. */
    }
  }

  Future<void> _leave() async {
    final old = channel;
    channel = null;
    if (old != null) await db.removeChannel(old);
    if (mounted && widget.liveOnly && widget.initialRoom != null) {
      Navigator.of(context).pop();
      return;
    }
    if (mounted) {
      setState(() {
        roomId = null;
        connection = null;
      });
    }
    await _refresh();
  }

  String money(dynamic cents) =>
      '${((cents as num? ?? 0) / 100).toStringAsFixed(2)} €';
  Future<void> _createRoom() async {
    if (!await _login()) return;
    if (!mounted) return;
    await CreateLiveShowScreen.open(context);
  }

  Future<void> _publish() async {
    if (!await _login()) return;
    final title = await _ask('Naziv predmeta');
    if (title == null) return;
    final amount = await _ask('Cijena u eurima', hint: '19,90');
    if (amount == null) return;
    final n = double.tryParse(amount.replaceAll(',', '.'));
    if (n == null || !n.isFinite || n <= 0) return;
    await commerce.publish(title, (n * 100).round(), 1);
  }

  Widget _card(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );
  @override
  Widget build(BuildContext context) {
    final room = rooms.where((r) => r['id'] == roomId).firstOrNull;
    final host = uid != null && room?['host_id'] == uid;
    final inRoom = roomId != null;
    return Scaffold(
      backgroundColor: inRoom ? _ink : null,
      appBar: widget.embedded || inRoom
          ? null
          : AppBar(
              // Soba je tamna (kao video): traka se stapa s njom.
              backgroundColor: inRoom ? _ink : null,
              foregroundColor: inRoom ? Colors.white : null,
              surfaceTintColor: Colors.transparent,
              title: Text(
                room?['title'] as String? ??
                    (tab == 2
                        ? 'Narudžbe'
                        : widget.liveOnly
                        ? 'Uživo'
                        : 'Online trgovina'),
              ),
              leading: roomId == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _leave,
                    ),
              actions: [
                if (uid == null)
                  TextButton(
                    style: inRoom
                        ? TextButton.styleFrom(foregroundColor: Colors.white)
                        : null,
                    onPressed: _login,
                    child: const Text('Prijava'),
                  ),
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (failed)
            MaterialBanner(
              content: const Text('Online trgovina trenutačno nije dostupna.'),
              actions: [
                TextButton(
                  onPressed: _refresh,
                  child: const Text('Pokušaj ponovno'),
                ),
              ],
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : roomId != null
                ? _room(room, host)
                : _lobby(),
          ),
        ],
      ),
      bottomNavigationBar: roomId != null || widget.liveOnly
          ? null
          : NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 54,
                backgroundColor: const Color(0xFF0B0C11),
                indicatorColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                iconTheme: WidgetStateProperty.resolveWith(
                  (states) => IconThemeData(
                    size: 20,
                    color: states.contains(WidgetState.selected)
                        ? Colors.white
                        : Colors.white54,
                  ),
                ),
                labelTextStyle: WidgetStateProperty.resolveWith(
                  (states) => TextStyle(
                    fontSize: 10,
                    fontWeight: states.contains(WidgetState.selected)
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: states.contains(WidgetState.selected)
                        ? Colors.white
                        : Colors.white54,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (v) {
                  setState(() => tab = v);
                  _refresh();
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.live_tv),
                    label: 'Uživo',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.storefront),
                    label: 'Katalog',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long),
                    label: 'Narudžbe',
                  ),
                ],
              ),
            ),
    );
  }

  Widget _lobby() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      if (tab == 0) ...[
        FilledButton.icon(
          onPressed: busy ? null : () => _run(_createRoom),
          icon: const Icon(Icons.videocam),
          label: const Text('Pokreni svoj live'),
        ),
        if (rooms.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Trenutno nema liveova.'),
          ),
        for (final r in rooms)
          if (r['status'] != 'ended')
            _card(
              ListTile(
                leading: r['cover_url'] == null
                    ? const Icon(Icons.live_tv)
                    : SizedBox(
                        width: 64,
                        height: 64,
                        child: LocalPhoto(
                          path: r['cover_url'] as String,
                          fit: BoxFit.cover,
                          fallback: const Icon(Icons.live_tv),
                        ),
                      ),
                title: Text(r['title'] as String),
                subtitle: Text(r['status'] == 'live' ? 'Uživo' : 'Uskoro'),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: () {
                  if (widget.embedded) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: AppPlace(
                          'cloud=live&room=${r['id']}',
                        ).settings,
                        builder: (_) => CloudCommerceScreen(
                          initialRoom: r['id'] as String,
                          liveOnly: true,
                        ),
                      ),
                    );
                  } else {
                    _open(r['id'] as String);
                  }
                },
              ),
            ),
      ],
      if (tab == 1) ...[
        FilledButton.icon(
          onPressed: busy ? null : () => _run(_publish),
          icon: const Icon(Icons.add),
          label: const Text('Dodaj predmet'),
        ),
        for (final p in products)
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p['title'] as String,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(money(p['price_cents'])),
                if (p['seller_id'] != uid)
                  FilledButton(
                    onPressed: busy || p['stock'] == 0
                        ? null
                        : () => _run(() async {
                            if (!await _login()) return;
                            await commerce.reserve(
                              p['id'] as String,
                              1,
                              const Uuid().v4(),
                            );
                            if (mounted) setState(() => tab = 2);
                          }),
                    child: Text(p['stock'] == 0 ? 'Prodano' : 'Kupi'),
                  ),
              ],
            ),
          ),
      ],
      if (tab == 2) ...[
        if (uid == null)
          FilledButton(
            onPressed: _login,
            child: const Text('Prijavi se za narudžbe'),
          ),
        if (uid != null)
          OutlinedButton(
            onPressed: busy
                ? null
                : () => _run(() => StripeBackend(db).connectSeller()),
            child: const Text('Postavi Stripe račun prodavatelja (test)'),
          ),
        for (final o in orders) _order(o),
      ],
    ],
  );
  Widget _order(Map<String, dynamic> o) {
    final buyer = o['buyer_id'] == uid;
    final id = o['id'] as String;
    final state = o['status'];
    const labels = {
      'awaiting_payment': 'Čeka plaćanje',
      'paid': 'Plaćeno',
      'shipped': 'Poslano',
      'delivered': 'Dostavljeno',
      'cancelled': 'Otkazano',
      'refunded': 'Vraćeno',
    };
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${buyer ? 'Kupnja' : 'Prodaja'} · ${money(o['total_cents'])}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(labels[state] ?? '$state'),
          Text('Narudžba ${id.substring(0, 8)}'),
          if (buyer && (state == 'awaiting_payment' || state == 'paid'))
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => _run(() async {
                      final locker = await _ask(
                        'BOX NOW paketomat',
                        hint: 'ID paketomata',
                      );
                      if (locker == null) return;
                      await commerce.chooseShipping(id, 'boxnow', {
                        'locker_id': locker,
                      });
                      // Whatnot: spremljena kartica se naplaćuje sama.
                      if (state == 'awaiting_payment') await _autoCharge(id);
                    }),
              child: const Text('Odaberi paketomat'),
            ),
          if (buyer && state == 'awaiting_payment' && cardLast4 != null)
            FilledButton.icon(
              onPressed: busy ? null : () => _run(() => _autoCharge(id)),
              icon: const Icon(Icons.credit_card),
              label: Text('Plati karticom •••• $cardLast4'),
            ),
          if (buyer && state == 'awaiting_payment')
            FilledButton(
              onPressed: busy
                  ? null
                  : () => _run(() => StripeBackend(db).checkout(id)),
              child: Text(
                cardLast4 == null
                    ? 'Plati preko Stripea (test)'
                    : 'Plati drugom karticom (Stripe)',
              ),
            ),
          if (!buyer && state == 'paid')
            FilledButton(
              onPressed: busy
                  ? null
                  : () => _run(() async {
                      final tracking = await _ask('Broj za praćenje');
                      if (tracking == null) return;
                      await commerce.ship(id, 'BOX NOW', tracking);
                    }),
              child: const Text('Označi poslano'),
            ),
          if (buyer && state == 'shipped')
            FilledButton(
              onPressed: busy
                  ? null
                  : () => _run(() => commerce.confirmDelivery(id)),
              child: const Text('Potvrdi primitak'),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- live soba

  static const _ink = Color(0xFF0B0C11);
  static const _panel = Color(0xFF16171D);
  static const _liveRed = Color(0xFFE5173F);

  /// Osvojeni predmet: narudžba i odabir dostave.
  Future<void> _claim(Map<String, dynamic> lot) => _run(() async {
    await commerce.claimAward(lot['id'] as String, const Uuid().v4());
    if (widget.liveOnly && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          settings: AppPlace.of('cloud', 'orders').settings,
          builder: (_) =>
              const CloudCommerceScreen(initialTab: 2, liveOnly: true),
        ),
      );
      return;
    }
    await _leave();
    if (mounted) setState(() => tab = 2);
    await _refresh();
  });

  /// Spremljena kartica (zadnje 4 znamenke) ili `null` dok nije dodana.
  String? cardLast4;
  bool cardKnown = false;

  Future<void> _loadCard() async {
    if (uid == null) return;
    try {
      final c = await StripeBackend(db).cardStatus();
      if (mounted) {
        setState(() {
          cardLast4 = c.hasCard ? (c.last4 ?? '••••') : null;
          cardKnown = true;
        });
      }
    } catch (_) {
      /* Stripe nije postavljen: licitiranje ostaje moguće. */
    }
  }

  /// Kao na Whatnotu: prije prve ponude treba spremljena kartica (naplata
  /// pobjednika je automatska). Ako Stripe nije dostupan, ne blokira.
  Future<bool> _ensureCard() async {
    if (!cardKnown) await _loadCard();
    if (!cardKnown || cardLast4 != null) return true;
    if (!mounted) return false;
    final add = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dodaj karticu za licitiranje'),
        content: const Text(
          'Karticu spremaš jednom. Kad pobijediš, naplata ide automatski, '
          'bez novog upisa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Kasnije'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dodaj karticu'),
          ),
        ],
      ),
    );
    if (add == true) await StripeBackend(db).addCard();
    return false;
  }

  /// Nakon odabira dostave: naplati spremljenu karticu bez checkouta.
  Future<void> _autoCharge(String orderId) async {
    if (cardLast4 == null) return;
    final paid = await StripeBackend(db).charge(orderId);
    if (paid && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plaćeno karticom •••• $cardLast4')),
      );
    }
  }

  Future<void> _customBid(Map<String, dynamic> lot) async {
    if (!await _login()) return;
    final next = lot['price_cents'] == null
        ? lot['start_cents'] as int
        : (lot['price_cents'] as int) + (lot['increment_cents'] as int);
    final raw = await _ask(
      'Ponudi vlastiti iznos',
      hint: 'Najmanje ${money(next)}',
    );
    if (raw == null) return;
    final amount = double.tryParse(raw.replaceAll(',', '.'));
    if (amount == null || !amount.isFinite || (amount * 100).round() < next) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Najmanja ponuda je ${money(next)}.')),
        );
      }
      return;
    }
    await _run(() async {
      if (!await _ensureCard()) return;
      await live.bid(
        lot['id'] as String,
        (amount * 100).round(),
        const Uuid().v4(),
      );
    });
  }

  Future<void> _bid(Map<String, dynamic> lot) => _run(() async {
    if (!await _login()) return;
    if (!await _ensureCard()) return;
    final price = lot['price_cents'] as int?;
    await live.bid(
      lot['id'] as String,
      price == null
          ? lot['start_cents'] as int
          : price + (lot['increment_cents'] as int),
      const Uuid().v4(),
    );
  });

  Future<void> _addLot() => _run(() async {
    final name = await _ask('Naziv aukcijskog predmeta');
    if (name != null) await live.addLot(roomId!, name, 100, 100);
  });

  Future<void> _confirmEnd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Završiti live?'),
        content: const Text('Gledatelji više neće moći licitirati.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Završi live'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => live.setStatus(roomId!, 'ended'));
  }

  /// Svi predmeti livea (redoslijed, status, pokretanje za voditelja).
  void _showLots(
    Map<String, dynamic>? room,
    bool host,
  ) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: _panel,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            'Predmeti',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (lots.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Još nema predmeta.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          for (final lot in lots)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                lot['title'] as String,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                '${money(lot['price_cents'] ?? lot['start_cents'])} · '
                '${const {'queued': 'na redu', 'running': 'licitira se', 'sold': 'prodano', 'unsold': 'neprodano'}[lot['status']] ?? lot['status']}',
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: host && lot['status'] == 'queued'
                  ? FilledButton(
                      onPressed: busy
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _run(
                                () => live.startLot(
                                  lot['id'] as String,
                                  room?['lot_seconds'] as int? ?? 30,
                                ),
                              );
                            },
                      child: const Text('Pokreni'),
                    )
                  : null,
            ),
        ],
      ),
    ),
  );

  /// Moderacija poruke (samo voditelj).
  void _moderate(Map<String, dynamic> m) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: _panel,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label, icon) in const [
            ('delete', 'Ukloni poruku', Icons.delete_outline),
            ('mute', 'Utišaj korisnika', Icons.volume_off_outlined),
            ('ban', 'Zabrani pristup', Icons.block),
          ])
            ListTile(
              leading: Icon(icon, color: Colors.white),
              title: Text(label, style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _run(() async {
                  if (v == 'delete') {
                    await live.deleteMessage(m['id'] as int);
                  } else {
                    await live.moderate(
                      roomId!,
                      m['sender_id'] as String,
                      muted: v == 'mute',
                      banned: v == 'ban',
                    );
                  }
                });
              },
            ),
        ],
      ),
    ),
  );

  Widget _stagePlaceholder(Map<String, dynamic>? room, bool host) {
    final scheduled = room?['status'] == 'scheduled';
    return Container(
      color: _ink,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            host ? Icons.videocam_outlined : Icons.live_tv_outlined,
            color: Colors.white38,
            size: 56,
          ),
          const SizedBox(height: 12),
          Text(
            host
                ? 'Pokreni kameru za emitiranje.'
                : scheduled
                ? 'Live još nije počeo.'
                : 'Čekamo prijenos voditelja…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 16),
          if (host)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _liveRed,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 50),
              ),
              onPressed: _video,
              icon: const Icon(Icons.videocam),
              label: const Text('Uključi kameru i mikrofon'),
            )
          else
            TextButton(
              onPressed: _video,
              child: const Text('Uključi prijenos'),
            ),
        ],
      ),
    );
  }

  Widget _chatOverlay(Map<String, dynamic>? room, bool host) {
    final hostId = room?['host_id'];
    final recent = messages.take(30).toList(); // najnovije prve
    return LayoutBuilder(
      builder: (_, c) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 320,
          maxHeight: c.maxHeight * 0.6,
        ),
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white],
            stops: [0, 0.25],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            reverse: true,
            shrinkWrap: true,
            padding: const EdgeInsets.only(top: 40),
            itemCount: recent.length,
            itemBuilder: (_, i) {
              final m = recent[i];
              final mine = m['sender_id'] == uid;
              final isHost = m['sender_id'] == hostId;
              final removed = m['deleted'] == true;
              final name = mine
                  ? 'Ti'
                  : isHost
                  ? 'Voditelj'
                  : 'Korisnik ${(m['sender_id'] as String).substring(0, 6)}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GestureDetector(
                  onLongPress: host && !mine ? () => _moderate(m) : null,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: isHost ? _liveRed : Colors.white24,
                          child: Text(
                            name.characters.first,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  color: isHost
                                      ? const Color(0xFFFFB3C1)
                                      : Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                removed
                                    ? 'Poruka je uklonjena'
                                    : m['body'] as String,
                                style: TextStyle(
                                  color: removed
                                      ? Colors.white38
                                      : Colors.white,
                                  fontSize: 14,
                                  fontStyle: removed
                                      ? FontStyle.italic
                                      : FontStyle.normal,
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
            },
          ),
        ),
      ),
    );
  }

  /// Kartica trenutnog predmeta + glavna radnja (licitiraj / pokreni).
  Widget _lotPanel(Map<String, dynamic>? room, bool host) {
    final running = lots.where((l) => l['status'] == 'running').firstOrNull;
    final queued = lots.where((l) => l['status'] == 'queued').toList();
    final won = lots
        .where((l) => l['status'] == 'sold' && l['winner_id'] == uid)
        .firstOrNull;
    final scheduled = room?['status'] == 'scheduled';
    final ended = room?['status'] == 'ended';
    final lot = running ?? queued.firstOrNull;
    final children = <Widget>[];

    if (lot != null) {
      children.add(
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    running != null ? 'Sada na aukciji' : 'Sljedeći predmet',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    lot['title'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(lot['price_cents'] ?? lot['start_cents']),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (running != null)
                  _LotTimer(
                    endsAt: DateTime.tryParse(
                      running['ends_at'] as String? ?? '',
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
      children.add(const SizedBox(height: 10));
    }

    final primary = <Widget>[];
    if (won != null) {
      primary.add(
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: busy ? null : () => _claim(won),
          icon: const Icon(Icons.local_shipping_outlined),
          label: const Text('Osvojeno · odaberi dostavu'),
        ),
      );
    } else if (host) {
      if (scheduled) {
        primary.add(
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _liveRed,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: busy
                ? null
                : () => _run(() async {
                    await live.setStatus(roomId!, 'live');
                    await _video();
                  }),
            icon: const Icon(Icons.podcasts),
            label: const Text('Započni live'),
          ),
        );
      } else if (!ended) {
        final next = running == null ? queued.firstOrNull : null;
        primary.add(
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _liveRed,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white12,
              disabledForegroundColor: Colors.white54,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: busy
                ? null
                : running != null
                ? null
                : next != null
                ? () => _run(
                    () => live.startLot(
                      next['id'] as String,
                      room?['lot_seconds'] as int? ?? 30,
                    ),
                  )
                : _addLot,
            icon: Icon(
              running != null
                  ? Icons.hourglass_top
                  : next != null
                  ? Icons.play_arrow
                  : Icons.add,
            ),
            label: Text(
              running != null
                  ? 'Licitacija traje…'
                  : next != null
                  ? 'Pokreni ${room?['lot_seconds'] ?? 30} s'
                  : 'Dodaj predmet',
            ),
          ),
        );
      }
    } else if (running != null) {
      final price = running['price_cents'] as int?;
      final nextBid = price == null
          ? running['start_cents'] as int
          : price + (running['increment_cents'] as int);
      primary.add(
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFFDF4D),
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          onPressed: busy ? null : () => _bid(running),
          child: Text(
            uid == null
                ? 'Prijavi se za licitiranje'
                : 'Licitiraj ${money(nextBid)}',
          ),
        ),
      );
    }
    children.addAll(primary);

    // Sporedne radnje: voditelj (dodaj, popis, završi) i provjera rezultata.
    final secondary = <Widget>[];
    if (host && !ended) {
      secondary
        ..add(_smallAction(Icons.add, 'Dodaj predmet', busy ? null : _addLot))
        ..add(
          _smallAction(
            Icons.list_alt,
            'Predmeti (${lots.length})',
            () => _showLots(room, host),
          ),
        )
        ..add(
          _smallAction(
            Icons.stop_circle_outlined,
            'Završi live',
            busy ? null : _confirmEnd,
            color: const Color(0xFFFF8FA3),
          ),
        );
    } else if (!host) {
      if (running != null) {
        secondary.add(
          _smallAction(
            Icons.edit_outlined,
            'Iznos',
            busy ? null : () => _customBid(running),
          ),
        );
      }
      secondary.add(
        _smallAction(
          Icons.list_alt,
          'Predmeti (${lots.length})',
          () => _showLots(room, host),
        ),
      );
    }
    if (uid != null && running != null) {
      secondary.add(
        _smallAction(
          Icons.refresh,
          'Provjeri rezultat',
          busy
              ? null
              : () => _run(() => live.finishLot(running['id'] as String)),
        ),
      );
    }
    if (secondary.isNotEmpty) {
      children
        ..add(const SizedBox(height: 6))
        ..add(
          Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 4,
            children: secondary,
          ),
        );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: const BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _smallAction(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    Color color = Colors.white70,
  }) => TextButton.icon(
    style: TextButton.styleFrom(
      foregroundColor: color,
      disabledForegroundColor: Colors.white24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );

  Widget _room(Map<String, dynamic>? room, bool host) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ColoredBox(
      color: _ink,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (room?['video_enabled'] != false && connection != null)
            CloudLiveMedia(
              key: ValueKey('$roomId:$uid'),
              connection: connection!,
            )
          else
            _stagePlaceholder(room, host),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xAA000000),
                    Colors.transparent,
                    Color(0xEE000000),
                  ],
                  stops: [0, .4, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 17,
                        backgroundColor: Color(0xFFFFDF4D),
                        child: Icon(
                          Icons.storefront,
                          color: Colors.black,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room?['title'] as String? ?? 'Prijenos uživo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              switch (room?['status']) {
                                'live' => '● UŽIVO',
                                'scheduled' => 'ZAKAZANO',
                                _ => 'ZAVRŠENO',
                              },
                              style: const TextStyle(
                                color: Color(0xFFFFDF4D),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (uid == null)
                        TextButton(
                          onPressed: _login,
                          child: const Text('Prijava'),
                        ),
                      IconButton(
                        tooltip: 'Osvježi live',
                        onPressed: _refresh,
                        icon: const Icon(
                          Icons.refresh,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Zatvori live',
                        onPressed: _leave,
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Predmeti u liveu',
                    onPressed: () => _showLots(room, host),
                    icon: Badge(
                      label: Text('${lots.length}'),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: _chatOverlay(room, host),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: input,
                          readOnly: uid == null,
                          onTap: uid == null ? _login : null,
                          maxLength: 500,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendChat(),
                          decoration: InputDecoration(
                            hintText: uid == null
                                ? 'Prijavi se za komentar'
                                : 'Napiši komentar',
                            hintStyle: const TextStyle(color: Colors.white60),
                            counterText: '',
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0x33000000),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                color: Colors.white30,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                color: Color(0xFFFFDF4D),
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Pošalji komentar',
                        onPressed: busy ? null : _sendChat,
                        icon: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      if (keyboard)
                        IconButton(
                          tooltip: 'Zatvori tipkovnicu',
                          onPressed: () => FocusScope.of(context).unfocus(),
                          icon: const Icon(
                            Icons.keyboard_hide_outlined,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!keyboard) _lotPanel(room, host),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendChat() => _run(() async {
    if (!await _login()) return;
    final text = input.text.trim();
    if (text.isEmpty) return;
    await live.sendMessage(roomId!, text, const Uuid().v4());
    input.clear();
  });
}

/// Odbrojavanje do kraja licitacije (osvježava se svake sekunde).
class _LotTimer extends StatefulWidget {
  const _LotTimer({required this.endsAt});
  final DateTime? endsAt;

  @override
  State<_LotTimer> createState() => _LotTimerState();
}

class _LotTimerState extends State<_LotTimer> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = widget.endsAt?.toLocal();
    if (end == null) return const SizedBox.shrink();
    final left = end.difference(DateTime.now());
    final secs = left.isNegative ? 0 : left.inSeconds;
    final hot = secs <= 5;
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: hot ? const Color(0xFFE5173F) : Colors.white12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        secs >= 60
            ? '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}'
            : '$secs s',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
