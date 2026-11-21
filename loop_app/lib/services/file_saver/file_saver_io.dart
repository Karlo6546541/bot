import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> saveBytesFile(
  String fileName,
  Uint8List bytes,
  String mime,
) async {
  Directory dir;
  try {
    dir =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
  } catch (_) {
    dir = await getApplicationDocumentsDirectory();
  }
  final file = File(p.join(dir.path, fileName));
  await file.writeAsBytes(bytes);
  return file.path;
}
