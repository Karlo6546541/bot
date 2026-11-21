import 'storage_service.dart';

/// Veličina otpremnice za ispis.
enum LabelSize { a6, a4 }

/// Zadane postavke otpremnice prodavača (vrijede za sve buduće
/// otpremnice): veličina i popis sadržaja u paketu. Spremaju se na uređaju.
class LabelOptions {
  const LabelOptions({this.size = LabelSize.a6, this.packingList = true});

  final LabelSize size;

  /// Na otpremnici je i popis sadržaja paketa (packing slip).
  final bool packingList;

  static String _key(String? userId) => 'labelOptions:${userId ?? 'guest'}';

  static LabelOptions of(StorageService storage, String? userId) {
    final m = storage.sessionValue(_key(userId));
    if (m is! Map) return const LabelOptions();
    return LabelOptions(
      size: LabelSize.values.firstWhere(
        (v) => v.name == m['size'],
        orElse: () => LabelSize.a6,
      ),
      packingList: m['packingList'] != false,
    );
  }

  Future<void> save(StorageService storage, String? userId) =>
      storage.setSessionValue(_key(userId), {
        'size': size.name,
        'packingList': packingList,
      });

  LabelOptions copyWith({LabelSize? size, bool? packingList}) => LabelOptions(
    size: size ?? this.size,
    packingList: packingList ?? this.packingList,
  );
}
