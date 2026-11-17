import 'vision_live_controls.dart';
import 'vision_glass.dart';
import 'package:flutter/material.dart';
import '../services/stripe_backend.dart';
import '../services/delivery_locations.dart';
import '../theme/app_theme.dart';
import 'formatters.dart';
import '../l10n/tr.dart';

Future<bool> showPurchaseConfirmation(
  BuildContext context,
  PurchaseConfirmationSheet sheet,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      enableDrag: false,
      constraints: const BoxConstraints(maxWidth: 520),
      backgroundColor: Colors.transparent,
      builder: (_) => VisionGlass(
        dark: LoopColors.isDark,
        heavy: true,
        opacity: .85,
        radius: 32,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: LoopColors.textSecondary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Flexible(child: appThemed(sheet)),
          ],
        ),
      ),
    ) ??
    false;

/// "Završetak kupnje": cijeli ekran poslije dodira na "Kupi odmah" (artikal,
/// adresa, dostava, plaćanje, sažetak cijene i "Plati"). Poslužitelj i dalje
/// jedini označava narudžbu plaćenom.
Future<bool> showCheckoutPage(
  BuildContext context,
  PurchaseConfirmationSheet sheet,
) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => appThemed(
          Scaffold(
            appBar: AppBar(
              title: Text(t('Završetak kupnje')),
              leading: BackButton(key: const ValueKey('purchase-close')),
            ),
            body: sheet,
          ),
        ),
      ),
    ) ??
    false;

/// Purchase confirmation stays over the item; only the server can mark it paid.
class PurchaseConfirmationSheet extends StatefulWidget {
  const PurchaseConfirmationSheet({
    super.key,
    required this.title,
    required this.totalCents,
    required this.loadCard,
    required this.addCard,
    required this.reserve,
    required this.chooseDelivery,
    required this.charge,
    this.address = '',
    this.digital = false,
    this.country = 'HR',
    this.searchLockers,
    this.embedded = false,
    this.onResult,
    this.itemCents,
    this.shippingCents = 0,
    this.orderTotal,
    this.page = false,
    this.image,
    this.subtitle = '',
    this.recipient = '',
  });

  /// Cijena proizvoda bez dostave (za raščlambu); kad je zadana, [totalCents]
  /// je proizvod + procjena dostave, a poslužitelj se uspoređuje s proizvodom.
  final int? itemCents;
  final int shippingCents;

  /// Stvarni ukupni iznos narudžbe na poslužitelju nakon odabira dostave.
  final Future<int> Function(String orderId)? orderTotal;

  /// Cijeli ekran "Završetak kupnje" (vidi [showCheckoutPage]).
  final bool page;

  /// Samo za [page]: fotografija artikla, podnaslov (stanje) i ime primatelja.
  final Widget? image;
  final String subtitle;
  final String recipient;
  final bool embedded;
  final ValueChanged<bool>? onResult;
  final String title;
  final int totalCents;
  final String address;
  final bool digital;
  final String country;
  final Future<List<DeliveryLocation>> Function(String)? searchLockers;
  final Future<({bool hasCard, String? last4})> Function() loadCard;
  final Future<bool> Function(BuildContext) addCard;
  final Future<Map<String, dynamic>> Function() reserve;
  final Future<void> Function(String, DeliveryDestination) chooseDelivery;
  final Future<SavedCardChargeStatus> Function(String, BuildContext) charge;

  @override
  State<PurchaseConfirmationSheet> createState() =>
      _PurchaseConfirmationState();
}

class _PurchaseConfirmationState extends State<PurchaseConfirmationSheet> {
  late final TextEditingController _address = TextEditingController(
    text: widget.address,
  );
  late int _totalCents = widget.totalCents;
  String? _last4, _error, _orderId;
  bool _hasCard = false, _loadingCard = true, _busy = false;
  bool _completed = false;
  bool _checkingPayment = false, _editingAddress = false;

  @override
  void initState() {
    super.initState();
    _loadCard();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadCard() async {
    if (mounted) {
      setState(() {
        _loadingCard = true;
        _error = null;
      });
    }
    try {
      final card = await widget.loadCard();
      if (!mounted) return;
      setState(() {
        _hasCard = card.hasCard;
        _last4 = card.last4;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = paymentActionErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingCard = false);
      }
    }
  }

  Future<void> _addCard() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.addCard(context);
      if (mounted) {
        await _loadCard();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = paymentActionErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pay() async {
    if (_busy || _completed) return;
    if (_busy || _loadingCard) return;
    if (!_hasCard) {
      await _addCard();
      return;
    }
    if (!widget.digital && _address.text.trim().isEmpty) {
      setState(() {
        _editingAddress = true;
        _error = 'Upiši adresu za dostavu.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_orderId == null) {
        final order = await widget.reserve();
        if (!mounted) return;
        _orderId = order['id'] as String;
        final serverTotal = (order['total_cents'] as num).toInt();
        if (serverTotal != (widget.itemCents ?? _totalCents)) {
          setState(() {
            _totalCents = serverTotal;
            _error = 'Cijena je promijenjena. Potvrdi novi ukupan iznos.';
          });
          return;
        }
      }
      if (!_checkingPayment && !widget.digital) {
        // Kupac ne bira dostavu: paket ide na adresu iz računa, a prodavač
        // šalje kurirom ili u paketomat i kupcu javi broj za praćenje.
        await widget.chooseDelivery(
          _orderId!,
          DeliveryDestination.courier(_address.text.trim()),
        );
        final fetch = widget.orderTotal;
        if (fetch != null) {
          final real = await fetch(_orderId!);
          if (!mounted) return;
          if (real != _totalCents) {
            // Poslužitelj je odredio drugačiji iznos: ništa se ne naplaćuje
            // dok kupac ne potvrdi novi iznos.
            setState(() {
              _totalCents = real;
              _error = 'Iznos je promijenjen. Provjeri i potvrdi novi iznos.';
            });
            return;
          }
        }
      }
      if (!mounted) return;
      // Retries always check the same order, including after a lost response.
      _checkingPayment = true;
      final status = await widget.charge(_orderId!, context);
      if (!mounted) return;
      if (status == SavedCardChargeStatus.paid) {
        setState(() => _completed = true);
        if (widget.embedded) {
          widget.onResult?.call(true);
        } else {
          Navigator.pop(context, true);
        }
      } else {
        setState(
          () => _error = status == SavedCardChargeStatus.processing
              ? 'Plaćanje je u obradi. Provjeri njegov status.'
              : 'Plaćanje nije dovršeno. Možeš pokušati ponovno.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = paymentActionErrorMessage(error);
          if (paymentClearlyRejected(error)) _checkingPayment = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _line(String label, int cents, String key) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          cents == 0 ? 'Besplatno' : formatCredits(cents / 100),
          key: ValueKey(key),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) =>
      widget.page ? _pageBody(context) : _sheetBody(context);

  Widget _sheetBody(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('purchase-confirmation'),
        padding: EdgeInsets.fromLTRB(
          widget.embedded ? 0 : 20,
          0,
          widget.embedded ? 0 : 20,
          (widget.embedded ? 0 : 20) + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.embedded)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Potvrdi kupnju',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('purchase-close'),
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            if (!widget.embedded) const SizedBox(height: 8),
            if (!widget.embedded)
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.credit_card_outlined, size: 21),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _loadingCard
                        ? 'Provjera kartice…'
                        : _hasCard
                        ? 'Kartica •••• ${_last4 ?? "••••"}'
                        : 'Dodaj karticu za plaćanje',
                  ),
                ),
                if (!_loadingCard)
                  TextButton(
                    onPressed: _busy ? null : _addCard,
                    child: Text(_hasCard ? 'Promijeni' : 'Dodaj'),
                  ),
              ],
            ),
            if (!widget.digital) ...[
              const SizedBox(height: 8),
              if (_editingAddress || widget.address.trim().isEmpty)
                TextField(
                  key: const ValueKey('purchase-address'),
                  controller: _address,
                  enabled: !_busy && !_checkingPayment,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Adresa za dostavu',
                    hintText: 'Ulica i broj, poštanski broj i mjesto',
                  ),
                )
              else
                Row(
                  children: [
                    const Icon(Icons.local_shipping_outlined, size: 21),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _address.text,
                        key: const ValueKey('purchase-address-text'),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy || _checkingPayment
                          ? null
                          : () => setState(() => _editingAddress = true),
                      child: const Text('Promijeni'),
                    ),
                  ],
                ),
            ],
            if (!widget.digital)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Prodavač šalje paket na ovu adresu (kurir ili paketomat) i javi ti broj za praćenje.',
                  key: ValueKey('purchase-seller-ships'),
                  style: TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            if (widget.itemCents != null) ...[
              _line('Proizvod (1 kom)', widget.itemCents!, 'purchase-item'),
              _line(
                'Dostava',
                _totalCents - widget.itemCents!,
                'purchase-shipping',
              ),
              const Divider(height: 20),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Ukupno',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                Text(
                  formatCredits(_totalCents / 100),
                  key: const ValueKey('purchase-total'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  key: const ValueKey('purchase-error'),
                  style: TextStyle(color: LoopColors.error),
                ),
              ),
            const SizedBox(height: 18),
            if (_completed)
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline),
                  SizedBox(width: 8),
                  Text('Plaćeno'),
                ],
              )
            else if (widget.embedded &&
                _hasCard &&
                !_loadingCard &&
                !_busy &&
                !_checkingPayment)
              VisionBidSlider(
                key: const ValueKey('purchase-slide'),
                label: 'Plati ${formatCredits(_totalCents / 100)}',
                confirmationKey: (_orderId, _totalCents),
                onConfirm: _pay,
              )
            else
              FilledButton.icon(
                key: const ValueKey('purchase-pay'),
                onPressed: _busy || _loadingCard ? null : _pay,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_outline),
                label: Text(
                  _busy
                      ? 'Obrada…'
                      : !_hasCard
                      ? 'Dodaj karticu'
                      : _checkingPayment
                      ? 'Provjeri plaćanje'
                      : 'Plati ${formatCredits(_totalCents / 100)}',
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Testni način',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: LoopColors.textSecondary),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
    child: Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    ),
  );

  Widget _card({required Widget child, VoidCallback? onTap, Key? key}) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LoopColors.glassBorder),
            ),
            child: child,
          ),
        ),
      );

  Widget _summaryRow(String label, String value, Key key) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 16, color: LoopColors.textSecondary),
          ),
        ),
        Text(
          value,
          key: key,
          style: TextStyle(fontSize: 16, color: LoopColors.textSecondary),
        ),
      ],
    ),
  );

  Widget _pageBody(BuildContext context) {
    final item = widget.itemCents;
    final canPay = !_busy && !_loadingCard && !_completed;
    final addressMissing = !widget.digital && _address.text.trim().isEmpty;
    final lines = [
      for (final l in _address.text.split(',')) l.trim(),
    ].where((l) => l.isNotEmpty).toList();
    return PopScope(
      canPop: !_busy,
      child: Column(
        key: const ValueKey('purchase-confirmation'),
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.image != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 110,
                                height: 132,
                                child: widget.image,
                              ),
                            ),
                          if (widget.image != null) const SizedBox(width: 14),
                          Expanded(
                            child: SizedBox(
                              height: 132,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (widget.subtitle.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        widget.subtitle,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: LoopColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  Text(
                                    formatCredits((item ?? _totalCents) / 100),
                                    key: const ValueKey('purchase-item-price'),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!widget.digital) ...[
                        _section(t('Adresa')),
                        if (_editingAddress || addressMissing)
                          TextField(
                            key: const ValueKey('purchase-address'),
                            controller: _address,
                            enabled: !_busy && !_checkingPayment,
                            minLines: 1,
                            maxLines: 3,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: t('Adresa za dostavu'),
                              hintText: t(
                                'Ulica i broj, poštanski broj i mjesto',
                              ),
                            ),
                          )
                        else
                          _card(
                            key: const ValueKey('purchase-address-card'),
                            onTap: _busy || _checkingPayment
                                ? null
                                : () => setState(() => _editingAddress = true),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (widget.recipient.isNotEmpty)
                                        Text(
                                          widget.recipient,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      Text(
                                        lines.join('\n'),
                                        key: const ValueKey(
                                          'purchase-address-text',
                                        ),
                                        style: TextStyle(
                                          fontSize: 17,
                                          height: 1.4,
                                          color: LoopColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.edit_outlined,
                                  color: LoopColors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        _section(t('Pojedinosti o dostavi')),
                        _card(
                          child: Row(
                            children: [
                              const Icon(Icons.local_shipping_outlined),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  t(
                                    'Prodavač šalje paket na tvoju adresu (kurir ili paketomat) i javlja ti broj za praćenje.',
                                  ),
                                  key: const ValueKey('purchase-seller-ships'),
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      _section(t('Plaćanje')),
                      _card(
                        key: const ValueKey('purchase-card-row'),
                        onTap: _busy || _loadingCard ? null : _addCard,
                        child: Row(
                          children: [
                            const Icon(Icons.credit_card_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _loadingCard
                                    ? t('Provjera kartice…')
                                    : _hasCard
                                    ? '${t('Kartica')} •••• ${_last4 ?? "••••"}'
                                    : t('Dodaj karticu za plaćanje'),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (!_loadingCard)
                              Icon(
                                _hasCard ? Icons.edit_outlined : Icons.add,
                                color: LoopColors.textSecondary,
                              ),
                          ],
                        ),
                      ),
                      _section(t('Sažetak cijene')),
                      _summaryRow(
                        t('Narudžba'),
                        formatCredits((item ?? _totalCents) / 100),
                        const ValueKey('purchase-item'),
                      ),
                      if (item != null)
                        _summaryRow(
                          t('Dostava'),
                          _totalCents - item == 0
                              ? t('Besplatno')
                              : formatCredits((_totalCents - item) / 100),
                          const ValueKey('purchase-shipping'),
                        ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: LoopColors.surface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t(
                                  'Subhasto štiti svaku kupnju. Novac čeka na sigurnom dok ne primiš paket i potvrdiš ga (imaš 2 dana), a ako nešto nije u redu, vraća se tebi.',
                                ),
                                key: const ValueKey('purchase-protection'),
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.shield_outlined,
                              size: 44,
                              color: LoopColors.accent,
                            ),
                          ],
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            _error!,
                            key: const ValueKey('purchase-error'),
                            style: TextStyle(color: LoopColors.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Material(
            color: LoopColors.background,
            child: Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: LoopColors.glassBorder)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                t('Ukupno za plaćanje'),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              formatCredits(_totalCents / 100),
                              key: const ValueKey('purchase-total'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            key: const ValueKey('purchase-pay'),
                            style: FilledButton.styleFrom(
                              backgroundColor: LoopColors.accent,
                              foregroundColor: LoopColors.onAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: canPay ? _pay : null,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    !_hasCard && !_loadingCard
                                        ? t('Dodaj karticu')
                                        : _checkingPayment
                                        ? t('Provjeri plaćanje')
                                        : t('Plati'),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 16,
                              color: LoopColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                t(
                                  'Tvoji podaci o plaćanju su šifrirani i sigurni',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: LoopColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
