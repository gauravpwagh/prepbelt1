import 'package:meta/meta.dart';

import 'defaults.dart';

/// Mirrors the `source_type` column.
enum SourceType {
  pdf('pdf'),
  book('book'),
  web('web'),
  aiChat('ai_chat'),
  video('video'),
  notes('notes'),
  lecture('lecture'),
  app('app'),
  otherDevice('other_device');

  const SourceType(this.key);
  final String key;

  static SourceType fromKey(String key) => values.firstWhere((t) => t.key == key,
      orElse: () => throw ArgumentError.value(key, 'key', 'Unknown source type'));
}

/// Hosts treated as AI-chat sources (design §7).
const aiChatHosts = [
  'claude.ai',
  'chatgpt.com',
  'chat.openai.com',
  'gemini.google.com',
  'perplexity.ai',
  'copilot.microsoft.com',
];

@immutable
final class SharedFile {
  const SharedFile({this.name, this.size});

  /// Null when the sending app gave no usable name.
  final String? name;
  final int? size;
}

@immutable
final class ShareDraft {
  const ShareDraft({
    required this.title,
    required this.type,
    this.url,
    this.excerpt,
    this.file,
  });

  final String title;
  final SourceType type;
  final String? url;
  final String? excerpt;
  final SharedFile? file;

  @override
  String toString() => 'ShareDraft("$title", ${type.key}, $url)';
}

final _urlRe = RegExp(r'https?://\S+');
const _trailing = '.,;:!?)]}\'"';

/// First http(s) URL in [text], with trailing punctuation removed.
String? firstUrl(String text) {
  final m = _urlRe.firstMatch(text);
  if (m == null) return null;
  var url = m[0]!;
  while (url.isNotEmpty && _trailing.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// True if [host] equals an AI-chat host or is a subdomain of one.
bool isAiChatHost(String host) {
  final h = host.toLowerCase();
  return aiChatHosts.any((e) => h == e || h.endsWith('.$e'));
}

String _cut(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';

String? _firstLine(String text) {
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final t = line.trim();
    if (t.isNotEmpty) return t;
  }
  return null;
}

String _stripExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

/// Turns one incoming share into drafts (design §7, decision D10).
///
/// One draft per file, plus one for the text if any. The share subject is
/// used as the title of the text draft, or of the only file when the share
/// contains a single file and no text.
List<ShareDraft> classifyShare({
  String? text,
  String? subject,
  List<SharedFile> files = const [],
}) {
  final t = _nonEmpty(text);
  final subj = _nonEmpty(subject);
  final drafts = <ShareDraft>[];

  for (final f in files) {
    final name = _nonEmpty(f.name);
    final String title = (subj != null && t == null && files.length == 1)
        ? subj
        : (name != null ? _stripExtension(name) : 'Shared PDF');
    drafts.add(ShareDraft(
      title: _cut(title, Defaults.titleMaxChars),
      type: SourceType.pdf,
      file: f,
    ));
  }

  if (t != null) {
    final url = firstUrl(t);
    final host = url == null ? null : Uri.tryParse(url)?.host;
    final type = url == null
        ? SourceType.notes
        : (host != null && isAiChatHost(host) ? SourceType.aiChat : SourceType.web);
    final title = subj ??
        _firstLine(t) ??
        (host != null && host.isNotEmpty ? host : null) ??
        'Shared note';
    drafts.add(ShareDraft(
      title: _cut(title, Defaults.titleMaxChars),
      type: type,
      url: url,
      excerpt: _cut(t, Defaults.excerptMaxChars),
    ));
  }

  return drafts;
}
