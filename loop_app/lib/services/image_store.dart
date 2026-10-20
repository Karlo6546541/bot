import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Lokalno spremište fotografija predmeta. Odabrana slika se kopira u mapu
/// aplikacije, pa ostaje dostupna i ako korisnik obriše original.
class ImageStore {
  final _picker = ImagePicker();
  final _uuid = const Uuid();

  /// Kamera postoji samo na mobitelu; na Windowsu se bira datoteka.
  bool get canUseCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'loop_images'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Otvara galeriju/kameru i vraća putanje spremljenih kopija
  /// (prazna lista ako korisnik odustane).
  Future<List<String>> pick({bool camera = false, int limit = 4}) async {
    final List<XFile> files;
    if (camera) {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      files = shot == null ? const [] : [shot];
    } else {
      files = await _picker.pickMultiImage(
        maxWidth: 1600,
        imageQuality: 85,
        limit: limit > 1 ? limit : null,
      );
    }
    final dir = await _dir();
    final saved = <String>[];
    for (final f in files.take(limit)) {
      final ext = p.extension(f.path).isEmpty ? '.jpg' : p.extension(f.path);
      final target = p.join(dir.path, '${_uuid.v4()}$ext');
      await File(target).writeAsBytes(await f.readAsBytes());
      saved.add(target);
    }
    return saved;
  }

  /// Briše datoteke; greške (npr. već obrisana datoteka) se ignoriraju.
  Future<void> delete(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      } on FileSystemException {
        // nije kritično za demo
      }
    }
  }

  /// Briše sve spremljene fotografije (koristi se pri resetiranju).
  Future<void> clearAll() async {
    try {
      final dir = await _dir();
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {
      // Nije kritično za demo (npr. nema pristupa mapi ili plugina u testu).
    }
  }
}
