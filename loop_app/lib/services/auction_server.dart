import 'package:supabase_flutter/supabase_flutter.dart';

/// Online način: aukcije zaključuje poslužitelj (i kad nitko nema otvorenu
/// aplikaciju), a pobjedniku se iznos naplaćuje preko Stripea. Aplikacija
/// samo traži zaključivanje i čita ishod — nikad sama ne upisuje "prodano".
abstract class AuctionServer {
  /// Zaključi aukciju ako je istekla (ili je dosegnut "Kupi odmah").
  Future<void> settle(String auctionId);

  /// Holandska: kupnja po cijeni koju računa poslužitelj (najviše
  /// [maxPrice]). Vraća ID narudžbe koju treba naplatiti.
  Future<String> takeDutch(String auctionId, double maxPrice);
}

class SupabaseAuctionServer implements AuctionServer {
  SupabaseAuctionServer(this.client);
  final SupabaseClient client;

  @override
  Future<void> settle(String auctionId) =>
      client.rpc('auction_settle', params: {'p_id': auctionId});

  @override
  Future<String> takeDutch(String auctionId, double maxPrice) async {
    final row = await client.rpc(
      'auction_take_dutch',
      params: {'p_id': auctionId, 'p_max': maxPrice},
    );
    return (row as Map)['id'] as String;
  }
}

/// Šifra greške poslužitelja (npr. `CARD_REQUIRED`) iz iznimke baze.
String? auctionServerErrorCode(Object error) {
  final text = error is PostgrestException ? error.message : '$error';
  for (final code in const [
    'CARD_REQUIRED',
    'BIDDING_SUSPENDED',
    'ALREADY_SOLD',
    'PRICE_CHANGED',
    'AUCTION_ENDED',
    'OWN_AUCTION',
  ]) {
    if (text.contains(code)) return code;
  }
  return null;
}
