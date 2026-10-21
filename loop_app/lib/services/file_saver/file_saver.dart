import 'dart:convert';
import 'dart:typed_data';

import 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    as impl;

/// Sprema tekstualnu datoteku: na webu je preuzme preglednik, inače ide u
/// mapu Preuzimanja/Dokumenti. Vraća opis gdje je spremljena.
Future<String> saveTextFile(String fileName, String content) =>
    impl.saveBytesFile(fileName, utf8.encode(content), 'application/json');

/// Isto za bilo koju datoteku (npr. preuzeti 3D model).
Future<String> saveBytesFile(
  String fileName,
  Uint8List bytes, {
  String mime = 'application/octet-stream',
}) => impl.saveBytesFile(fileName, bytes, mime);
