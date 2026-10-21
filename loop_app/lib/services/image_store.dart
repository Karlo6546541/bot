import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Spremište fotografija predmeta. Tri načina rada:
/// - **online** (Supabase): slika se šalje u Storage bucket `loop-images`,
///   a uz predmet se sprema javni URL — vide je svi testeri;
/// - **web bez baze**: smanjena slika se sprema kao `data:` URL (u pregledniku);
/// - **Windows/mobitel bez baze**: kopija u mapi aplikacije (putanja datoteke).
///
/// Što je spremljeno u `Device.imagePaths` prepoznaje [PhotoSource].
class ImageStore {
  ImageStore({this.client});

  /// Supabase klijent kad je online baza postavljena.
  final SupabaseClient? client;

  final _picker = ImagePicker();
  final _uuid = const Uuid();

  static const bucket = 'loop-images';

  /// Kamera: na mobitelu, i na webu (preglednik na mobitelu otvara kameru
  /// izravno; na računalu umjesto toga ponudi odabir datoteke).
  /// Windows aplikacija nema podršku za kameru.
  bool get canUseCamera => kIsWeb || Platform.isAndroid || Platform.isIOS;

  /// Fotografije rade svugdje (na webu kao data: URL ili preko Supabasea).
  bool get supported => true;

  bool get _online => client != null;

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'loop_images'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Otvara galeriju/kameru i vraća reference spremljenih slika
  /// (prazna lista ako korisnik odustane).
  Future<List<String>> pick({bool camera = false, int limit = 4}) async {
    // Bez online baze na webu slike idu u preglednik — manje i jače
    // komprimirane, da stanu u lokalnu pohranu.
    final small = kIsWeb && !_online;
    final maxWidth = small ? 900.0 : 1600.0;
    final quality = small ? 70 : 85;

    final List<XFile> files;
    if (camera) {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxWidth,
        imageQuality: quality,
      );
      files = shot == null ? const [] : [shot];
    } else {
      files = await _picker.pickMultiImage(
        maxWidth: maxWidth,
        imageQuality: quality,
        limit: limit > 1 ? limit : null,
      );
    }

    final saved = <String>[];
    for (final f in files.take(limit)) {
      saved.add(await _save(f));
    }
    return saved;
  }

  Future<String> _save(XFile f) async {
    final bytes = await f.readAsBytes();
    final mime = f.mimeType ?? _mimeFromName(f.name);
    final ext = _extFor(mime);

    if (_online) {
      final path = '${_uuid.v4()}$ext';
      await client!.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      return client!.storage.from(bucket).getPublicUrl(path);
    }
    if (kIsWeb) {
      return 'data:$mime;base64,${base64Encode(bytes)}';
    }
    final target = p.join((await _dir()).path, '${_uuid.v4()}$ext');
    await File(target).writeAsBytes(bytes);
    return target;
  }

  static String _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static String _extFor(String mime) => switch (mime) {
    'image/png' => '.png',
    'image/webp' => '.webp',
    'image/gif' => '.gif',
    _ => '.jpg',
  };

  /// Briše slike; greške (npr. već obrisano) se ignoriraju.
  Future<void> delete(Iterable<String> refs) async {
    for (final ref in refs) {
      try {
        switch (PhotoSource.of(ref)) {
          case PhotoSource.network:
            final path = storagePathOf(ref);
            if (path != null && _online) {
              await client!.storage.from(bucket).remove([path]);
            }
          case PhotoSource.data:
            break; // dio zapisa predmeta, nema što brisati
          case PhotoSource.file:
            if (!kIsWeb) {
              final f = File(ref);
              if (f.existsSync()) await f.delete();
            }
        }
      } catch (_) {
        // nije kritično za demo
      }
    }
  }

  /// Briše sve spremljene fotografije (pri resetiranju demo podataka).
  Future<void> clearAll() async {
    try {
      if (_online) {
        final files = await client!.storage.from(bucket).list();
        if (files.isNotEmpty) {
          await client!.storage.from(bucket).remove([
            for (final f in files) f.name,
          ]);
        }
      } else if (!kIsWeb) {
        final dir = await _dir();
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    } catch (_) {
      // Nije kritično za demo (npr. nema pristupa ili plugina u testu).
    }
  }

  /// Iz javnog URL-a Supabase Storagea izvlači putanju datoteke u bucketu.
  static String? storagePathOf(String url) {
    const marker = '/storage/v1/object/public/$bucket/';
    final i = url.indexOf(marker);
    return i < 0 ? null : url.substring(i + marker.length);
  }
}

/// Vrsta reference na sliku spremljene uz predmet.
enum PhotoSource {
  network,
  data,
  file;

  static PhotoSource of(String ref) => ref.startsWith('http')
      ? network
      : ref.startsWith('data:')
      ? data
      : file;
}
