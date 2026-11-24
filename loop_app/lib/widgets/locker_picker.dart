import 'dart:async';
import 'package:flutter/material.dart';
import '../services/delivery_locations.dart';
import '../theme/app_theme.dart';

Future<DeliveryLocation?> showLockerPicker(
  BuildContext context, {
  required String address,
  required Future<List<DeliveryLocation>> Function(String) search,
  DeliveryLocation? selected,
}) => showModalBottomSheet<DeliveryLocation>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 560),
  backgroundColor: LoopColors.background,
  builder: (_) => appThemed(
    LockerPicker(address: address, search: search, selected: selected),
  ),
);

class LockerPicker extends StatefulWidget {
  const LockerPicker({
    super.key,
    required this.address,
    required this.search,
    this.selected,
  });
  final String address;
  final DeliveryLocation? selected;
  final Future<List<DeliveryLocation>> Function(String) search;
  @override
  State<LockerPicker> createState() => _LockerPickerState();
}

class _LockerPickerState extends State<LockerPicker> {
  late final TextEditingController _query = TextEditingController(
    text: widget.address,
  );
  Timer? _debounce;
  int _request = 0;
  bool _loading = true;
  String? _error;
  List<DeliveryLocation> _locations = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    // Invalidate an older response immediately, even during the debounce.
    _request++;
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.search(_query.text.trim());
      if (!mounted || request != _request) return;
      setState(() => _locations = rows);
    } catch (_) {
      if (mounted && request == _request) {
        setState(
          () => _error =
              'Popis paketomata nije dostupan. Pokušaj ponovno ili odaberi kurira.',
        );
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Odaberi paketomat',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            TextField(
              key: const ValueKey('locker-search'),
              controller: _query,
              onChanged: _changed,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                _debounce?.cancel();
                _load();
              },
              decoration: InputDecoration(
                labelText: 'Grad, poštanski broj ili adresa',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Prikaži sve',
                  onPressed: () {
                    _query.clear();
                    _changed('');
                  },
                  icon: const Icon(Icons.clear),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Pokušaj ponovno'),
                    ),
                  ],
                ),
              ),
            if (!_loading && _error == null && _locations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Nema paketomata za ovu pretragu. Upiši drugi grad ili odaberi kurirsku dostavu.',
                ),
              ),
            Expanded(
              child: ListView.separated(
                key: const ValueKey('locker-results'),
                itemCount: _loading || _error != null ? 0 : _locations.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final location = _locations[index];
                  return ListTile(
                    key: ValueKey('delivery-location-${location.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(location.name),
                    subtitle: Text(
                      '${location.address}\n${location.postalCode} ${location.city}${location.isDemo ? ' · Demo lokacija' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: Icon(
                      widget.selected?.id == location.id
                          ? Icons.check_circle
                          : Icons.chevron_right,
                    ),
                    onTap: () => Navigator.pop(context, location),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
