import 'dart:convert';

import 'package:prep_core/prep_core.dart';

import '../platform/local_files.dart';
import '../platform/share_receiver.dart';

/// What to do with an incoming share (design §8a "Receiving exam files").
sealed class ShareKind {
  const ShareKind();
}

/// A `.prepbelt.json` exam file: open the Import screen.
final class ExamFileShare extends ShareKind {
  const ExamFileShare(this.copy);
  final SharedCopy copy;
}

/// Text, links and PDFs: open the capture sheet.
final class CaptureShare extends ShareKind {
  const CaptureShare(this.share);
  final IncomingShare share;
}

/// Any other file: "Unsupported file".
final class UnsupportedShare extends ShareKind {
  const UnsupportedShare(this.share);
  final IncomingShare share;
}

Future<ShareKind> sortShare(IncomingShare share, LocalFiles files) async {
  if (share.files.length == 1 && (share.text == null || share.text!.trim().isEmpty)) {
    final f = share.files.single;
    if (await isExamFile(f.cachePath, files)) return ExamFileShare(f);
  }
  for (final f in share.files) {
    if (!await _looksPdf(f, files)) return UnsupportedShare(share);
  }
  return CaptureShare(share);
}

Future<bool> _looksPdf(SharedCopy f, LocalFiles files) async {
  final name = (f.name ?? f.cachePath).toLowerCase();
  if (name.endsWith('.pdf')) return true;
  try {
    final bytes = await files.readHead(f.cachePath, 5);
    return utf8.decode(bytes, allowMalformed: true) == '%PDF-';
  } on LocalFileException {
    return false;
  }
}

/// A JSON file of at most 20 MB whose `format` is `prepbelt-exam`.
Future<bool> isExamFile(String path, LocalFiles files) async {
  try {
    if (await files.length(path) > examFileMaxBytes) return false;
    final raw = jsonDecode(await files.readString(path));
    return raw is Map && raw['format'] == examFormatId;
  } on FormatException {
    return false;
  } on LocalFileException {
    return false;
  }
}
