import 'package:intl/intl.dart';

final _credits = NumberFormat('#,##0.00', 'en_US');
final _dateTime = DateFormat('dd.MM.yyyy. HH:mm', 'en_US');

/// "1,250.00 LC" — LC = LOOP krediti.
String formatCredits(double value) => '${_credits.format(value)} LC';

/// Samo broj, bez oznake valute.
String formatNumber(double value) => _credits.format(value);

String formatDateTime(DateTime value) => _dateTime.format(value);
