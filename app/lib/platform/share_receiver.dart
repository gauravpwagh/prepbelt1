// Share to PrepBelt (design §7, plan item 70).
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'device_status.dart';

/// The share plugin's temporary cache copy of a shared file.
class SharedCopy {
  const SharedCopy(this.cachePath, this.name, this.size);
  final String cachePath;

  /// Null when the sending app gave no usable name.
  final String? name;
  final int? size;

  Future<void> delete() async {
    try {
      await File(cachePath).delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}

class IncomingShare {
  const IncomingShare({this.text, this.subject, this.files = const []});
  final String? text;
  final String? subject;
  final List<SharedCopy> files;

  bool get isEmpty => (text == null || text!.trim().isEmpty) && files.isEmpty;

  /// Deletes every cache copy; the app never keeps shared files.
  Future<void> discardFiles() async {
    for (final f in files) {
      await f.delete();
    }
  }
}

abstract interface class ShareReceiver {
  Stream<IncomingShare> get shares;
}

final _unknownName = RegExp(r'^FILE_\d+\.');

/// Built on `receive_sharing_intent`, which copies each shared file into the
/// app cache. A single SEND with both a PDF and text delivers only the file
/// (a plugin limitation).
class IntentShareReceiver implements ShareReceiver {
  IntentShareReceiver();

  final _plugin = ReceiveSharingIntent.instance;
  StreamController<IncomingShare>? _controller;

  @override
  Stream<IncomingShare> get shares {
    final c = _controller ??= StreamController<IncomingShare>.broadcast(onListen: _start);
    return c.stream;
  }

  Future<void> _start() async {
    try {
      await _deliver(await _plugin.getInitialMedia());
    } on MissingPluginException {
      return;
    }
    _plugin.getMediaStream().listen(_deliver, onError: (Object _) {});
  }

  Future<void> _deliver(List<SharedMediaFile> media) async {
    if (media.isEmpty) return;
    String? subject;
    try {
      subject = await deviceChannel.invokeMethod<String>('takeShareSubject');
    } on PlatformException {
      subject = null;
    } on MissingPluginException {
      subject = null;
    }
    final texts = <String>[];
    final files = <SharedCopy>[];
    for (final m in media) {
      if (m.type == SharedMediaType.text || m.type == SharedMediaType.url) {
        texts.add(m.path);
        continue;
      }
      final name = p.basename(m.path);
      int? size;
      try {
        size = File(m.path).lengthSync();
      } on FileSystemException {
        size = null;
      }
      files.add(SharedCopy(m.path, _unknownName.hasMatch(name) ? null : name, size));
    }
    final share = IncomingShare(
      text: texts.isEmpty ? null : texts.join('\n'),
      subject: subject,
      files: files,
    );
    await _plugin.reset();
    if (!share.isEmpty) _controller?.add(share);
  }
}
