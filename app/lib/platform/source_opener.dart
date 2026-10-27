// Opening a task's source in another app (design §7, plan item 68).
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:prep_core/prep_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/db/app_database.dart';
import '../data/db/converters.dart';
import 'folder_access.dart';

enum OpenResult { ok, notFound, noApp }

abstract interface class SourceOpener {
  /// `not_linked` sources (printed books, other devices) open nothing and
  /// return [OpenResult.ok].
  Future<OpenResult> open(SourceRow source);
}

/// Used until folder access and intents are wired (and in tests).
class NoopSourceOpener implements SourceOpener {
  const NoopSourceOpener();

  @override
  Future<OpenResult> open(SourceRow source) async => OpenResult.ok;
}

/// Opens files with `ACTION_VIEW` on their content URI (read permission
/// granted to the viewer) and links with `url_launcher` (plan item 68).
class IntentSourceOpener implements SourceOpener {
  IntentSourceOpener(this._folders, {required Future<String?> Function(String folderId) treeUriOf})
      : _treeUriOf = treeUriOf;

  final FolderAccess _folders;
  final Future<String?> Function(String folderId) _treeUriOf;

  static const _flagGrantRead = 0x00000001; // FLAG_GRANT_READ_URI_PERMISSION
  static const _flagNewTask = 0x10000000; // FLAG_ACTIVITY_NEW_TASK

  @override
  Future<OpenResult> open(SourceRow s) async {
    if (s.url != null) {
      final uri = Uri.tryParse(s.url!);
      if (uri == null) return OpenResult.noApp;
      try {
        return await launchUrl(uri, mode: LaunchMode.externalApplication)
            ? OpenResult.ok
            : OpenResult.noApp;
      } on PlatformException {
        return OpenResult.noApp;
      }
    }
    if (s.folderId == null || s.relativePath == null) {
      // Not on the phone (printed book, another device) or not linked yet.
      return s.linkStatus == LinkStatus.ok ? OpenResult.notFound : OpenResult.ok;
    }
    String? docUri;
    try {
      final tree = await _treeUriOf(s.folderId!);
      if (tree == null) return OpenResult.notFound;
      docUri = await _folders.resolve(tree, s.relativePath!);
    } on FolderException {
      return OpenResult.notFound;
    }
    if (docUri == null) return OpenResult.notFound;

    final intent = AndroidIntent(
      action: 'action_view',
      data: docUri,
      type: s.sourceType == SourceType.pdf ? 'application/pdf' : '*/*',
      flags: const [_flagGrantRead, _flagNewTask],
    );
    try {
      if (await intent.canResolveActivity() != true) return OpenResult.noApp;
      await intent.launch();
      return OpenResult.ok;
    } on PlatformException {
      return OpenResult.noApp;
    }
  }
}
