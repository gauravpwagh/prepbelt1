// Coverage gate (implementation plan item 4).
//
// Usage: dart run tool/coverage_gate.dart <prep_core lcov.info> [<app lcov.info>]
//
// SF: paths are normalised to repository-relative paths:
//   * absolute paths containing "packages/prep_core/" keep the part from there;
//   * relative paths from the app lcov get "app/" prepended.
import 'dart:io';

const _strictFiles = [
  'packages/prep_core/lib/src/belt_policy.dart',
  'packages/prep_core/lib/src/effective_due.dart',
  'packages/prep_core/lib/src/planner.dart',
  'packages/prep_core/lib/src/catch_up.dart',
  'packages/prep_core/lib/src/exam_package.dart',
];

class _Cov {
  int found = 0;
  int hit = 0;
  double get pct => found == 0 ? 100 : 100 * hit / found;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: coverage_gate.dart <prep_core lcov> [<app lcov>]');
    exitCode = 64;
    return;
  }
  final files = <String, _Cov>{};
  _read(args[0], files, isApp: false);
  if (args.length > 1) _read(args[1], files, isApp: true);

  final failures = <String>[];
  void gate(String label, Iterable<String> paths, double min) {
    final total = _Cov();
    for (final p in paths) {
      total
        ..found += files[p]!.found
        ..hit += files[p]!.hit;
    }
    final ok = total.pct >= min;
    stdout.writeln('${ok ? 'PASS' : 'FAIL'}  ${total.pct.toStringAsFixed(1).padLeft(5)}%  '
        '(min ${min.toStringAsFixed(0)}%)  $label');
    if (!ok) failures.add(label);
  }

  gate('packages/prep_core/lib',
      files.keys.where((p) => p.startsWith('packages/prep_core/lib/')), 90);
  for (final f in _strictFiles) {
    if (files.containsKey(f)) gate(f, [f], 100);
  }
  final appFiles = files.keys.where((p) => p.startsWith('app/lib/application/'));
  if (appFiles.isNotEmpty) gate('app/lib/application', appFiles, 80);

  if (failures.isNotEmpty) exitCode = 1;
}

void _read(String path, Map<String, _Cov> out, {required bool isApp}) {
  String? current;
  for (final line in File(path).readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      current = _normalise(line.substring(3), isApp: isApp);
      out.putIfAbsent(current, _Cov.new);
    } else if (line.startsWith('LF:') && current != null) {
      out[current]!.found += int.parse(line.substring(3));
    } else if (line.startsWith('LH:') && current != null) {
      out[current]!.hit += int.parse(line.substring(3));
    } else if (line == 'end_of_record') {
      current = null;
    }
  }
}

String _normalise(String sf, {required bool isApp}) {
  final p = sf.replaceAll(r'\', '/');
  const marker = 'packages/prep_core/';
  final i = p.indexOf(marker);
  if (i >= 0) return p.substring(i);
  if (isApp && !p.startsWith('/')) return 'app/$p';
  final j = p.indexOf('/app/lib/');
  if (j >= 0) return p.substring(j + 1);
  return p;
}
