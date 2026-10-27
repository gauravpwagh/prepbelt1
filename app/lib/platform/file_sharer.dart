import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// The system share sheet, for exported exam files and logs.
abstract interface class FileSharer {
  Future<void> shareFile(File file, {String? subject});
}

class SystemFileSharer implements FileSharer {
  const SystemFileSharer();

  @override
  Future<void> shareFile(File file, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: subject));
  }
}
