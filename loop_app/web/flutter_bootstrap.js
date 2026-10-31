{{flutter_js}}
{{flutter_build_config}}

// Oznaka verzije na main.dart.js: nova objava se nikad ne uzima iz cachea.
(function () {
  var v = String({{flutter_service_worker_version}});
  (_flutter.buildConfig.builds || []).forEach(function (b) {
    if (b.mainJsPath && b.mainJsPath.indexOf('?') < 0) {
      b.mainJsPath += '?v=' + v;
    }
  });
})();

_flutter.loader.load();
