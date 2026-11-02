import 'package:flutter/material.dart';
import '../services/stripe_backend.dart';
import '../services/delivery_locations.dart';
import 'locker_picker.dart';
import '../theme/app_theme.dart';
import 'formatters.dart';

Future<bool> showPurchaseConfirmation(
  BuildContext context,
  PurchaseConfirmationSheet sheet,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      enableDrag: false,
      constraints: const BoxConstraints(maxWidth: 520),
      backgroundColor: LoopColors.background,
      builder: (_) => appThemed(sheet),
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
  });
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
  bool _checkingPayment = false, _editingAddress = false;
  bool _lockerDelivery = false;
  DeliveryLocation? _locker;

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

  Future<void> _pickLocker() async {
    final search = widget.searchLockers;
    if (search == null) {
      setState(
        () => _error =
            'Popis paketomata nije dostupan. Odaberi kurirsku dostavu.',
      );
      return;
    }
    final selected = await showLockerPicker(
      context,
      address: _address.text.trim(),
      search: search,
      selected: _locker,
    );
    if (selected != null && mounted) {
      setState(() {
        _locker = selected;
        _error = null;
      });
    }
  }

  Future<void> _pay() async {
    if (_busy || _loadingCard) return;
    if (!_hasCard) {
      await _addCard();
      return;
    }
    if (!widget.digital && _lockerDelivery && _locker == null) {
      setState(() => _error = 'Odaberi paketomat za dostavu.');
      return;
    }
    if (!widget.digital && !_lockerDelivery && _address.text.trim().isEmpty) {
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
        if (serverTotal != _totalCents) {
          setState(() {
            _totalCents = serverTotal;
            _error = 'Cijena je promijenjena. Potvrdi novi ukupan iznos.';
          });
          return;
        }
      }
      if (!_checkingPayment && !widget.digital) {
        await widget.chooseDelivery(
          _orderId!,
          _lockerDelivery
              ? DeliveryDestination.locker(_locker!)
              : DeliveryDestination.courier(_address.text.trim()),
        );
      }
      if (!mounted) return;
      // Retries always check the same order, including after a lost response.
      _checkingPayment = true;
      final status = await widget.charge(_orderId!, context);
      if (!mounted) return;
      if (status == SavedCardChargeStatus.paid) {
        Navigator.pop(context, true);
      } else {
        setState(
          () => _error = status == SavedCardChargeStatus.processing
              ? 'Plaćanje je u obradi. Provjeri njegov status.'
              : 'Plaćanje nije dovršeno. Možeš pokušati ponovno.',
        );
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('purchase-confirmation'),
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Potvrdi kupnju',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  key: const ValueKey('purchase-close'),
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('delivery-locker'),
                    label: const Text('Paketomat'),
                    selected: _lockerDelivery,
                    onSelected: _busy || _checkingPayment
                        ? null
                        : (_) => setState(() {
                            _lockerDelivery = true;
                            _error = null;
                          }),
                  ),
                  ChoiceChip(
                    key: const ValueKey('delivery-courier'),
                    label: const Text('Kurirska dostava'),
                    selected: !_lockerDelivery,
                    onSelected: _busy || _checkingPayment
                        ? null
                        : (_) => setState(() {
                            _lockerDelivery = false;
                            _error = null;
                          }),
                  ),
                ],
              ),
              if (_lockerDelivery)
                ListTile(
                  key: const ValueKey('purchase-locker'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(_locker?.name ?? 'Odaberi paketomat'),
                  subtitle: Text(
                    _locker == null
                        ? 'Pretraga prema tvojoj adresi, gradu ili poštanskom broju'
                        : '${_locker!.address}, ${_locker!.postalCode} ${_locker!.city}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy || _checkingPayment ? null : _pickLocker,
                )
              else if (_editingAddress || widget.address.trim().isEmpty)
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
                    Expanded(child: Text(_address.text)),
                    TextButton(
                      onPressed: _busy || _checkingPayment
                          ? null
                          : () => setState(() => _editingAddress = true),
                      child: const Text('Promijeni'),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 16),
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
                    : 'Potvrdi i plati ${formatCredits(_totalCents / 100)}',
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
}
