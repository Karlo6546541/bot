import 'dart:ui';

import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../theme/app_theme.dart';

/// The supplied artboard uses one bottom sheet for secondary destinations.
Future<T?> openReferenceSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  bool scaffoldContent = false,
  RouteSettings? settings,
}) => Navigator.of(context).push<T>(
  PageRouteBuilder<T>(
    settings: settings,
    opaque: false,
    barrierColor: Colors.black54,
    barrierDismissible: false,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => ReferenceSheet(
      title: title,
      scaffoldContent: scaffoldContent,
      child: builder(ctx),
    ),
    transitionsBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(0, .12),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: animation, child: child),
    ),
  ),
);

class ReferenceSheet extends StatelessWidget {
  const ReferenceSheet({
    super.key,
    required this.title,
    required this.child,
    this.scaffoldContent = false,
  });
  final String title;
  final Widget child;
  final bool scaffoldContent;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, box) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final available = (box.maxHeight - keyboard).clamp(
          120.0,
          box.maxHeight,
        );
        final theme = Theme.of(context);
        final content = scaffoldContent
            ? Theme(
                data: theme.copyWith(
                  scaffoldBackgroundColor: Colors.transparent,
                  appBarTheme: theme.appBarTheme.copyWith(
                    toolbarHeight: 0,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                  ),
                ),
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child,
                ),
              )
            : child;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SizedBox(
              height: available * .90,
              width: box.maxWidth.clamp(0, 720),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(38),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 44, sigmaY: 44),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: dark
                          ? const Color(0xFF16161C).withValues(alpha: .88)
                          : Colors.white.withValues(alpha: .94),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(38),
                      ),
                      border: Border.all(
                        color: dark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          Container(
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(
                              color: dark ? Colors.white30 : Colors.black26,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 7, 16, 8),
                            child: SizedBox(
                              height: 52,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontFamily: kFontFamily,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -.44,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: IconButton(
                                      key: const ValueKey(
                                        'reference-sheet-close',
                                      ),
                                      tooltip: t('Zatvori'),
                                      style: IconButton.styleFrom(
                                        backgroundColor: dark
                                            ? Colors.white12
                                            : Colors.black.withValues(
                                                alpha: .06,
                                              ),
                                        shape: const CircleBorder(),
                                        padding: EdgeInsets.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () =>
                                          Navigator.of(context).maybePop(),
                                      icon: const Icon(Icons.close, size: 20),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: MediaQuery.removeViewInsets(
                              context: context,
                              removeBottom: true,
                              child: content,
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
        );
      },
    );
  }
}
