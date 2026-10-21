import 'package:intl/intl.dart';

import '../l10n/tr.dart';

// Hrvatski zapis brojeva: točka za tisućice, zarez za decimale.
// Engleski: zarez za tisućice, točka za decimale.
final _wholeHr = NumberFormat('#,##0', 'hr');
final _decimalHr = NumberFormat('#,##0.00', 'hr');
final _wholeEn = NumberFormat('#,##0', 'en_US');
final _decimalEn = NumberFormat('#,##0.00', 'en_US');
final _dateTimeHr = DateFormat('dd.MM.yyyy. HH:mm', 'en_US');
final _dateTimeEn = DateFormat('MMM d, yyyy HH:mm', 'en_US');

bool get _en => Tr.lang == AppLang.en;

bool _isWhole(double v) => (v * 100).round() % 100 == 0;

/// "1.250" ili "294,50" (decimale samo kad postoje); na engleskom
/// "1,250" i "294.50".
String formatNumber(double value) {
  final whole = _en ? _wholeEn : _wholeHr;
  final decimal = _en ? _decimalEn : _decimalHr;
  return _isWhole(value) ? whole.format(value.round()) : decimal.format(value);
}

/// Riječ uz iznos: "1 kredit", "21 kredit", inače "kredita"
/// (engleski: "1 credit", inače "credits").
String creditsWord(double value) {
  if (_en) {
    return _isWhole(value) && value.round().abs() == 1 ? 'credit' : 'credits';
  }
  if (!_isWhole(value)) return 'kredita';
  final n = value.round().abs();
  return n % 10 == 1 && n % 100 != 11 ? 'kredit' : 'kredita';
}

/// "1.250 kredita", "294,50 kredita", "1 kredit".
String formatCredits(double value) =>
    '${formatNumber(value)} ${creditsWord(value)}';

String formatDateTime(DateTime value) =>
    (_en ? _dateTimeEn : _dateTimeHr).format(value);

/// Iznos u eurima (za kupnju kredita): "49,99 €" / "€49.99".
String formatEuro(double value) =>
    _en ? '€${_decimalEn.format(value)}' : '${_decimalHr.format(value)} €';
