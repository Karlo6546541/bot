import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/device.dart';
import '../models/live_show.dart';
import '../services/live_service.dart';
import '../services/live_video.dart';
import '../theme/app_theme.dart';
import '../widgets/category_style.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/story_canvas.dart';
import '../widgets/user_avatar.dart';

/// Pozadina gledatelja kad kamere nema: fotografija predmeta preko cijelog
/// ekrana, inače tihi gradijent kategorije.
List<Color> viewerStageGradient(Device? device) => device == null
    ? const [Color(0xFF28282D), Color(0xFF08080A)]
    : [
        device.category.color,
        Color.lerp(device.category.color, Colors.black, 0.75)!,
      ];

Widget viewerStageBackdrop({Device? device, String? coverPath}) {
  final backdrop = StoryBackdrop(
    gradient: viewerStageGradient(device),
    device: device,
  );
  final path = device != null && device.imagePaths.isNotEmpty
      ? device.imagePaths.first
      : coverPath;
  if (path == null) return backdrop;
  return Stack(
    fit: StackFit.expand,
    children: [
      backdrop,
      LocalPhoto(path: path, fit: BoxFit.cover, fallback: backdrop),
    ],
  );
}

/// Mala oznaka umjesto velikog čipa "Video trenutno nije uključen".
class ViewerVideoCaption extends StatelessWidget {
  const ViewerVideoCaption({
    super.key,
    required this.show,
    required this.watcher,
    required this.online,
  });

  final LiveShow show;
  final LiveWatcher? watcher;
  final bool online;

  Widget _label(String text, {Key? key}) => Padding(
    padding: const EdgeInsets.only(left: 12, top: 2),
    child: Text(
      text,
      key: key,
      style: const TextStyle(
        color: Color(0xC7FFFFFF),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!show.video) {
      return _label(t('Bez videa'), key: const ValueKey('live-no-video'));
    }
    if (!online) {
      return _label(
        t('Video radi u online verziji'),
        key: const ValueKey('live-video-offline'),
      );
    }
    final watcher = this.watcher;
    if (watcher == null) {
      return _label(t('Bez videa'), key: const ValueKey('live-no-video'));
    }
    return ValueListenableBuilder<LiveVideoStatus>(
      valueListenable: watcher.status,
      builder: (_, status, _) => switch (status) {
        LiveVideoStatus.playing => const SizedBox.shrink(),
        LiveVideoStatus.connecting => _label(t('Spajam video…')),
        LiveVideoStatus.offline => _label(
          t('Bez videa'),
          key: const ValueKey('live-no-video'),
        ),
        LiveVideoStatus.blocked => _label(
          LiveVideoConfig.hasTurn
              ? t('Video se ne spaja — pokušavam ponovno…')
              : t('Video ne prolazi kroz ovu mrežu — probaj isti Wi-Fi'),
          key: const ValueKey('live-video-blocked'),
        ),
      },
    );
  }
}

/// Tanka gornja traka gledatelja: avatar, ime, Prati, UŽIVO, oko + broj, X.
class ViewerTopBar extends StatelessWidget {
  const ViewerTopBar({
    super.key,
    required this.show,
    required this.state,
    required this.host,
    required this.hostName,
    required this.following,
    required this.showFollow,
    required this.onHost,
    required this.onFollow,
    required this.onViewers,
    required this.onClose,
  });

  final LiveShow show;
  final LiveState state;
  final AppUser? host;
  final String hostName;
  final bool following;
  final bool showFollow;
  final VoidCallback onHost;
  final VoidCallback onFollow;
  final VoidCallback onViewers;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('live-compact-header'),
      padding: const EdgeInsets.fromLTRB(10, 4, 2, 0),
      child: Row(
        children: [
          UserAvatar(user: host, size: 28),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: onHost,
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
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.2,
                  ),
                ),
              ),
            ),
          ),
          if (showFollow) ...[
            const SizedBox(width: 6),
            FilledButton(
              key: const ValueKey('live-follow'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white12,
                disabledForegroundColor: Colors.white70,
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: following ? null : onFollow,
              child: Text(t(following ? 'Pratim' : 'Prati')),
            ),
          ],
          if (state.isLive) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: LoopColors.live,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                t('UŽIVO'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .4,
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              key: const ValueKey('live-viewers-open'),
              borderRadius: BorderRadius.circular(99),
              onTap: onViewers,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.visibility_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${state.viewers}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          IconButton(
            key: const ValueKey('live-close'),
            tooltip: t('Zatvori'),
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }
}

/// Donja trećina sobe gledatelja: chat, jedna kartica, jedna radnja, red.
class ViewerBottomChrome extends StatelessWidget {
  const ViewerBottomChrome({
    super.key,
    required this.show,
    required this.state,
    required this.now,
    required this.me,
    required this.device,
    required this.lot,
    required this.result,
    required this.featured,
    required this.featuredPrice,
    required this.leaderName,
    required this.composing,
    required this.chatHidden,
    required this.liked,
    required this.busy,
    required this.canAct,
    required this.guest,
    required this.entered,
    required this.catalogCount,
    required this.chat,
    required this.chatController,
    required this.chatFocus,
    required this.onSend,
    required this.onLogin,
    required this.onHeart,
    required this.onShare,
    required this.onToggleChat,
    required this.onTools,
    required this.onCatalog,
    required this.onBid,
    required this.onTake,
    required this.onEnter,
    required this.onBuy,
  });

  final LiveShow show;
  final LiveState state;
  final DateTime now;
  final String? me;
  final Device? device;
  final LotState? lot;
  final bool result;
  final Device? featured;
  final double? featuredPrice;
  final String? leaderName;
  final bool composing;
  final bool chatHidden;
  final bool liked;
  final bool busy;
  final bool canAct;
  final bool guest;
  final bool entered;
  final int catalogCount;
  final Widget chat;
  final TextEditingController chatController;
  final FocusNode chatFocus;
  final Future<void> Function(String) onSend;
  final VoidCallback onLogin;
  final VoidCallback onHeart;
  final VoidCallback onShare;
  final VoidCallback onToggleChat;
  final VoidCallback onTools;
  final VoidCallback onCatalog;
  final VoidCallback onBid;
  final VoidCallback onTake;
  final VoidCallback onEnter;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    if (state.isOver) return const SizedBox.shrink();
    final hasText = chatController.text.trim().isNotEmpty;
    final card = _card(context);
    final action = _action();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 8, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!composing)
            SizedBox(
              height: 78,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: chatHidden
                        ? const SizedBox.shrink()
                        : Align(alignment: Alignment.bottomLeft, child: chat),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _edgeIcon(
                        key: const ValueKey('live-rail-share'),
                        tooltip: t('Podijeli'),
                        icon: Icons.ios_share,
                        onTap: onShare,
                      ),
                      _edgeIcon(
                        key: const ValueKey('live-chat-toggle'),
                        tooltip: chatHidden
                            ? t('Prikaži chat')
                            : t('Sakrij chat'),
                        icon: chatHidden
                            ? Icons.chat_bubble_outline
                            : Icons.speaker_notes_off_outlined,
                        onTap: onToggleChat,
                      ),
                      _edgeIcon(
                        key: const ValueKey('live-room-tools'),
                        tooltip: t('Više'),
                        icon: Icons.more_horiz,
                        onTap: onTools,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (!composing && card != null) card,
          if (!composing && action != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: action),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _field(hasText)),
              const SizedBox(width: 6),
              _round(
                key: const ValueKey('live-heart'),
                tooltip: t('Srce'),
                onTap: onHeart,
                child: Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? LoopColors.live : Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                key: const ValueKey('live-queue'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xCC1C1C22),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: const StadiumBorder(
                    side: BorderSide(color: Color(0x33FFFFFF)),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: onCatalog,
                icon: const Icon(
                  Icons.shopping_bag_outlined,
                  size: 16,
                  color: Color(0xFF7DDEA0),
                ),
                label: Text(t('Predmeti {0}', ['$catalogCount'])),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _edgeIcon({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) => Tooltip(
    message: tooltip,
    child: InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 36,
        height: 24,
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    ),
  );

  Widget _round({
    required Key key,
    required String tooltip,
    required VoidCallback onTap,
    required Widget child,
  }) => Semantics(
    button: true,
    label: tooltip,
    excludeSemantics: true,
    child: InkWell(
      key: key,
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xCC1C1C22),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: child,
      ),
    ),
  );

  Widget _field(bool hasText) => TextField(
    key: const ValueKey('live-chat'),
    readOnly: guest,
    canRequestFocus: !guest,
    onTap: guest ? onLogin : null,
    controller: chatController,
    focusNode: chatFocus,
    scrollPadding: const EdgeInsets.all(12),
    maxLength: LiveEvent.maxText,
    style: const TextStyle(color: Colors.white, fontSize: 14),
    textInputAction: TextInputAction.send,
    onSubmitted: onSend,
    decoration: InputDecoration(
      isDense: true,
      counterText: '',
      hintText: t('Pitaj prodavača…'),
      hintStyle: const TextStyle(color: Colors.white60, fontSize: 14),
      filled: true,
      fillColor: const Color(0xCC1C1C22),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      suffixIcon: hasText
          ? IconButton(
              key: const ValueKey('live-send'),
              tooltip: t('Pošalji'),
              onPressed: () => onSend(chatController.text),
              icon: const Icon(Icons.send, color: Colors.white70, size: 18),
            )
          : null,
    ),
  );

  Widget? _card(BuildContext context) {
    final product = featured;
    final price = featuredPrice;
    if (lot == null && product != null && price != null) {
      return _ItemCard(
        key: const ValueKey('live-featured'),
        thumb: ItemThumb(device: product, size: 46),
        title: product.name,
        badge: t('KUPI ODMAH'),
        badgeColor: const Color(0xFF7DDEA0),
        condition: product.isDigital ? t('Digitalno') : product.condition.label,
        price: formatCredits(price),
      );
    }
    final current = lot;
    if (current == null) return null;
    final left = current.left(now);
    final seconds = current.lot.seconds ?? show.lotSeconds;
    final hot =
        !result &&
        current.mode == LotMode.auction &&
        left <= LiveShow.hotWindow;
    final progress = seconds <= 0
        ? 0.0
        : (left.inMilliseconds / (seconds * 1000)).clamp(0.0, 1.0);
    final d = device;
    final condition = d == null
        ? ''
        : d.isDigital
        ? t('Digitalno')
        : d.condition.label;
    final amount = switch (current.mode) {
      LotMode.giveaway => t('Besplatno'),
      LotMode.dutch when !result => formatCredits(
        current.dutchPriceAt(now, seconds),
      ),
      _ => formatCredits(current.price),
    };
    final badge = switch (current.mode) {
      LotMode.auction => t('AUKCIJA'),
      LotMode.dutch => t('Pada cijena'),
      LotMode.giveaway => t('Nagradna igra'),
    };
    final badgeColor = switch (current.mode) {
      LotMode.auction => const Color(0xFFFFB020),
      LotMode.dutch => const Color(0xFF7DDEA0),
      LotMode.giveaway => const Color(0xFFFFD60A),
    };
    final leading = !result && current.leader?.userId == me;
    final winner = leaderName ?? current.leader?.userLabel;
    final status = result
        ? (current.leader == null
              ? (current.mode == LotMode.giveaway
                    ? t('Nitko se nije prijavio')
                    : t('Nije prodano'))
              : current.leader!.userId == me
              ? t('Osvojio si!')
              : current.mode == LotMode.giveaway
              ? '$winner ${t('je izvučen!')}'
              : '$winner${t(' je osvojio!')}')
        : leading
        ? t('Ti vodiš')
        : null;
    return _ItemCard(
      key: ValueKey(result ? 'live-result' : 'live-lot'),
      thumb: d == null
          ? const SizedBox(width: 46, height: 46)
          : ItemThumb(device: d, size: 46),
      title: current.lot.deviceName,
      badge: badge,
      badgeColor: badgeColor,
      condition: condition,
      status: status,
      price: amount,
      countdown: !result && current.mode == LotMode.auction
          ? _clock(left)
          : null,
      hot: hot,
      progress: !result && current.mode == LotMode.auction ? progress : null,
    );
  }

  Widget? _action() {
    final product = featured;
    if (lot == null && product != null) {
      return _primary(
        key: const ValueKey('live-featured-buy'),
        label: t('Kupi odmah {0}', [
          formatCredits(featuredPrice ?? product.askPrice),
        ]),
        onPressed: onBuy,
        color: const Color(0xFFFF5A1F),
      );
    }
    final current = lot;
    if (current == null || result) {
      if (!state.isLive) return null;
      return _primary(
        key: const ValueKey('live-awaiting'),
        label: t('Čeka se sljedeći predmet'),
        onPressed: null,
        color: const Color(0xFF2A2A30),
      );
    }
    if (!canAct) {
      return _primary(
        key: const ValueKey('live-login'),
        label: t('Prijavi se za licitiranje'),
        onPressed: onLogin,
        color: const Color(0xFFFF5A1F),
      );
    }
    if (current.mode == LotMode.dutch) {
      final price = current.dutchPriceAt(
        now,
        current.lot.seconds ?? show.lotSeconds,
      );
      return _primary(
        key: const ValueKey('live-take'),
        label: t('⬇️ Uzmi za {0}', [formatCredits(price)]),
        onPressed: busy ? null : onTake,
        color: const Color(0xFF1E7E34),
      );
    }
    if (current.mode == LotMode.giveaway) {
      if (entered) {
        return Container(
          key: const ValueKey('live-entered'),
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1E7E34),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            t('✓ Sudjeluješ · izvlačenje na kraju'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      }
      return _primary(
        key: const ValueKey('live-enter'),
        label: t('Sudjeluj besplatno'),
        onPressed: busy ? null : onEnter,
        color: const Color(0xFFFFC233),
        foreground: Colors.black,
      );
    }
    if (current.leader?.userId == me) {
      return Container(
        key: const ValueKey('live-leading'),
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1E7E34),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          t('✓ Vodiš s {0}', [formatCredits(current.price)]),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      );
    }
    return _primary(
      key: const ValueKey('live-bid'),
      label: busy
          ? t('Šaljem ponudu…')
          : t('Licitiraj {0}', [formatCredits(current.minNext)]),
      onPressed: busy ? null : onBid,
      color: const Color(0xFFFF5A1F),
    );
  }

  Widget _primary({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
    Color foreground = Colors.white,
  }) => FilledButton(
    key: key,
    style: FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: foreground,
      disabledBackgroundColor: const Color(0xFF2A2A30),
      disabledForegroundColor: Colors.white70,
      minimumSize: const Size.fromHeight(46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(
        fontFamily: kFontFamily,
        fontWeight: FontWeight.w800,
        fontSize: 16,
      ),
    ),
    onPressed: onPressed,
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );

  static String _clock(Duration left) {
    final seconds = left.isNegative ? 0 : left.inSeconds;
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    super.key,
    required this.thumb,
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.condition,
    this.status,
    required this.price,
    this.countdown,
    this.progress,
    this.hot = false,
  });

  final Widget thumb;
  final String title;
  final String badge;
  final Color badgeColor;
  final String condition;
  final String? status;
  final String price;
  final String? countdown;
  final double? progress;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xF2141418),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: 46, height: 46, child: thumb),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: badge,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .3,
                            ),
                          ),
                          if (condition.isNotEmpty)
                            TextSpan(
                              text: '  $condition',
                              style: const TextStyle(
                                color: Color(0xFFC8C8D0),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (status != null)
                      Text(
                        status!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
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
                    price,
                    key: const ValueKey('live-price'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: -.3,
                    ),
                  ),
                  if (countdown != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 12,
                          color: hot ? LoopColors.live : Colors.white70,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          countdown!,
                          key: const ValueKey('live-secs'),
                          style: TextStyle(
                            color: hot ? LoopColors.live : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
          if (progress != null)
            Padding(
              key: const ValueKey('live-rules'),
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  color: hot ? LoopColors.live : const Color(0xFFFF5A1F),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
