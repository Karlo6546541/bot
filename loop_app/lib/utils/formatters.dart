import 'package:intl/intl.dart';

// Hrvatski zapis brojeva: točka za tisućice, zarez za decimale.
final _whole = NumberFormat('#,##0', 'hr');
final _decimal = NumberFormat('#,##0.00', 'hr');
final _dateTime = DateFormat('dd.MM.yyyy. HH:mm', 'en_US');

bool _isWhole(double v) => (v * 100).round() % 100 == 0;

/// "1.250" ili "294,50" (decimale samo kad postoje).
String formatNumber(double value) =>
    _isWhole(value) ? _whole.format(value.round()) : _decimal.format(value);

/// Riječ uz iznos: "1 kredit", "21 kredit", inače "kredita".
String creditsWord(double value) {
  if (!_isWhole(value)) return 'kredita';
  final n = value.round().abs();
  return n % 10 == 1 && n % 100 != 11 ? 'kredit' : 'kredita';
}

/// "1.250 kredita", "294,50 kredita", "1 kredit".
String formatCredits(double value) =>
    '${formatNumber(value)} ${creditsWord(value)}';

String formatDateTime(DateTime value) => _dateTime.format(value);

/// Iznos u eurima (za kupnju kredita): "49,99 €".
String formatEuro(double value) => '${_decimal.format(value)} €';
