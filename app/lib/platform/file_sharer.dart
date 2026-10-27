import 'package:share_plus/share_plus.dart';

/// The system share sheet, for exported exam files and logs.
abstract interface class FileSharer {
  /// Shares the local file at [path].
  Future<void> shareFile(String path, {String? subject});
}

class SystemFileSharer implements FileSharer {
  const SystemFileSharer();

  @override
  Future<void> shareFile(String path, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], subject: subject));
  }
}
