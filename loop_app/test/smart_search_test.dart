import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/services/market_filter.dart';
import 'package:loop_app/services/smart_search.dart';

void main() {
  test('tipfeleri: dulje riječi trpe pogrešku, kratke moraju biti točne', () {
    expect(searchMatches('Apple mobitel 128 GB', ['mobtel']), isTrue);
    expect(searchMatches('Apple mobitel 128 GB', ['mobtiel']), isTrue);
    expect(searchMatches('Nike Air Max tenisice', ['tenicice']), isTrue);
    expect(searchMatches('Pokémon kartica', ['pokemom']), isTrue);
    // "nike" (4 slova) se ne smije proširiti na slične riječi.
    expect(searchMatches('Bike za početnike', ['nike']), isFalse);
    expect(searchMatches('Violina za početnike', ['nike']), isFalse);
  });

  test('sinonimi: telefon nalazi mobitel, patike nalaze tenisice', () {
    expect(searchMatches('Mobiteli iPhone 13', ['telefon']), isTrue);
    expect(searchMatches('Tenisice Adidas', ['patike']), isTrue);
    expect(searchMatches('Pametni sat', ['ura']), isTrue);
    expect(searchMatches('Gitara', ['telefon']), isFalse);
  });

  test('upit: cijena i vrsta se izvlače iz teksta', () {
    var q = SmartQuery.parse('Tenisice do 50 €');
    expect(q.terms, ['tenisice']);
    expect(q.maxPrice, 50);
    expect(q.minPrice, isNull);
    expect(q.priceOk(49.9), isTrue);
    expect(q.priceOk(60), isFalse);

    q = SmartQuery.parse('laptop od 200 do 500');
    expect(q.terms, ['laptop']);
    expect((q.minPrice, q.maxPrice), (200, 500));

    q = SmartQuery.parse('kartice 10-30');
    expect((q.minPrice, q.maxPrice), (10, 30));

    q = SmartQuery.parse('mobitel < 99,5');
    expect(q.maxPrice, 99.5);

    q = SmartQuery.parse('aukcije');
    expect(q.kind, SearchKind.auction);
    expect(q.terms, isEmpty);
    expect(q.isEmpty, isFalse);

    q = SmartQuery.parse('tenisice uživo');
    expect(q.kind, SearchKind.live);
    expect(q.terms, ['tenisice']);

    q = SmartQuery.parse('lego kupi odmah');
    expect(q.kind, SearchKind.buyNow);
    expect(q.terms, ['lego']);

    expect(SmartQuery.parse('  ').isEmpty, isTrue);
  });

  test('prijedlog ispravka za pojmove bez rezultata', () {
    final vocab = ['Mobiteli', 'Tenisice Nike', 'Laptop Lenovo'];
    expect(suggestQuery(['mobtli'], vocab), 'mobiteli');
    expect(suggestQuery(['tenicice', 'nike'], vocab), 'tenisice nike');
    expect(suggestQuery(['laptop'], vocab), isNull);
    expect(suggestQuery(['zzzzzz'], vocab), isNull);
  });
}
