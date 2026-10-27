import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Loads the full time-zone database and makes [id] the local zone. The full
/// set matters: Android still reports legacy names such as "Asia/Calcutta",
/// which the smaller default set lacks. Returns the zone in use, or "UTC"
/// when [id] is unknown.
String setLocalTimeZone(String? id) {
  tzdata.initializeTimeZones();
  if (id != null && tz.timeZoneDatabase.locations.containsKey(id)) {
    tz.setLocalLocation(tz.getLocation(id));
    return id;
  }
  tz.setLocalLocation(tz.UTC);
  return 'UTC';
}
