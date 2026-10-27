import 'package:meta/meta.dart';

/// How to split a task into subtasks in one action (Goal 6).
sealed class SplitSpec {
  const SplitSpec();
}

final class Chapters extends SplitSpec {
  const Chapters(this.from, this.to);
  final int from;
  final int to;
}

final class PageChunks extends SplitSpec {
  const PageChunks(this.from, this.to, this.size);
  final int from;
  final int to;
  final int size;
}

final class Custom extends SplitSpec {
  const Custom(this.titles);
  final List<String> titles;
}

@immutable
final class SplitPart {
  const SplitPart(this.title, this.positionText);
  final String title;
  final String? positionText;

  @override
  bool operator ==(Object other) =>
      other is SplitPart && other.title == title && other.positionText == positionText;

  @override
  int get hashCode => Object.hash(title, positionText);

  @override
  String toString() => 'SplitPart($title, $positionText)';
}

List<SplitPart> split(SplitSpec spec) {
  switch (spec) {
    case Chapters(:final from, :final to):
      if (from < 1 || from > to) {
        throw ArgumentError('Chapter range must satisfy 1 ≤ from ≤ to');
      }
      return [
        for (var c = from; c <= to; c++) SplitPart('Ch $c', 'Ch $c'),
      ];
    case PageChunks(:final from, :final to, :final size):
      if (from < 1 || from > to) {
        throw ArgumentError('Page range must satisfy 1 ≤ from ≤ to');
      }
      if (size < 1) throw ArgumentError('Chunk size must be at least 1');
      final parts = <SplitPart>[];
      for (var start = from; start <= to; start += size) {
        final end = (start + size - 1) > to ? to : start + size - 1;
        final text = start == end ? 'p. $start' : 'pp. $start–$end';
        parts.add(SplitPart(text, text));
      }
      return parts;
    case Custom(:final titles):
      final cleaned = [
        for (final t in titles)
          if (t.trim().isNotEmpty) t.trim(),
      ];
      if (cleaned.isEmpty) throw ArgumentError('At least one title is needed');
      return [for (final t in cleaned) SplitPart(t, null)];
  }
}
