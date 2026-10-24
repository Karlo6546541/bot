import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/tr.dart';
import '../models/chat_message.dart';
import '../models/device.dart';
import '../models/swap_offer.dart';
import '../providers/app_providers.dart';
import '../services/fee.dart';
import '../services/trade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/item_image.dart';
import '../widgets/trade_actions.dart';
import '../widgets/user_avatar.dart';
import 'device_detail_screen.dart';
import 'public_profile_screen.dart';

/// Poruke: razgovori i ponude zamjene.
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const MessagesScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final conversations = state.conversations;
    final offers = state.myOffers.where((o) => o.isPending).toList();
    return Scaffold(
      appBar: AppBar(title: Text(t('Poruke'))),
      body: conversations.isEmpty && offers.isEmpty
          ? EmptyState(
              icon: Icons.chat_bubble_outline,
              title: t('Još nema poruka'),
              message: t('Na predmetu na prodaji dodirni "Pošalji poruku".'),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  children: [
                    if (offers.isNotEmpty) ...[
                      _Section(t('Ponude zamjene ({0})', [offers.length])),
                      for (final o in offers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SwapOfferCard(offer: o),
                        ),
                    ],
                    if (conversations.isNotEmpty) _Section(t('Razgovori')),
                    for (final c in conversations)
                      Card(
                        child: ListTile(
                          leading: UserAvatar(
                            user: state.userById(c.otherId),
                            size: 40,
                          ),
                          title: Text(
                            state.userLabel(c.otherId),
                            style: TextStyle(
                              fontWeight: c.unread > 0
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${c.last.senderId == state.currentUserId ? '${t('Ti')}: ' : ''}${c.last.text}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: c.unread > 0
                              ? Badge(label: Text('${c.unread}'))
                              : Text(
                                  formatDate(c.last.createdAt),
                                  style: TextStyle(
                                    color: LoopColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                          onTap: () => ChatScreen.open(context, c.otherId),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
    ),
  );
}

/// Razgovor s jednim korisnikom (+ ponude zamjene između vas).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.otherId, this.deviceId});

  final String otherId;

  /// Predmet o kojem se pita (prva poruka ga prikaže kao karticu).
  final String? deviceId;

  static Future<void> open(
    BuildContext context,
    String otherId, {
    String? deviceId,
  }) async {
    if (blockGuest(context)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(otherId: otherId, deviceId: deviceId),
      ),
    );
  }

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  late String? _deviceId = widget.deviceId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _markRead() {
    if (mounted) {
      ref.read(appProvider.notifier).markChatRead(widget.otherId);
    }
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(appProvider.notifier)
          .sendMessage(widget.otherId, _text.text, deviceId: _deviceId);
      _text.clear();
      setState(() => _deviceId = null); // kartica predmeta samo uz prvu
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final me = state.currentUserId;
    final other = state.userById(widget.otherId);
    final messages = state.chatWith(widget.otherId);
    final offers = state.myOffers
        .where(
          (o) =>
              o.isPending &&
              (o.fromId == widget.otherId || o.toId == widget.otherId),
        )
        .toList();
    // Nove poruke dok je razgovor otvoren su odmah pročitane.
    if (messages.any((m) => m.receiverId == me && !m.read)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
    }
    final pending = _deviceId == null ? null : state.deviceById(_deviceId!);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: other == null
              ? null
              : () => PublicProfileScreen.open(context, other.id),
          child: Row(
            children: [
              UserAvatar(user: other, size: 34),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  state.userLabel(widget.otherId),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              for (final o in offers)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: SwapOfferCard(offer: o),
                ),
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            t(
                              'Napiši prvu poruku. Budi pristojan — poruke se mogu prijaviti.',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: LoopColors.textSecondary),
                          ),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final m = messages[messages.length - 1 - i];
                          return _Bubble(message: m, mine: m.senderId == me);
                        },
                      ),
              ),
              if (pending != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.attach_file,
                        size: 16,
                        color: LoopColors.textSecondary,
                      ),
                      Expanded(
                        child: Text(
                          t('O predmetu: {0}', [pending.name]),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: LoopColors.textSecondary),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _deviceId = null),
                      ),
                    ],
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chat-input'),
                          controller: _text,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: ChatMessage.maxLength,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: t('Poruka…'),
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        key: const ValueKey('chat-send'),
                        tooltip: t('Pošalji'),
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
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

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = message.deviceId == null
        ? null
        : ref.watch(appProvider).deviceById(message.deviceId!);
    final bg = mine ? LoopColors.accent : LoopColors.surface;
    final fg = mine ? LoopColors.onAccent : LoopColors.textPrimary;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomRight: mine ? const Radius.circular(4) : null,
              bottomLeft: mine ? null : const Radius.circular(4),
            ),
            border: mine ? null : Border.all(color: LoopColors.surfaceHover),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (device != null)
                InkWell(
                  onTap: () => DeviceDetailScreen.open(context, device),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ItemThumb(device: device, size: 32),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${device.name} · ${formatCredits(device.shownPrice)}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Text(message.text, style: TextStyle(color: fg)),
              const SizedBox(height: 2),
              Text(
                formatDateTime(message.createdAt),
                style: TextStyle(
                  color: fg.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ponuda zamjene s gumbima (prihvati/odbij ili povuci).
class SwapOfferCard extends ConsumerWidget {
  const SwapOfferCard({super.key, required this.offer});
  final SwapOffer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final incoming = offer.toId == state.currentUserId;
    final c = ref.read(appProvider.notifier);
    final other = incoming ? offer.fromId : offer.toId;
    return Card(
      color: LoopColors.lilac,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              incoming
                  ? t('🔄 {0} ti nudi zamjenu', [state.userLabel(other)])
                  : t('🔄 Tvoja ponuda za {0}', [state.userLabel(other)]),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              incoming
                  ? t('Dobivaš: {0}{1}\nDaješ: {2}', [
                      offer.offeredName,
                      offer.extraCredits > 0
                          ? t(' + {0}', [formatCredits(offer.extraCredits)])
                          : '',
                      offer.wantedName,
                    ])
                  : t('Nudiš: {0}{1}\nZa: {2}', [
                      offer.offeredName,
                      offer.extraCredits > 0
                          ? t(' + {0}', [formatCredits(offer.extraCredits)])
                          : '',
                      offer.wantedName,
                    ]),
              style: const TextStyle(height: 1.4),
            ),
            if (offer.message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('"${offer.message}"'),
            ],
            const SizedBox(height: 10),
            if (incoming)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: ValueKey('accept-${offer.id}'),
                      onPressed: () async {
                        final ok = await confirmDialog(
                          context,
                          title: t('Prihvatiti zamjenu?'),
                          message: t(
                            'Daješ "{0}" i dobivaš "{1}"{2}. Zamjena je konačna, a oboje zatim birate dostavu.',
                            [
                              offer.wantedName,
                              offer.offeredName,
                              offer.extraCredits > 0
                                  ? t(' + {0}', [
                                      formatCredits(
                                        sellPayout(offer.extraCredits),
                                      ),
                                    ])
                                  : '',
                            ],
                          ),
                          confirmLabel: t('Prihvati'),
                        );
                        if (!ok || !context.mounted) return;
                        await runWithLoading(
                          context,
                          () => c.acceptSwap(offer.id),
                          successMessage: t(
                            'Zamjena prihvaćena 🤝 — odaberi dostavu u "Moje dostave".',
                          ),
                        );
                      },
                      icon: const Icon(Icons.handshake_outlined),
                      label: Text(t('Prihvati')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => runWithLoading(
                        context,
                        () => c.declineSwap(offer.id),
                        successMessage: t('Ponuda odbijena'),
                      ),
                      child: Text(t('Odbij')),
                    ),
                  ),
                ],
              )
            else
              OutlinedButton(
                onPressed: () => runWithLoading(
                  context,
                  () => c.withdrawSwap(offer.id),
                  successMessage: t('Ponuda povučena'),
                ),
                child: Text(t('Povuci ponudu')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ponudi zamjenu: odaberi svoj predmet, nadoplatu i poruku.
Future<void> showSwapSheet(
  BuildContext context,
  WidgetRef ref,
  Device wanted,
) async {
  if (blockGuest(context)) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SwapSheet(wanted: wanted),
  );
}

class _SwapSheet extends ConsumerStatefulWidget {
  const _SwapSheet({required this.wanted});
  final Device wanted;

  @override
  ConsumerState<_SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends ConsumerState<_SwapSheet> {
  String? _offered;
  final _extra = TextEditingController(text: '0');
  final _message = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _extra.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final offered = _offered;
    if (offered == null) return;
    final extra =
        double.tryParse(_extra.text.trim().replaceAll(',', '.')) ?? -1;
    if (extra < 0) {
      showLoopSnackBar(t('Unesi ispravan iznos'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(appProvider.notifier)
          .offerSwap(
            wantedDeviceId: widget.wanted.id,
            offeredDeviceId: offered,
            extraCredits: extra,
            message: _message.text,
          );
      if (mounted) Navigator.pop(context);
      showLoopSnackBar(t('Ponuda zamjene poslana 🔄'));
    } on TradeException catch (e) {
      showLoopSnackBar(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final mine = state.myDevices
        .where((d) => state.activeAuctionFor(d.id) == null)
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('Ponudi zamjenu'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            Text(
              t('Za: {0} ({1})', [
                widget.wanted.name,
                formatCredits(widget.wanted.shownPrice),
              ]),
              style: TextStyle(color: LoopColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              t('Tvoj predmet'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (mine.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  t('Nemaš predmeta za zamjenu — dodaj ga u Moje predmete.'),
                  style: TextStyle(color: LoopColors.textSecondary),
                ),
              )
            else
              RadioGroup<String>(
                groupValue: _offered,
                onChanged: (v) => setState(() => _offered = v),
                child: Column(
                  children: [
                    for (final d in mine)
                      RadioListTile<String>(
                        value: d.id,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        secondary: ItemThumb(device: d, size: 36),
                        title: Text('${d.name} ${d.model}'),
                        subtitle: Text(formatCredits(d.price)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _extra,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: t('Nadoplata u eurima (neobavezno)'),
                helperText: t('Plaća se karticom kad druga strana prihvati.'),
                suffixText: t('€'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              maxLength: SwapOffer.maxMessage,
              decoration: InputDecoration(labelText: t('Poruka (neobavezno)')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('swap-send'),
              onPressed: _offered == null || _busy ? null : _send,
              icon: const Icon(Icons.swap_horiz),
              label: Text(t('Pošalji ponudu')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ikona poruka s brojem nepročitanih (i ponuda koje čekaju odgovor).
class MessagesButton extends ConsumerWidget {
  const MessagesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      appProvider.select((s) => s.unreadMessages + s.incomingOffers.length),
    );
    return IconButton(
      key: const ValueKey('messages-button'),
      tooltip: t('Poruke'),
      onPressed: () => MessagesScreen.open(context),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 9 ? '9+' : '$count'),
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }
}
