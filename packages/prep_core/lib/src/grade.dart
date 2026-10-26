/// How well a review went. Definitions are shown on the grade sheet (§10).
enum Grade {
  forgot('forgot', 'Forgot', "Couldn't recall the main points."),
  shaky('shaky', 'Shaky', 'Recalled some, with gaps or after peeking.'),
  solid('solid', 'Solid', 'Could explain it without looking.');

  const Grade(this.key, this.label, this.definition);

  final String key;
  final String label;
  final String definition;

  static Grade fromKey(String key) => Grade.values.firstWhere(
        (g) => g.key == key,
        orElse: () => throw ArgumentError.value(key, 'key', 'Unknown grade'),
      );
}

/// Extra line on the grade sheet for PYQ practice tasks (decision D1).
const pyqGuidance =
    'Grade on the questions you got wrong last time, or on a fresh set.';
