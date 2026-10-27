import 'defaults.dart';

/// A task split one part at a time (design D17, §10b).
enum SplitAsIGo {
  open('open'),
  done('done');

  const SplitAsIGo(this.key);
  final String key;

  static SplitAsIGo fromKey(String key) => values.firstWhere((k) => k.key == key,
      orElse: () => throw ArgumentError.value(key, 'key', 'Unknown split-as-I-go state'));
}

final _range = RegExp(r'^(.*?)(\d+)(\s*[–-]\s*)(\d+)(\D*)$');
final _lastNumber = RegExp(r'^(.*\D)?(\d+)(\D*)$');

/// The pre-filled title of the next part, from the titles of the parts so
/// far (design §10b): "pp. 21–40" → "pp. 41–60", "Ch 3" → "Ch 4", and
/// "Part {n+1}" otherwise.
String nextPartTitle(List<String> partTitles) {
  final fallback = 'Part ${partTitles.length + 1}';
  if (partTitles.isEmpty) return fallback;
  final last = partTitles.last.trim();
  final r = _range.firstMatch(last);
  if (r != null) {
    final a = int.parse(r[2]!), b = int.parse(r[4]!);
    if (b >= a) return '${r[1]}${b + 1}${r[3]}${2 * b - a + 1}${r[5]}';
  }
  final n = _lastNumber.firstMatch(last);
  if (n != null) return '${n[1] ?? ''}${int.parse(n[2]!) + 1}${n[3]}';
  return fallback;
}

/// A part's base time: the minutes studied, kept within 10–50.
int partBaseMinutes(int minutes) => minutes.clamp(Defaults.baseMin, Defaults.baseMax);
