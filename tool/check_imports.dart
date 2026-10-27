// Enforces the layering rules from the design (§1):
//   (a) packages/prep_core/lib must not import dart:io.
//   (b) a file under app/lib/features/<x>/ must not import another feature <y>.
//   (c) in app/lib, only data/ and platform/ may import dart:io (plan item 105),
//       so a port to another platform only swaps those two layers.
//
// Usage: dart run tool/check_imports.dart   (from the repository root)
import 'dart:io';

final _importRe = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

void main() {
  final violations = <String>[];

  final core = Directory('packages/prep_core/lib');
  if (core.existsSync()) {
    for (final file in _dartFiles(core)) {
      for (final uri in _imports(file)) {
        if (uri == 'dart:io') {
          violations.add('${file.path}: prep_core must not import dart:io');
        }
      }
    }
  }

  final features = Directory('app/lib/features');
  if (features.existsSync()) {
    for (final file in _dartFiles(features)) {
      final own = _featureOf(file.path);
      if (own == null) continue;
      for (final uri in _imports(file)) {
        final target = _targetFeature(file, uri);
        if (target != null && target != own) {
          violations.add('${file.path}: feature "$own" imports feature "$target" ($uri)');
        }
      }
    }
  }

  final app = Directory('app/lib');
  if (app.existsSync()) {
    for (final file in _dartFiles(app)) {
      final rel = _norm(file.path).substring('app/lib/'.length);
      if (rel.startsWith('data/') || rel.startsWith('platform/')) continue;
      if (_imports(file).contains('dart:io')) {
        violations.add('${file.path}: only data/ and platform/ may import dart:io');
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('check_imports: OK');
    return;
  }
  violations.forEach(stderr.writeln);
  stderr.writeln('check_imports: ${violations.length} violation(s)');
  exitCode = 1;
}

Iterable<File> _dartFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

Iterable<String> _imports(File file) sync* {
  for (final line in file.readAsLinesSync()) {
    final m = _importRe.firstMatch(line);
    if (m != null) yield m.group(1)!;
  }
}

String _norm(String p) => p.replaceAll(r'\', '/');

/// Returns the feature name for a path like app/lib/features/<x>/...
String? _featureOf(String path) {
  final parts = _norm(path).split('/');
  final i = parts.indexOf('features');
  if (i < 0 || i + 1 >= parts.length - 1) return null;
  return parts[i + 1];
}

/// Returns the feature an import points at, or null if it is not a feature.
String? _targetFeature(File from, String uri) {
  const pkgPrefix = 'package:prepbelt/features/';
  if (uri.startsWith(pkgPrefix)) {
    return uri.substring(pkgPrefix.length).split('/').first;
  }
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
  final resolved = File(from.parent.uri.resolve(uri).toFilePath()).absolute.path;
  return _featureOf(resolved);
}
