import 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    as impl;

/// Sprema tekstualnu datoteku: na webu je preuzme preglednik, inače ide u
/// mapu Dokumenti. Vraća opis gdje je spremljena.
Future<String> saveTextFile(String fileName, String content) =>
    impl.saveTextFile(fileName, content);
