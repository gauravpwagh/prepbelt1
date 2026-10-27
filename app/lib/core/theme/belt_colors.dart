import 'package:flutter/material.dart';
import 'package:prep_core/prep_core.dart';

/// Belt colours (plan item 51).
Color beltColor(Belt belt) => switch (belt) {
      Belt.red => const Color(0xFFC62828),
      Belt.orange => const Color(0xFFEF6C00),
      Belt.yellow => const Color(0xFFF9A825),
      Belt.lightGreen => const Color(0xFF7CB342),
      Belt.green => const Color(0xFF2E7D32),
      Belt.unread => const Color(0xFF9E9E9E),
    };

/// Black or white text on [background], whichever contrasts more. Every
/// belt colour reaches at least 3:1 with one of them.
Color onColor(Color background) {
  double ratio(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  return ratio(background, Colors.white) >= ratio(background, Colors.black)
      ? Colors.white
      : Colors.black;
}
