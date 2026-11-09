import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import '../config/backend_config.dart';
import '../l10n/tr.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../providers/app_providers.dart';
import '../services/live_backend.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/live_video_view.dart';
import '../widgets/trade_actions.dart';
import 'seller_screens.dart' show ensureSellerInfo;

/// Tamna paleta livea (ista kao [LoopColors] u tamnoj temi). Ne čita
/// [LoopColors] izravno: tok ostaje taman i kad je aplikacija svijetla.
const _bg = Color(0xFF000000);
const _surface = Color(0xFF1C1C1E);
const _hover = Color(0xFF2C2C30);
const _text = Color(0xFFF5F5F7);
const _muted = Color(0xFFAEAEB6);
const _red = Color(0xFFD92D26);
const _danger = Color(0xFFFF453A);
const _line = Color(0xFF3A3A3C);

const _bidChoices = [10, 20, 30, 60];

/// Rezultat čarobnjaka. Soba se otvara u roditelju da ovaj ekran ne uvlači
/// sobu uživo (izbjegava kružni uvoz).
class LiveCreateOutcome {
  const LiveCreateOutcome({
    this.show,
    this.onlineRoom,
    this.scheduled = false,
    this.backend,
  });

  final LiveShow? show;
  final String? onlineRoom;
  final bool scheduled;
  final LiveBackend? backend;
}

typedef LiveCreateFinished =
    void Function(BuildContext context, LiveCreateOutcome outcome);

enum _Sale { auction, buyNow }

/// Predmet u redu ovog livea, prije spremanja.
///
/// Zaliha je ista kao u trgovini, ali model to radi ovako (ne izmišljamo
/// novo):
/// * Kupi odmah ostaje oglas. Prodano skida komad (zadnji odlazi kupcu).
///   Neprodano ostaje u trgovini.
/// * Aukcija predmeta iz trgovine skida oglas dok traje live
///   ([LiveService] `_prepareLot`). Neprodano se ne vraća samo na Kupi
///   odmah (`relistUnsold: false`, kao i dosad).
/// * Uključena trgovina u liveu pokazuje sve oglase domaćina, ne samo
///   odabrane ovdje. Red u čarobnjaku je red aukcija; Kupi odmah nije
///   zaseban lot. Prvi Kupi odmah postaje istaknuti proizvod.
/// * Trajanje po predmetu je [LiveLot.seconds]. Iznenadna smrt je
///   [LiveLot.suddenDeath] (bez +2 s). Oblak (`prepareRoom`) i dalje prima
///   samo aukcijske lotove i jedno trajanje sobe.
class _LineItem {
  _LineItem({
    required this.id,
    required this.name,
    required this.mode,
    required this.price,
    this.deviceId,
    this.photo,
    this.quantity = 1,
    this.from,
  });

  final String id;
  String? deviceId;
  String name;
  String? photo;
  _Sale mode;
  double price;
  int quantity;
  int? seconds;
  bool suddenDeath = false;
  int? from;

  bool get onScreen => from != null;
}

/// Cijeli tok "Novi live": dva koraka, preko cijelog ekrana.
class LiveCreateFlow extends ConsumerStatefulWidget {
  const LiveCreateFlow({super.key, this.deviceId, required this.onFinished});

  final String? deviceId;
  final LiveCreateFinished onFinished;

  @override
  ConsumerState<LiveCreateFlow> createState() => _LiveCreateFlowState();
}

class _LiveCreateFlowState extends ConsumerState<LiveCreateFlow> {
  final _title = TextEditingController();
  final _items = <_LineItem>[];
  int _seq = 0;
  int _step = 0;
  int _secs = 30;
  bool _video = true;
  String? _cover;
  DeviceCategory? _category;
  DateTime? _startsAt;
  String? _error;
  bool _busy = false;
  int? _count;
  final _requestId = const Uuid().v4();

  /// `null` = još se provjerava, `true` = smije, `false` = nema dozvole.
  bool? _camOk = true;
  String? _camError;
  MediaStream? _preview;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    final id = widget.deviceId;
    if (id != null) {
      final device = ref.read(appProvider).deviceById(id);
      if (device != null && !device.isDigital) {
        _items.add(_fromDevice(device));
        _category = device.category;
      }
    }
    if (ref.read(tickIntervalProvider) == null) _camOk = true;
  }

  @override
  void dispose() {
    _title.dispose();
    final stream = _preview;
    _preview = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        unawaited(track.stop());
      }
    }
    super.dispose();
  }

  String _nextId() => 'line-${_seq++}';

  int get _maxLots => ref.read(appProvider).currentUser?.isTrader ?? false
      ? LiveShow.businessMaxLots
      : LiveShow.maxLots;

  bool get _dirty =>
      _title.text.trim().isNotEmpty ||
      _cover != null ||
      _category != null ||
      _startsAt != null ||
      _items.isNotEmpty ||
      _secs != 30 ||
      !_video;

  bool get _titleOk => _title.text.trim().length >= 3;

  String? get _blockReason {
    if (!_titleOk) return t('Upiši naslov (barem 3 znaka).');
    if (_step == 1 && _video && _camOk != true) {
      return _camOk == false
          ? (_camError ?? t('Dopusti kameru da kreneš uživo.'))
          : t('Provjeravam kameru…');
    }
    return null;
  }

  _LineItem _fromDevice(Device device) {
    final listed = device.isListed && device.listPrice != null;
    final price = listed ? device.listPrice! : 1.0;
    return _LineItem(
      id: _nextId(),
      deviceId: device.id,
      name: device.name,
      photo: device.imagePaths.firstOrNull,
      mode: listed ? _Sale.buyNow : _Sale.auction,
      price: price < 1 ? 1 : price,
      quantity: device.quantity < 1 ? 1 : device.quantity,
    );
  }

  Future<void> _stopPreview() async {
    final stream = _preview;
    _preview = null;
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      await track.stop();
    }
  }

  bool _denied(Object error) {
    final msg = '$error'.toLowerCase();
    return msg.contains('notallowed') ||
        msg.contains('permission') ||
        msg.contains('notfound') ||
        msg.contains('notreadable') ||
        msg.contains('security');
  }

  Future<void> _ensureCamera() async {
    if (!_video) {
      await _stopPreview();
      if (mounted) setState(() => _camOk = true);
      return;
    }
    if (ref.read(tickIntervalProvider) == null) {
      if (mounted) setState(() => _camOk = true);
      return;
    }
    if (_probing) return;
    _probing = true;
    if (mounted) {
      setState(() {
        _camOk = null;
        _camError = null;
      });
    }
    try {
      await _stopPreview();
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'facingMode': 'user'},
      });
      if (!mounted || !_video) {
        for (final track in stream.getTracks()) {
          await track.stop();
        }
        return;
      }
      setState(() {
        _preview = stream;
        _camOk = true;
        _camError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _camOk = false;
        _camError = _denied(error)
            ? t('Dopusti kameru da kreneš uživo.')
            : t('Kamera nije dostupna.');
      });
    } finally {
      _probing = false;
    }
  }

  void _goNext() {
    if (!_titleOk) return;
    setState(() {
      _error = null;
      _step = 1;
    });
    unawaited(_ensureCamera());
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: Text(t('Odbaciti live?'), style: const TextStyle(color: _text)),
        content: Text(
          t('Uneseni podaci se neće spremiti.'),
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            key: const ValueKey('live-discard-keep'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Nastavi')),
          ),
          FilledButton(
            key: const ValueKey('live-discard'),
            style: FilledButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Odbaci')),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  void _back() {
    if (_step > 0) {
      setState(() {
        _error = null;
        _step = 0;
      });
      return;
    }
    unawaited(_close());
  }

  Future<void> _pickCover() async {
    try {
      final paths = await ref.read(imageStoreProvider).pick(limit: 1);
      if (paths.isNotEmpty && mounted) setState(() => _cover = paths.first);
    } catch (error) {
      showLoopSnackBar(
        t('Fotografiju nije moguće učitati: {0}', [error]),
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

  void _guardCapacity() {
    if (_items.length >= _maxLots) {
      setState(
        () =>
            _error = t('Live može imati najviše {0} predmeta.', ['$_maxLots']),
      );
    }
  }

  Future<void> _addQuick() async {
    if (_items.length >= _maxLots) {
      _guardCapacity();
      return;
    }
    final item = await showModalBottomSheet<_LineItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (_) => _QuickSheet(id: _nextId()),
    );
    if (item != null && mounted) {
      setState(() {
        _error = null;
        _items.add(item);
      });
    }
  }

  Future<void> _addOnScreen() async {
    if (_items.length >= _maxLots) {
      _guardCapacity();
      return;
    }
    var next = 1;
    for (final item in _items.reversed) {
      if (item.from != null) {
        next = item.from! + 1;
        break;
      }
    }
    final item = await showModalBottomSheet<_LineItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (_) => _OnScreenSheet(id: _nextId(), start: next),
    );
    if (item != null && mounted) {
      setState(() {
        _error = null;
        _items.add(item);
      });
    }
  }

  Future<void> _pickShop() async {
    final state = ref.read(appProvider);
    final taken = {for (final item in _items) ?item.deviceId};
    final devices = state.myDevices
        .where(
          (device) =>
              !device.isDigital &&
              !taken.contains(device.id) &&
              state.activeAuctionFor(device.id) == null,
        )
        .toList();
    final picked = await Navigator.of(context).push<List<Device>>(
      MaterialPageRoute(builder: (_) => _ShopPicker(devices: devices)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _error = null;
      for (final device in picked) {
        if (_items.length >= _maxLots) {
          _error = t('Live može imati najviše {0} predmeta.', ['$_maxLots']);
          break;
        }
        _items.add(_fromDevice(device));
        _category ??= device.category;
      }
    });
  }

  Future<void> _edit(int index) async {
    final item = _items[index];
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (_) => _EditSheet(item: item, showSeconds: _secs),
    );
    if (changed == true && mounted) setState(() => _error = null);
  }

  void _remove(int index) => setState(() => _items.removeAt(index));

  void _move(int from, int to) {
    if (to < 0 || to >= _items.length || to == from) return;
    setState(() {
      final item = _items.removeAt(from);
      _items.insert(to, item);
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
  }

  String _subtitle(_LineItem item) {
    if (item.onScreen) {
      return t('Aukcija · start {0} · #{1}', [
        formatCredits(item.price),
        '${item.from}',
      ]);
    }
    if (item.mode == _Sale.buyNow) {
      return t('Kupi odmah · {0} · {1} kom', [
        formatCredits(item.price),
        '${item.quantity}',
      ]);
    }
    final extra = <String>[
      t('Aukcija · start {0}', [formatCredits(item.price)]),
      if (item.seconds != null && item.seconds != _secs)
        t('{0} s', ['${item.seconds}']),
      if (item.suddenDeath) t('iznenadna'),
    ];
    return extra.join(' · ');
  }

  String _summary() {
    final auctions = _items.where((item) => item.mode == _Sale.auction).length;
    final buyNow = _items.length - auctions;
    final parts = <String>[
      itemsLabel(_items.length),
      if (auctions > 0) _auctions(auctions),
      if (buyNow > 0) '$buyNow ${t('Kupi odmah')}',
      _video ? t('Kamera uključena') : t('Kamera isključena'),
    ];
    return parts.join(' · ');
  }

  String _auctions(int n) {
    if (Tr.lang == AppLang.en) {
      return n == 1 ? '$n auction' : '$n auctions';
    }
    final few = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);
    final singular = n % 10 == 1 && n % 100 != 11;
    final word = singular || !few ? 'aukcija' : 'aukcije';
    return '$n $word';
  }

  Future<void> _countdown() async {
    if (ref.read(tickIntervalProvider) == null) return;
    for (final n in [3, 2, 1]) {
      if (!mounted) return;
      setState(() => _count = n);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    if (mounted) setState(() => _count = null);
  }

  Future<String> _ensureBuyNow(_LineItem item) async {
    final app = ref.read(appProvider.notifier);
    if (item.deviceId == null) {
      final created = await app.addDevice(
        name: item.name,
        model: '',
        condition: DeviceCondition.good,
        price: item.price,
        category:
            _category ?? suggestCategory(item.name) ?? DeviceCategory.other,
        imagePaths: [?item.photo],
        listOnMarket: true,
        quantity: item.quantity,
      );
      return created.id;
    }
    final current = ref.read(appProvider).deviceById(item.deviceId!);
    final changed =
        current == null ||
        !current.isListed ||
        current.listPrice != item.price ||
        current.quantity != item.quantity;
    if (changed) {
      await app.listOnMarket(
        item.deviceId!,
        item.price,
        quantity: item.quantity,
      );
    }
    return item.deviceId!;
  }

  Future<String> _ensureAuctionDevice(_LineItem item) async {
    if (item.deviceId != null) return item.deviceId!;
    final created = await ref
        .read(appProvider.notifier)
        .addDevice(
          name: item.name,
          model: '',
          condition: DeviceCondition.good,
          price: item.price,
          category:
              _category ?? suggestCategory(item.name) ?? DeviceCategory.other,
          imagePaths: [?item.photo],
          listOnMarket: false,
        );
    return created.id;
  }

  Future<void> _submit() async {
    if (_busy || _blockReason != null) return;
    if (blockGuest(context, place: 'new=live')) return;
    if (!await ensureSellerInfo(context) || !mounted) return;
    for (final item in _items) {
      if (item.price < 1) {
        setState(() => _error = t('Upiši početnu cijenu za svaki predmet.'));
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await _stopPreview();
    if (!mounted) return;
    LiveShow? created;
    String? onlineRoom;
    LiveBackend? backendUsed;
    final backend = BackendConfig.cloudLiveEnabled
        ? ref.read(preparedLiveBackendProvider)
        : null;
    final app = ref.read(appProvider.notifier);
    final ok = await runWithLoading(context, () async {
      if (backend != null) {
        final state = ref.read(appProvider);
        final lots = <Map<String, dynamic>>[];
        for (final item in _items) {
          if (item.mode == _Sale.buyNow && !item.onScreen) continue;
          final device = item.deviceId == null
              ? null
              : state.deviceById(item.deviceId!);
          lots.add({
            'title': item.onScreen
                ? '${item.name} #${item.from}'
                : (device == null
                      ? item.name
                      : '${device.name} ${device.model}'.trim()),
            'start_cents': (item.price * 100).round(),
            if (item.deviceId != null) 'source_device_id': item.deviceId,
            'image_url': item.photo ?? device?.imagePaths.firstOrNull,
          });
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
          requestId: _requestId,
        );
        onlineRoom = room['id'] as String;
        backendUsed = backend;
        return;
      }
      final auction = <(String, double)>[];
      final names = <String?>[];
      final secondsEach = <int?>[];
      final suddenEach = <bool>[];
      String? firstBuyNow;
      for (final item in _items) {
        if (item.mode == _Sale.buyNow && !item.onScreen) {
          final id = await _ensureBuyNow(item);
          item.deviceId = id;
          firstBuyNow ??= id;
          continue;
        }
        final id = await _ensureAuctionDevice(item);
        item.deviceId = id;
        auction.add((id, item.price));
        names.add(item.onScreen ? '${item.name} #${item.from}' : null);
        secondsEach.add(item.seconds);
        suddenEach.add(item.suddenDeath);
      }
      final buyNow = firstBuyNow != null;
      created = await app.createLiveShow(
        title: _title.text,
        items: auction,
        names: names,
        secondsEach: secondsEach,
        suddenEach: suddenEach,
        lotSeconds: _secs,
        startsAt: _startsAt,
        video: _video,
        coverPath: _cover,
        category: _category ?? suggestCategory(_title.text),
        relistUnsold: false,
        sells: LiveSells.physical,
        shop: buyNow,
        buyNowOnly: buyNow && auction.isEmpty,
      );
      if (firstBuyNow != null) {
        await app.liveSetFeatured(created!.id, firstBuyNow);
      }
    }, successMessage: null);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    if (_startsAt == null) await _countdown();
    if (!mounted) return;
    widget.onFinished(
      context,
      LiveCreateOutcome(
        show: created,
        onlineRoom: onlineRoom,
        scheduled: _startsAt != null,
        backend: backendUsed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _step == 1;
    final reason = _blockReason;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          foregroundColor: _text,
          leading: IconButton(
            key: const ValueKey('wizard-back'),
            tooltip: t('Natrag'),
            onPressed: _back,
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  t('Novi live'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                t('{0} od {1}', ['${_step + 1}', '2']),
                key: const ValueKey('wizard-count'),
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              key: const ValueKey('wizard-close'),
              tooltip: t('Zatvori'),
              onPressed: () => unawaited(_close()),
              icon: const Icon(Icons.close),
            ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: ColoredBox(
              color: _line,
              child: SizedBox(height: 1, width: double.infinity),
            ),
          ),
        ),
        body: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ReorderableListView.builder(
                  key: ValueKey('wizard-step-$_step'),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  buildDefaultDragHandles: false,
                  header: _step == 0 ? _basics() : _itemsHeader(),
                  footer: _step == 0 ? const SizedBox(height: 8) : _footer(),
                  itemCount: _step == 0 ? 0 : _items.length,
                  onReorderItem: _onReorder,
                  itemBuilder: (context, index) => _row(index),
                ),
              ),
            ),
            if (_count != null)
              Positioned.fill(
                child: ColoredBox(
                  color: _bg,
                  child: Center(
                    child: Text(
                      '$_count',
                      key: const ValueKey('live-countdown'),
                      style: const TextStyle(
                        color: _text,
                        fontSize: 96,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: Material(
          color: _bg,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _line)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (last) ...[
                          Text(
                            _summary(),
                            key: const ValueKey('live-summary'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (reason != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              reason,
                              key: const ValueKey('live-go-reason'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: last
                              ? FilledButton(
                                  key: const ValueKey('live-go'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _red,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: _hover,
                                    disabledForegroundColor: _text,
                                    minimumSize: const Size.fromHeight(52),
                                  ),
                                  onPressed: reason == null && !_busy
                                      ? () => unawaited(_submit())
                                      : null,
                                  child: Text(
                                    _startsAt == null
                                        ? t('Kreni uživo')
                                        : t('Zakaži live'),
                                  ),
                                )
                              : FilledButton(
                                  key: const ValueKey('wizard-next'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _text,
                                    foregroundColor: _bg,
                                    disabledBackgroundColor: _hover,
                                    disabledForegroundColor: _text,
                                    minimumSize: const Size.fromHeight(52),
                                  ),
                                  onPressed: _titleOk ? _goNext : null,
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
        ),
      ),
    );
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      title,
      style: const TextStyle(
        color: _text,
        fontWeight: FontWeight.w800,
        fontSize: 28,
        height: 1.1,
      ),
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _muted,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    ),
  );

  Widget _basics() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(t('Osnovno')),
      TextField(
        key: const ValueKey('live-title'),
        controller: _title,
        maxLength: LiveShow.maxTitle,
        style: const TextStyle(color: _text),
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: t('Naslov showa'),
          hintText: t('npr. Retro igre od 1 €'),
        ),
      ),
      _label(t('Kategorija')),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final section in ItemSection.values)
            if (section != ItemSection.digital)
              for (final category in section.categories)
                ChoiceChip(
                  key: ValueKey('live-cat-${category.name}'),
                  label: Text(category.label),
                  labelPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  showCheckmark: false,
                  selected: _category == category,
                  onSelected: (_) => setState(
                    () => _category = _category == category ? null : category,
                  ),
                ),
        ],
      ),
      _label(t('Naslovna slika')),
      Align(
        alignment: Alignment.centerLeft,
        child: _CoverPicker(
          path: _cover,
          onPick: _pickCover,
          onClear: () => setState(() => _cover = null),
        ),
      ),
      _label(t('Kada kreće show?')),
      _Segments(
        selected: _startsAt == null ? 'now' : 'later',
        segments: [
          (label: t('Sada'), value: 'now', key: const ValueKey('live-now')),
          (
            label: t('Zakaži'),
            value: 'later',
            key: const ValueKey('live-later'),
          ),
        ],
        onChanged: (value) {
          if (value == 'now') {
            setState(() => _startsAt = null);
          } else {
            unawaited(_pickTime());
          }
        },
      ),
      if (_startsAt != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('live-when'),
            onPressed: () => unawaited(_pickTime()),
            child: Text(formatDateTime(_startsAt!)),
          ),
        ),
    ],
  );

  Widget _addButtons() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('live-quick-item'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _text,
              side: const BorderSide(color: _text),
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () => unawaited(_addQuick()),
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              t('Novi predmet'),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('live-from-shop'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _text,
              side: const BorderSide(color: _text),
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () => unawaited(_pickShop()),
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: Text(
              t('Iz moje trgovine'),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _itemsHeader() {
    if (_items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(t('Predmeti u liveu')),
          const Icon(Icons.inventory_2_outlined, color: _text, size: 36),
          const SizedBox(height: 8),
          Text(
            t('Nema predmeta u ovom liveu'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t(
              'Dodaj novi ili odaberi iz trgovine. Jedan live može miješati aukcije i Kupi odmah.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 16),
          _addButtons(),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(t('Predmeti u liveu')),
        _addButtons(),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            t('U ovom liveu ({0})', ['${_items.length}']),
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(int index) {
    final item = _items[index];
    final subtitle = _subtitle(item);
    return Padding(
      key: ValueKey(item.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Semantics(
              container: true,
              label: '${item.name}, $subtitle',
              customSemanticsActions: {
                CustomSemanticsAction(label: t('Gore')): () =>
                    _move(index, index - 1),
                CustomSemanticsAction(label: t('Dolje')): () =>
                    _move(index, index + 1),
              },
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.drag_handle, color: _text),
                    ),
                  ),
                  _Thumb(photo: item.photo, marked: item.onScreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.onScreen
                              ? '${item.name} #${item.from}'
                              : item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    key: ValueKey('live-move-${item.id}'),
                    tooltip: t('Premjesti'),
                    color: _surface,
                    icon: const Icon(Icons.swap_vert, color: _text),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onSelected: (value) =>
                        _move(index, value == 'up' ? index - 1 : index + 1),
                    itemBuilder: (_) => [
                      if (index > 0)
                        PopupMenuItem(value: 'up', child: Text(t('Gore'))),
                      if (index < _items.length - 1)
                        PopupMenuItem(value: 'down', child: Text(t('Dolje'))),
                    ],
                  ),
                  IconButton(
                    key: ValueKey('live-edit-${item.id}'),
                    tooltip: t('Uredi'),
                    onPressed: () => unawaited(_edit(index)),
                    icon: const Icon(Icons.edit_outlined, color: _text),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      fixedSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  IconButton(
                    key: ValueKey('live-remove-${item.id}'),
                    tooltip: t('Ukloni'),
                    onPressed: () => _remove(index),
                    icon: const Icon(Icons.close, color: _text),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      fixedSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _error!,
            style: const TextStyle(color: _danger, fontWeight: FontWeight.w700),
          ),
        ),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('live-more'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          iconColor: _text,
          collapsedIconColor: _text,
          title: Text(
            t('Više postavki'),
            style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
          ),
          children: [
            SwitchListTile(
              key: const ValueKey('live-video'),
              contentPadding: EdgeInsets.zero,
              value: _video,
              onChanged: (value) {
                setState(() => _video = value);
                if (value) {
                  unawaited(_ensureCamera());
                } else {
                  unawaited(_stopPreview());
                  setState(() => _camOk = true);
                }
              },
              title: Text(
                t('Video uživo s kamere'),
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                t(
                  'Gledatelji vide kameru. Bez dozvole ne možeš krenuti uživo.',
                ),
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ),
            if (_video && _preview != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 128,
                      height: 96,
                      child: LiveVideoSurface(stream: _preview!, mirror: true),
                    ),
                  ),
                ),
              ),
            _label(t('Zadano trajanje licitacije')),
            _Segments(
              selected: '$_secs',
              segments: [
                for (final seconds in _bidChoices)
                  (
                    label: t('{0} s', ['$seconds']),
                    value: '$seconds',
                    key: ValueKey('live-secs-$seconds'),
                  ),
              ],
              onChanged: (value) => setState(() => _secs = int.parse(value)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('live-on-screen'),
                onPressed: () => unawaited(_addOnScreen()),
                child: Text(t('Brojevi na ekranu (#150, #151…)')),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Segments extends StatelessWidget {
  const _Segments({
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<({String label, String value, Key key})> segments;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _hover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            for (final segment in segments)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Material(
                    color: selected == segment.value
                        ? _text
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    child: InkWell(
                      key: segment.key,
                      onTap: () => onChanged(segment.value),
                      borderRadius: BorderRadius.circular(9),
                      child: Center(
                        child: Text(
                          segment.label,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: selected == segment.value ? _bg : _text,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.marked});

  final String? photo;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final image = photo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        height: 56,
        child: image != null
            ? LocalPhoto(
                path: image,
                cacheWidth: 168,
                fallback: const ColoredBox(
                  color: _hover,
                  child: Icon(Icons.image_outlined, color: _text),
                ),
              )
            : ColoredBox(
                color: marked ? _bg : _hover,
                child: Icon(
                  marked ? Icons.tag : Icons.image_outlined,
                  color: _text,
                ),
              ),
      ),
    );
  }
}

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
    final image = path;
    return SizedBox(
      width: 96,
      height: 128,
      child: Material(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('live-cover'),
          onTap: onPick,
          child: image == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: _text,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t('Naslovna slika'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _text,
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
                      path: image,
                      cacheWidth: 300,
                      fallback: const SizedBox.shrink(),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        key: const ValueKey('live-cover-clear'),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          minimumSize: const Size(44, 44),
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

class _QuickSheet extends ConsumerStatefulWidget {
  const _QuickSheet({required this.id});
  final String id;

  @override
  ConsumerState<_QuickSheet> createState() => _QuickSheetState();
}

class _QuickSheetState extends ConsumerState<_QuickSheet> {
  final _name = TextEditingController();
  final _price = TextEditingController(text: '1');
  final _qty = TextEditingController(text: '1');
  _Sale _mode = _Sale.auction;
  String? _photo;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final paths = await ref.read(imageStoreProvider).pick(limit: 1);
      if (paths.isNotEmpty && mounted) setState(() => _photo = paths.first);
    } catch (error) {
      showLoopSnackBar(
        t('Fotografiju nije moguće učitati: {0}', [error]),
        error: true,
      );
    }
  }

  void _submit() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    final qty = int.tryParse(_qty.text.trim()) ?? 1;
    if (name.isEmpty || price == null || price < 1) {
      showLoopSnackBar(t('Upiši naziv i cijenu (barem 1 €).'), error: true);
      return;
    }
    if (_mode == _Sale.buyNow && (qty < 1 || qty > Device.maxQuantity)) {
      showLoopSnackBar(
        t('Količina mora biti između 1 i {0}.', ['${Device.maxQuantity}']),
        error: true,
      );
      return;
    }
    Navigator.pop(
      context,
      _LineItem(
        id: widget.id,
        name: name,
        photo: _photo,
        mode: _mode,
        price: price,
        quantity: _mode == _Sale.buyNow ? qty : 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buy = _mode == _Sale.buyNow;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Novi predmet'),
            style: const TextStyle(
              color: _text,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                key: const ValueKey('quick-lot-photo'),
                onTap: _pick,
                child: Container(
                  width: 72,
                  height: 72,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: _hover,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _photo != null
                      ? LocalPhoto(
                          path: _photo!,
                          cacheWidth: 200,
                          fallback: const SizedBox.shrink(),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.add_a_photo_outlined,
                              color: _text,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t('Slika'),
                              style: const TextStyle(
                                color: _text,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('quick-lot-name'),
                  controller: _name,
                  autofocus: true,
                  style: const TextStyle(color: _text),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: t('Naziv')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Segments(
            selected: _mode.name,
            segments: [
              (
                label: t('Aukcija'),
                value: _Sale.auction.name,
                key: const ValueKey('quick-mode-auction'),
              ),
              (
                label: t('Kupi odmah'),
                value: _Sale.buyNow.name,
                key: const ValueKey('quick-mode-buy'),
              ),
            ],
            onChanged: (value) => setState(
              () => _mode = value == _Sale.buyNow.name
                  ? _Sale.buyNow
                  : _Sale.auction,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('quick-lot-price'),
            controller: _price,
            style: const TextStyle(color: _text),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: buy ? t('Cijena') : t('Početna cijena'),
              suffixText: '€',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (buy) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('quick-lot-qty'),
              controller: _qty,
              style: const TextStyle(color: _text),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t('Količina')),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('quick-lot-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: _text,
              foregroundColor: _bg,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _submit,
            child: Text(t('Dodaj u live')),
          ),
        ],
      ),
    );
  }
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.item, required this.showSeconds});

  final _LineItem item;
  final int showSeconds;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _price = TextEditingController(text: _money(widget.item.price));
  late final _qty = TextEditingController(text: '${widget.item.quantity}');
  late _Sale _mode = widget.item.onScreen ? _Sale.auction : widget.item.mode;
  late int _seconds = widget.item.seconds ?? widget.showSeconds;
  late bool _sudden = widget.item.suddenDeath;

  @override
  void dispose() {
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  String _money(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  void _save() {
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    final qty = int.tryParse(_qty.text.trim()) ?? 1;
    if (price == null || price < 1) {
      showLoopSnackBar(t('Upiši naziv i cijenu (barem 1 €).'), error: true);
      return;
    }
    if (_mode == _Sale.buyNow && (qty < 1 || qty > Device.maxQuantity)) {
      showLoopSnackBar(
        t('Količina mora biti između 1 i {0}.', ['${Device.maxQuantity}']),
        error: true,
      );
      return;
    }
    final item = widget.item;
    item.mode = item.onScreen ? _Sale.auction : _mode;
    item.price = price;
    item.quantity = _mode == _Sale.buyNow ? qty : 1;
    item.seconds = _mode == _Sale.auction && _seconds != widget.showSeconds
        ? _seconds
        : null;
    item.suddenDeath = _mode == _Sale.auction && _sudden;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final auction = _mode == _Sale.auction || widget.item.onScreen;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Uredi predmet'),
            style: const TextStyle(
              color: _text,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (!widget.item.onScreen) ...[
            Text(
              t('Način prodaje'),
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            _Segments(
              selected: _mode.name,
              segments: [
                (
                  label: t('Aukcija'),
                  value: _Sale.auction.name,
                  key: const ValueKey('edit-mode-auction'),
                ),
                (
                  label: t('Kupi odmah'),
                  value: _Sale.buyNow.name,
                  key: const ValueKey('edit-mode-buy'),
                ),
              ],
              onChanged: (value) => setState(
                () => _mode = value == _Sale.buyNow.name
                    ? _Sale.buyNow
                    : _Sale.auction,
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const ValueKey('edit-price'),
            controller: _price,
            style: const TextStyle(color: _text),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: auction ? t('Početna cijena') : t('Cijena'),
              suffixText: '€',
            ),
          ),
          if (auction) ...[
            const SizedBox(height: 12),
            Text(
              t('Trajanje'),
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            _Segments(
              selected: '$_seconds',
              segments: [
                for (final seconds in _bidChoices)
                  (
                    label: t('{0} s', ['$seconds']),
                    value: '$seconds',
                    key: ValueKey('edit-secs-$seconds'),
                  ),
              ],
              onChanged: (value) => setState(() => _seconds = int.parse(value)),
            ),
            SwitchListTile(
              key: const ValueKey('edit-sudden'),
              contentPadding: EdgeInsets.zero,
              value: _sudden,
              onChanged: (value) => setState(() => _sudden = value),
              title: Text(
                t('Iznenadna smrt'),
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                t('Ponuda u zadnjim sekundama ne produžuje sat.'),
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('edit-qty'),
              controller: _qty,
              style: const TextStyle(color: _text),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t('Količina')),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('edit-save'),
            style: FilledButton.styleFrom(
              backgroundColor: _text,
              foregroundColor: _bg,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _save,
            child: Text(t('Spremi')),
          ),
        ],
      ),
    );
  }
}

class _OnScreenSheet extends StatefulWidget {
  const _OnScreenSheet({required this.id, required this.start});

  final String id;
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
    _name.dispose();
    _from.dispose();
    _price.dispose();
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
    Navigator.pop(
      context,
      _LineItem(
        id: widget.id,
        name: name,
        mode: _Sale.auction,
        price: price,
        from: from,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final from = int.tryParse(_from.text) ?? widget.start;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Items on screen'),
            style: const TextStyle(
              color: _text,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t(
              'Predmeti s brojevima, bez slike — pokazuješ ih na kameri. Brojevi idu sami: nakon svake prodaje stisneš "Sljedeći #N". Nema ograničenja.',
            ),
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('on-screen-name'),
            controller: _name,
            style: const TextStyle(color: _text),
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
                  style: const TextStyle(color: _text),
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
                  style: const TextStyle(color: _text),
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
            style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('on-screen-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: _text,
              foregroundColor: _bg,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _submit,
            child: Text(t('Dodaj u live')),
          ),
        ],
      ),
    );
  }
}

class _ShopPicker extends StatefulWidget {
  const _ShopPicker({required this.devices});

  final List<Device> devices;

  @override
  State<_ShopPicker> createState() => _ShopPickerState();
}

class _ShopPickerState extends State<_ShopPicker> {
  final _query = TextEditingController();
  final _picked = <String>{};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final shown = [
      for (final device in widget.devices)
        if (q.isEmpty || device.name.toLowerCase().contains(q)) device,
    ];
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _text,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(t('Iz moje trgovine')),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: ColoredBox(
            color: _line,
            child: SizedBox(height: 1, width: double.infinity),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const ValueKey('shop-pick-search'),
              controller: _query,
              style: const TextStyle(color: _text),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: t('Traži predmete'),
                prefixIcon: const Icon(Icons.search, color: _text),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      t('Nema predmeta za dodati.'),
                      style: const TextStyle(color: _muted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    itemCount: shown.length,
                    itemBuilder: (context, index) {
                      final device = shown[index];
                      final on = _picked.contains(device.id);
                      final listed =
                          device.isListed && device.listPrice != null;
                      final subtitle = listed
                          ? t('Kupi odmah · {0} · {1} kom', [
                              formatCredits(device.listPrice!),
                              '${device.quantity}',
                            ])
                          : t('Spremljeno · aukcija od 1 €');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: on ? _hover : _surface,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            key: ValueKey('shop-pick-${device.id}'),
                            onTap: () => setState(() {
                              if (!on) {
                                _picked.add(device.id);
                              } else {
                                _picked.remove(device.id);
                              }
                            }),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 72),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    IgnorePointer(
                                      child: Checkbox(
                                        value: on,
                                        onChanged: (_) {},
                                        fillColor:
                                            WidgetStateProperty.resolveWith(
                                              (states) =>
                                                  states.contains(
                                                    WidgetState.selected,
                                                  )
                                                  ? _red
                                                  : Colors.transparent,
                                            ),
                                        checkColor: Colors.white,
                                        side: const BorderSide(
                                          color: _text,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    _Thumb(
                                      photo: device.imagePaths.firstOrNull,
                                      marked: false,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            device.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _text,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Text(
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _muted,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Material(
        color: _bg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              key: const ValueKey('shop-pick-add'),
              style: FilledButton.styleFrom(
                backgroundColor: _text,
                foregroundColor: _bg,
                disabledBackgroundColor: _hover,
                disabledForegroundColor: _text,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _picked.isEmpty
                  ? null
                  : () {
                      final chosen = [
                        for (final device in widget.devices)
                          if (_picked.contains(device.id)) device,
                      ];
                      Navigator.pop(context, chosen);
                    },
              child: Text(t('Dodaj odabrano ({0})', ['${_picked.length}'])),
            ),
          ),
        ),
      ),
    );
  }
}
