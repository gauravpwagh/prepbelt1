import 'dart:convert';
import 'dart:io';

import 'package:prep_core/prep_core.dart';

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

Future<ShareKind> sortShare(IncomingShare share) async {
  if (share.files.length == 1 && (share.text == null || share.text!.trim().isEmpty)) {
    final f = share.files.single;
    if (await isExamFile(File(f.cachePath))) return ExamFileShare(f);
  }
  final allPdf = share.files.every((f) => _looksPdf(f));
  return allPdf ? CaptureShare(share) : UnsupportedShare(share);
}

bool _looksPdf(SharedCopy f) {
  final name = (f.name ?? f.cachePath).toLowerCase();
  if (name.endsWith('.pdf')) return true;
  try {
    final head = File(f.cachePath).openSync()..setPositionSync(0);
    final bytes = head.readSync(5);
    head.closeSync();
    return utf8.decode(bytes, allowMalformed: true) == '%PDF-';
  } on FileSystemException {
    return false;
  }
}

/// A JSON file of at most 20 MB whose `format` is `prepbelt-exam`.
Future<bool> isExamFile(File file) async {
  try {
    if (await file.length() > examFileMaxBytes) return false;
    final raw = jsonDecode(await file.readAsString());
    return raw is Map && raw['format'] == examFormatId;
  } on FormatException {
    return false;
  } on FileSystemException {
    return false;
  }
}
