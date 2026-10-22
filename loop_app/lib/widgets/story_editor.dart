import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import '../models/story.dart';
import '../providers/app_providers.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'item_image.dart';
import 'story_canvas.dart';
import 'trade_actions.dart';

/// Urednik priče (kao na Instagramu): tekstovi koji se povlače po pozadini,
/// povećavaju i rotiraju (dva prsta), fontovi, boje, poravnanje, pozadina
/// teksta, boja/fotografija pozadine i oglas.
class CreateStoryScreen extends ConsumerStatefulWidget {
  const CreateStoryScreen({super.key});

  static Future<void> open(BuildContext context) {
    if (blockGuest(context)) return Future.value();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const CreateStoryScreen(),
      ),
    );
  }

  @override
  ConsumerState<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends ConsumerState<CreateStoryScreen> {
  final _canvasKey = GlobalKey();
  final List<StoryText> _layers = [];
  int _background = 0;
  String? _photo;
  String? _deviceId;
  bool _busy = false;

  // Povlačenje teksta.
  int? _dragging;
  Offset? _lastFocal;
  double _startSize = StoryText.defaultSize;
  double _startRotation = 0;
  Offset _raw = Offset.zero;
  bool _guideX = false;
  bool _guideY = false;
  bool _overTrash = false;

  // Uređivanje teksta: null = ne uređuje se, -1 = novi tekst.
  int? _editing;
  final _text = TextEditingController();
  final _focus = FocusNode();
  StoryText _draft = const StoryText(text: '');

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      _layers.isNotEmpty || _photo != null || _deviceId != null;

  Size get _canvasSize =>
      (_canvasKey.currentContext?.findRenderObject() as RenderBox?)?.size ??
      const Size(360, 640);

  // ── Uređivanje teksta ───────────────────────────────────────────────

  void _startEditing([int? index]) {
    if (index == null && _layers.length >= Story.maxTexts) {
      showLoopSnackBar(
        t('Priča može imati najviše {0} tekstova.', ['${Story.maxTexts}']),
        error: true,
      );
      return;
    }
    setState(() {
      _editing = index ?? -1;
      _draft = index == null
          ? StoryText(
              text: '',
              // Novi tekst nasljeđuje izgled zadnjeg (brže uređivanje).
              font: _layers.lastOrNull?.font ?? StoryFont.classic,
              color: _layers.lastOrNull?.color ?? 0xFFFFFFFF,
              y: 0.4,
            )
          : _layers[index];
      _text.text = _draft.text;
    });
    _focus.requestFocus();
  }

  void _finishEditing() {
    final i = _editing;
    if (i == null) return;
    final text = _text.text.trim();
    setState(() {
      final layer = _draft.copyWith(text: text);
      if (i == -1) {
        if (text.isNotEmpty) _layers.add(layer);
      } else if (text.isEmpty) {
        _layers.removeAt(i);
      } else {
        _layers[i] = layer;
      }
      _editing = null;
    });
    _focus.unfocus();
  }

  /// Mijenja izgled teksta koji se uređuje (uvijek od trenutnog stanja).
  void _setDraft(StoryText Function(StoryText d) change) =>
      setState(() => _draft = change(_draft));

  // ── Povlačenje, povećavanje, rotacija ───────────────────────────────

  void _onScaleStart(int i, ScaleStartDetails e) {
    final l = _layers[i];
    setState(() {
      _dragging = i;
      _lastFocal = e.focalPoint;
      _startSize = l.size;
      _startRotation = l.rotation;
      _raw = Offset(l.x, l.y);
    });
  }

  void _onScaleUpdate(int i, ScaleUpdateDetails e) {
    final size = _canvasSize;
    final delta = e.focalPoint - (_lastFocal ?? e.focalPoint);
    _lastFocal = e.focalPoint;
    _raw += Offset(delta.dx / size.width, delta.dy / size.height);
    // Privlačenje na sredinu (vodilice).
    final snapX = (_raw.dx - 0.5).abs() < 0.02;
    final snapY = (_raw.dy - 0.5).abs() < 0.015;
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(e.focalPoint);
    final overTrash =
        local != null &&
        (local - Offset(size.width / 2, size.height - 56)).distance < 48;
    setState(() {
      _guideX = snapX;
      _guideY = snapY;
      _overTrash = overTrash;
      _layers[i] = _layers[i].copyWith(
        x: snapX ? 0.5 : _raw.dx.clamp(0.0, 1.0),
        y: snapY ? 0.5 : _raw.dy.clamp(0.0, 1.0),
        size: e.pointerCount > 1
            ? (_startSize * e.scale).clamp(StoryText.minSize, StoryText.maxSize)
            : null,
        rotation: e.pointerCount > 1 ? _startRotation + e.rotation : null,
      );
    });
  }

  void _onScaleEnd(int i) {
    setState(() {
      if (_overTrash) _layers.removeAt(i);
      _dragging = null;
      _guideX = _guideY = _overTrash = false;
    });
  }

  // ── Pozadina, fotografija, oglas ────────────────────────────────────

  Future<void> _photoMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: LoopColors.background,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t('Odaberi iz galerije')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t('Uslikaj')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (_photo != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: LoopColors.error),
                title: Text(t('Ukloni sliku')),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      setState(() => _photo = null);
      return;
    }
    try {
      final p = await ref
          .read(appProvider.notifier)
          .pickStoryPhoto(camera: choice == 'camera');
      if (p != null && mounted) setState(() => _photo = p);
    } catch (e) {
      showLoopSnackBar(t('Slika nije spremljena: {0}', [e]), error: true);
    }
  }

  Future<void> _pickListing() async {
    final listings = ref.read(appProvider).myListings;
    if (listings.isEmpty) {
      showLoopSnackBar(t('Nemaš oglasa u Marketu.'), error: true);
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: LoopColors.background,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                t('Pokaži oglas'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              for (final d in listings)
                ListTile(
                  key: ValueKey('story-pick-${d.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: ItemThumb(device: d, size: 44),
                  title: Text(d.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(formatCredits(d.askPrice)),
                  trailing: _deviceId == d.id
                      ? Icon(Icons.check_circle, color: LoopColors.accent)
                      : null,
                  onTap: () => Navigator.pop(ctx, d.id),
                ),
              if (_deviceId != null)
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, ''),
                  icon: const Icon(Icons.close),
                  label: Text(t('Bez oglasa')),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _deviceId = picked.isEmpty ? null : picked);
  }

  Future<void> _close() async {
    if (_hasContent) {
      final ok = await confirmDialog(
        context,
        title: t('Odbaciti priču?'),
        message: t('Promjene neće biti spremljene.'),
        confirmLabel: t('Odbaci'),
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(appProvider.notifier)
          .createStory(
            texts: _layers,
            deviceId: _deviceId,
            imagePath: _photo,
            color: _background,
          );
      if (!mounted) return;
      Navigator.pop(context);
      showLoopSnackBar(t('Priča je objavljena — vidljiva je 24 sata ✨'));
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Izgled ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final d = _deviceId == null ? null : state.deviceById(_deviceId!);
    return PopScope(
      canPop: !_hasContent && _editing == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_editing != null) {
          _finishEditing();
        } else {
          _close();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: AspectRatio(
                          aspectRatio: kStoryAspect,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: _canvas(d),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _bottomBar(),
                ],
              ),
            ),
            if (_editing != null) Positioned.fill(child: _editorOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _canvas(Device? d) => LayoutBuilder(
    key: _canvasKey,
    builder: (context, c) {
      final size = c.biggest;
      final dragging = _dragging != null;
      return Stack(
        fit: StackFit.expand,
        children: [
          StoryBackdrop(
            gradient: Story.palettes[_background % Story.palettes.length],
            photo: _photo,
            device: d,
          ),
          // Dodir na prazno mjesto = novi tekst.
          GestureDetector(
            key: const ValueKey('story-canvas'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _startEditing(),
          ),
          if (_layers.isEmpty && _editing == null)
            IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t('Dodirni za tekst'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                    ),
                  ),
                ),
              ),
            ),
          if (_guideX)
            const Center(
              child: SizedBox(
                width: 1.5,
                height: double.infinity,
                child: ColoredBox(color: Color(0xFF33D1FF)),
              ),
            ),
          if (_guideY)
            const Center(
              child: SizedBox(
                height: 1.5,
                width: double.infinity,
                child: ColoredBox(color: Color(0xFF33D1FF)),
              ),
            ),
          if (d != null && !dragging)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: StoryItemCard(
                device: d,
                price: formatCredits(d.askPrice),
                compact: true,
              ),
            ),
          for (var i = 0; i < _layers.length; i++)
            if (i != _editing)
              positionStoryLayer(
                layer: _layers[i],
                size: size,
                child: GestureDetector(
                  key: ValueKey('story-layer-$i'),
                  onTap: () => _startEditing(i),
                  onScaleStart: (e) => _onScaleStart(i, e),
                  onScaleUpdate: (e) => _onScaleUpdate(i, e),
                  onScaleEnd: (_) => _onScaleEnd(i),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _dragging == i && _overTrash ? 0.4 : 1,
                    child: StoryTextBox(layer: _layers[i], width: size.width),
                  ),
                ),
              ),
          // Kanta za brisanje dok se tekst povlači.
          if (dragging)
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: _overTrash ? 64 : 48,
                  height: _overTrash ? 64 : 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _overTrash
                        ? const Color(0xFFFF3B30)
                        : Colors.black45,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
              ),
            ),
          if (!dragging) _toolbar(),
        ],
      );
    },
  );

  Widget _toolbar() => Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black45, Colors.transparent],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 18),
        child: Row(
          children: [
            _ToolButton(
              key: const ValueKey('story-editor-close'),
              icon: Icons.close,
              tooltip: t('Zatvori'),
              onTap: _close,
            ),
            const Spacer(),
            _ToolButton(
              key: const ValueKey('story-add-text'),
              label: 'Aa',
              tooltip: t('Dodaj tekst'),
              onTap: () => _startEditing(),
            ),
            _ToolButton(
              key: const ValueKey('story-bg'),
              tooltip: t('Promijeni pozadinu'),
              onTap: () => setState(() => _background++),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  gradient: LinearGradient(
                    colors: Story
                        .palettes[(_background + 1) % Story.palettes.length],
                  ),
                ),
              ),
            ),
            _ToolButton(
              key: const ValueKey('story-photo'),
              icon: Icons.add_photo_alternate_outlined,
              tooltip: t('Fotografija'),
              onTap: _photoMenu,
            ),
            _ToolButton(
              key: const ValueKey('story-listing'),
              icon: Icons.sell_outlined,
              tooltip: t('Pokaži oglas'),
              onTap: _pickListing,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _bottomBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _layers.isEmpty
                ? t('Dodirni pozadinu za tekst')
                : t('Povuci tekst · dva prsta za veličinu i rotaciju'),
            maxLines: 2,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          key: const ValueKey('publish-story'),
          onPressed: _busy || _editing != null ? null : _publish,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(
            t('Objavi'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    ),
  );

  /// Širina polja = širina teksta (lomi se kao gotov tekst na priči).
  double _fieldWidth(StoryText d, double width) {
    final style = storyTextStyleFor(d, width);
    final fs = style.fontSize!;
    final pad = d.background == StoryTextBackground.none ? 0.0 : fs * 0.8;
    final max = width * 0.92 - pad;
    final painter = TextPainter(
      text: TextSpan(text: _text.text.isEmpty ? ' ' : _text.text, style: style),
      textAlign: d.align,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: max);
    final w = painter.width + 6; // mjesto za kursor
    painter.dispose();
    return w.clamp(24.0, max + 6);
  }

  /// Upis teksta preko priče: font, boja, poravnanje, pozadina, veličina.
  Widget _editorOverlay() {
    final width = _canvasSize.width;
    final d = _draft;
    final alignIcon = switch (d.align) {
      TextAlign.left => Icons.format_align_left,
      TextAlign.right => Icons.format_align_right,
      _ => Icons.format_align_center,
    };
    // Na webu preglednik sam smanji stranicu za tipkovnicu.
    final keyboard = kIsWeb ? 0.0 : MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Row(
                  children: [
                    _ToolButton(
                      key: const ValueKey('story-align'),
                      icon: alignIcon,
                      tooltip: t('Poravnanje'),
                      onTap: () => _setDraft(
                        (d) => d.copyWith(
                          align: switch (d.align) {
                            TextAlign.center => TextAlign.left,
                            TextAlign.left => TextAlign.right,
                            _ => TextAlign.center,
                          },
                        ),
                      ),
                    ),
                    _ToolButton(
                      key: const ValueKey('story-text-bg'),
                      tooltip: t('Pozadina teksta'),
                      onTap: () => _setDraft(
                        (d) => d.copyWith(
                          background:
                              StoryTextBackground.values[(d.background.index +
                                      1) %
                                  StoryTextBackground.values.length],
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: Colors.white, width: 1.6),
                          color: switch (d.background) {
                            StoryTextBackground.none => Colors.transparent,
                            StoryTextBackground.solid => Colors.white,
                            StoryTextBackground.soft => Colors.white38,
                          },
                        ),
                        child: Text(
                          'A',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: d.background == StoryTextBackground.solid
                                ? Colors.black
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      key: const ValueKey('story-text-done'),
                      onPressed: _finishEditing,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        t('Gotovo'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    // Tekst je u sredini cijele širine (kao kad je postavljen).
                    Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: width * 0.92),
                          child: Center(
                            child: decoratedStoryText(
                              d,
                              width,
                              SizedBox(
                                width: _fieldWidth(d, width),
                                child: TextField(
                                  key: const ValueKey('story-text'),
                                  controller: _text,
                                  focusNode: _focus,
                                  autofocus: true,
                                  maxLines: null,
                                  maxLength: Story.maxText,
                                  textAlign: d.align,
                                  cursorColor: Colors.white,
                                  style: storyTextStyleFor(d, width),
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    isCollapsed: true,
                                    // Tema inače dodaje razmak polju.
                                    contentPadding: EdgeInsets.zero,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    counterText: '',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Veličina slova (okomiti klizač, kao na Instagramu).
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 44,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                            overlayColor: Colors.white12,
                            trackHeight: 3,
                          ),
                          child: Slider(
                            key: const ValueKey('story-size'),
                            min: StoryText.minSize,
                            max: StoryText.maxSize,
                            value: d.size.clamp(
                              StoryText.minSize,
                              StoryText.maxSize,
                            ),
                            onChanged: (v) =>
                                _setDraft((d) => d.copyWith(size: v)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Fontovi.
              SizedBox(
                key: const ValueKey('story-fonts'),
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final f in StoryFont.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Pill(
                          key: ValueKey('story-font-${f.name}'),
                          selected: d.font == f,
                          onTap: () => _setDraft((d) => d.copyWith(font: f)),
                          child: Text(
                            storyFontLabel(f),
                            style: storyFontStyle(f).copyWith(
                              fontSize: f == StoryFont.modern ? 18 : 14,
                              height: 1.1,
                              color: d.font == f ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Boje.
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (var i = 0; i < StoryText.colors.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          key: ValueKey('story-color-$i'),
                          onTap: () => _setDraft(
                            (d) => d.copyWith(color: StoryText.colors[i]),
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: d.color == StoryText.colors[i] ? 36 : 30,
                            height: d.color == StoryText.colors[i] ? 36 : 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(StoryText.colors[i]),
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Okrugli gumb alata na tamnoj podlozi.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.tooltip,
    required this.onTap,
    this.icon,
    this.label,
    this.child,
  });

  final String tooltip;
  final VoidCallback onTap;
  final IconData? icon;
  final String? label;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black38,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child:
                  child ??
                  (label != null
                      ? Text(
                          label!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        )
                      : Icon(icon, color: Colors.white, size: 22)),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.black38,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white54),
      ),
      child: child,
    ),
  );
}
