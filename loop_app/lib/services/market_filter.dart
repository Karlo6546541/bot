import '../models/device.dart';
import 'fee.dart';

/// Filteri Marketa, odvojeni od UI-ja kako bi se ponašanje moglo testirati.
class MarketFilter {
  const MarketFilter({
    this.query = '',
    this.condition,
    this.minPrice,
    this.maxPrice,
    this.onlyAffordable = false,
    this.credits = 0,
  });

  final String query;
  final DeviceCondition? condition;
  final double? minPrice;
  final double? maxPrice;
  final bool onlyAffordable;
  final double credits;

  bool matches(Device device) {
    final price = device.askPrice;
    if (condition != null && device.condition != condition) return false;
    if (minPrice != null && price < minPrice!) return false;
    if (maxPrice != null && price > maxPrice!) return false;
    // Kupac plaća i 2% naknade, ne samo prikazanu cijenu.
    if (onlyAffordable && buyTotal(price) > credits) return false;

    final terms = normalizeSearch(
      query,
    ).split(RegExp(r'\s+')).where((term) => term.isNotEmpty);
    final searchable = normalizeSearch(
      [
        device.name,
        device.model,
        device.description,
        device.category.label,
        device.category.singular,
        device.section.label,
        device.condition.label,
      ].join(' '),
    );
    return terms.every(searchable.contains);
  }
}

/// Hrvatska dijakritika, više uzastopnih razmaka i veličina slova
/// ne smiju spriječiti pronalazak oglasa.
String normalizeSearch(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[čć]'), 'c')
    .replaceAll('đ', 'd')
    // "dj" se često piše umjesto "đ" ("medjed" = "međed").
    .replaceAll('dj', 'd')
    .replaceAll('š', 's')
    .replaceAll('ž', 'z')
    .replaceAll(RegExp('[áàâä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .trim();
