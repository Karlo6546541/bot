import 'package:web/web.dart' as web;

/// Mijenja upit u adresi (bez novog unosa u povijesti preglednika i bez
/// diranja stanja koje drži Flutter).
void replaceQuery(String query) {
  final l = web.window.location;
  final url = '${l.pathname}${query.isEmpty ? '' : '?$query'}${l.hash}';
  if ('${l.pathname}${l.search}${l.hash}' == url) return;
  web.window.history.replaceState(web.window.history.state, '', url);
}
