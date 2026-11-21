import 'boxnow.dart';

/// Izvan preglednika nema BOX NOW karte (koristi se popis paketomata).
bool get boxNowAvailable => false;

Future<BoxNowPick> boxNowPick(
  String partnerId,
  String scriptUrl,
  String language,
) async => const BoxNowUnavailable();

void closeMaps() {}

Future<BoxNowPick> glsPick(String scriptUrl, String country) async =>
    const BoxNowUnavailable();

Future<BoxNowPick> dpdPick(String url, String country) async =>
    const BoxNowUnavailable();
