import 'package:prep_core/prep_core.dart';

/// The only place that reads the system time.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}
