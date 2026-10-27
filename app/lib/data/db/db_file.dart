import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The single database file. On Android this is
/// `files/app_flutter/prepbelt.sqlite` (plan item 55).
Future<File> databaseFile() async =>
    File(p.join((await getApplicationDocumentsDirectory()).path, 'prepbelt.sqlite'));

/// The WAL side files that sit next to [db].
List<File> sideFiles(File db) => [File('${db.path}-wal'), File('${db.path}-shm')];
