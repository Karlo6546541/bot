import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> saveTextFile(String fileName, String content) async {
  Directory dir;
  try {
    dir =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
  } catch (_) {
    dir = await getApplicationDocumentsDirectory();
  }
  final file = File(p.join(dir.path, fileName));
  await file.writeAsString(content);
  return file.path;
}
