import 'package:flutter/material.dart';

import '../format.dart';

class MinutesText extends StatelessWidget {
  const MinutesText(this.minutes, {super.key, this.style});

  final int minutes;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(formatMinutes(minutes),
      style: style ?? Theme.of(context).textTheme.bodySmall);
}
