import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../l10n/tr.dart';
import '../models/device.dart';
import 'storage_service.dart';
import 'trade_service.dart';

/// Odabrana datoteka (prije spremanja).
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;

  int get size => bytes.length;
}

/// Datoteke digitalnih proizvoda (3D modeli, softver, e-knjige…).
///
/// - **online** (Supabase): PRIVATNI bucket `loop-files`, put
///   `<idPredmeta>/<datoteka>`. Pravila u bazi dopuštaju preuzimanje samo
///   vlasniku i kupcima (vidi `supabase/schema.sql`).
/// - **lokalno, web**: sadržaj u lokalnom boxu (preglednik).
/// - **lokalno, Windows/mobitel**: kopija u mapi aplikacije.
///
/// Referenca u [DigitalFile.ref] počinje sa `sb:`, `local:` ili `file:`.
class FileStore {
  FileStore(this._storage, {this.client});

  final StorageService _storage;
  final SupabaseClient? client;
  final _uuid = const Uuid();

  static const bucket = 'loop-files';

  bool get _online => client != null;

  /// Najveća datoteka: online 25 MB; lokalno na webu 8 MB (preglednik).
  int get maxBytes =>
      _online ? 25 * 1024 * 1024 : (kIsWeb ? 8 : 50) * 1024 * 1024;

  /// Dopuštene vrste (bez izvršnih datoteka — softver ide kao .zip).
  static const allowedExtensions = [
    // 3D
    'stl', 'obj', '3mf', 'step', 'stp', 'gcode', 'blend', 'fbx', 'glb',
    // arhive (softver, paketi)
    'zip', '7z', 'rar',
    // dokumenti / e-knjige
    'pdf', 'epub', 'mobi', 'txt', 'md',
    // grafika / predlošci / fontovi
    'png', 'jpg', 'jpeg', 'svg', 'psd', 'ai', 'xd', 'fig', 'ttf', 'otf',
    'xlsx', 'docx', 'pptx',
    // zvuk
    'mp3', 'wav', 'flac', 'ogg', 'mid',
  ];

  /// Otvara odabir datoteke (`null` ako korisnik odustane).
  Future<PickedFile?> pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (files.isEmpty) return null;
    final f = files.first;
    final Uint8List bytes;
    try {
      bytes = await f.xFile.readAsBytes();
    } catch (_) {
      throw TradeException(t('Datoteku nije moguće pročitati.'));
    }
    return PickedFile(f.name, bytes);
  }

  /// Greška ili `null` ako je datoteka ispravna.
  String? validate(PickedFile f) {
    final dot = f.name.lastIndexOf('.');
    final ext = dot < 0 ? '' : f.name.substring(dot + 1).toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      return t('Vrsta datoteke .{0} nije dopuštena.', [ext]);
    }
    if (f.size == 0) return t('Datoteka je prazna.');
    if (f.size > maxBytes) {
      return t('Datoteka je prevelika (najviše {0} MB).', [
        maxBytes ~/ (1024 * 1024),
      ]);
    }
    return null;
  }

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Sprema datoteku za predmet [deviceId].
  Future<DigitalFile> save(String deviceId, PickedFile f) async {
    final error = validate(f);
    if (error != null) throw TradeException(error);
    final name = '${_uuid.v4().substring(0, 8)}_${_safeName(f.name)}';
    final String ref;
    if (_online) {
      final path = '$deviceId/$name';
      await client!.storage
          .from(bucket)
          .uploadBinary(
            path,
            f.bytes,
            fileOptions: const FileOptions(
              contentType: 'application/octet-stream',
              upsert: false,
            ),
          );
      ref = 'sb:$path';
    } else if (kIsWeb) {
      final key = '$deviceId/$name';
      await _storage.putFileBytes(key, f.bytes);
      ref = 'local:$key';
    } else {
      final dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'loop_files'),
      );
      if (!dir.existsSync()) await dir.create(recursive: true);
      final target = p.join(dir.path, '${deviceId}_$name');
      await File(target).writeAsBytes(f.bytes);
      ref = 'file:$target';
    }
    return DigitalFile(
      ref: ref,
      name: f.name,
      size: f.size,
      uploadedAt: DateTime.now(),
    );
  }

  /// Sadržaj datoteke (online: samo vlasnik i kupci — provjerava baza).
  Future<Uint8List> read(DigitalFile file) async {
    try {
      final ref = file.ref;
      if (ref.startsWith('sb:')) {
        if (!_online) throw StateError('offline');
        return await client!.storage.from(bucket).download(ref.substring(3));
      }
      if (ref.startsWith('local:')) {
        final bytes = _storage.fileBytes(ref.substring(6));
        if (bytes == null) throw StateError('missing');
        return bytes;
      }
      if (ref.startsWith('file:') && !kIsWeb) {
        return await File(ref.substring(5)).readAsBytes();
      }
      throw StateError('unknown ref');
    } on StorageException catch (e) {
      if (e.statusCode == '400' ||
          e.statusCode == '403' ||
          e.statusCode == '404') {
        throw TradeException(
          t('Datoteka nije dostupna (nemaš pristup ili je obrisana).'),
        );
      }
      rethrow;
    } on StateError {
      throw TradeException(t('Datoteka nije dostupna na ovom uređaju.'));
    } on FileSystemException {
      throw TradeException(t('Datoteka nije dostupna na ovom uređaju.'));
    }
  }

  Future<void> delete(DigitalFile file) async {
    try {
      final ref = file.ref;
      if (ref.startsWith('sb:') && _online) {
        await client!.storage.from(bucket).remove([ref.substring(3)]);
      } else if (ref.startsWith('local:')) {
        await _storage.deleteFileBytes(ref.substring(6));
      } else if (ref.startsWith('file:') && !kIsWeb) {
        final f = File(ref.substring(5));
        if (f.existsSync()) await f.delete();
      }
    } catch (_) {
      // nije kritično
    }
  }
}
