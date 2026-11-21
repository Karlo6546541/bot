import 'package:supabase_flutter/supabase_flutter.dart';

class DeliveryLocation {
  const DeliveryLocation({
    required this.id,
    required this.name,
    required this.address,
    required this.postalCode,
    required this.city,
    required this.country,
    this.isDemo = false,
  });
  final String id, name, address, postalCode, city, country;
  final bool isDemo;
  String get label => [
    name,
    address,
    '$postalCode $city',
  ].where((s) => s.trim().isNotEmpty).join(', ');
  factory DeliveryLocation.fromMap(Map<String, dynamic> data) =>
      DeliveryLocation(
        id: data['id'] as String,
        name: data['name'] as String,
        address: data['address'] as String,
        postalCode: data['postal_code'] as String,
        city: data['city'] as String,
        country: data['country_code'] as String,
        isDemo: data['is_demo'] == true,
      );
}

class DeliveryDestination {
  const DeliveryDestination.courier(this.address) : locker = null;
  const DeliveryDestination.locker(DeliveryLocation location)
    : locker = location,
      address = '';
  final String address;
  final DeliveryLocation? locker;
  String get method => locker == null ? 'courier' : 'boxnow';
  Map<String, dynamic> get data =>
      locker == null ? {'address': address} : {'locker_id': locker!.id};
}

class DeliveryLocationsBackend {
  DeliveryLocationsBackend(this.client);
  final SupabaseClient client;
  Future<List<DeliveryLocation>> search(
    String address, {
    String country = 'HR',
  }) async {
    final data = await client
        .rpc(
          'commerce_search_lockers',
          params: {'p_address': address, 'p_country': country, 'p_limit': 30},
        )
        .timeout(const Duration(seconds: 15));
    return (data as List)
        .map(
          (row) =>
              DeliveryLocation.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }
}
