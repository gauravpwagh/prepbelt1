/// The belt ladder (design §3, scheduler version 1).
///
/// `interval` is the review gap after reaching the belt with Solid;
/// `shakyInterval` is `ceil(interval / 2)` with a minimum of 1.
enum Belt {
  unread('unread', 0, null, null, 'Unread'),
  red('red', 1, 1, 1, 'Red'),
  orange('orange', 2, 3, 2, 'Orange'),
  yellow('yellow', 3, 7, 4, 'Yellow'),
  lightGreen('light_green', 4, 16, 8, 'Light green'),
  green('green', 5, 35, 18, 'Green');

  const Belt(this.key, this.step, this.interval, this.shakyInterval, this.label);

  /// Stable string stored in the database and in exam files. Never renumber.
  final String key;

  /// 0 for Unread, 1 (Red) … 5 (Green). Shown as "Orange · 2/5".
  final int step;
  final int? interval;
  final int? shakyInterval;
  final String label;

  static const int topStep = 5;

  /// One belt higher; Green stays Green. Unread goes to Red.
  Belt up() => this == green ? green : Belt.values[index + 1];

  /// One belt lower; Red stays Red. Unread stays Unread.
  Belt down() => (this == unread || this == red) ? this : Belt.values[index - 1];

  static Belt fromKey(String key) => Belt.values.firstWhere(
        (b) => b.key == key,
        orElse: () => throw ArgumentError.value(key, 'key', 'Unknown belt'),
      );
}
