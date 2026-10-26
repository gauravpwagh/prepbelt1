import 'package:prep_core/prep_core.dart';
import 'package:test/test.dart';

void main() {
  group('AI-chat hosts', () {
    for (final host in aiChatHosts) {
      test(host, () {
        final d = classifyShare(text: 'Preamble notes https://$host/share/abc').single;
        expect(d.type, SourceType.aiChat);
        expect(d.url, 'https://$host/share/abc');
      });
    }
    test('www. and subdomains match; look-alikes do not', () {
      expect(isAiChatHost('www.perplexity.ai'), isTrue);
      expect(isAiChatHost('eu.claude.ai'), isTrue);
      expect(isAiChatHost('notclaude.ai'), isFalse);
      expect(isAiChatHost('claude.ai.evil.com'), isFalse);
    });
  });

  test('plain web link', () {
    final d = classifyShare(text: 'https://example.org/polity/preamble').single;
    expect(d.type, SourceType.web);
    expect(d.title, 'https://example.org/polity/preamble');
  });

  test('text with no URL → notes', () {
    final d = classifyShare(text: '\n  Fundamental duties summary\nline two').single;
    expect(d.type, SourceType.notes);
    expect(d.url, isNull);
    expect(d.title, 'Fundamental duties summary');
    expect(d.excerpt, '\n  Fundamental duties summary\nline two'.trim());
  });

  test('first URL wins and trailing punctuation is dropped', () {
    expect(firstUrl('see (https://a.com/x). and https://b.com'), 'https://a.com/x');
    final d = classifyShare(text: 'https://a.com/1 https://b.com/2').single;
    expect(d.url, 'https://a.com/1');
  });

  test('subject is the title of the text draft', () {
    final d = classifyShare(text: 'https://chatgpt.com/share/1', subject: 'Preamble chat').single;
    expect(d.title, 'Preamble chat');
  });

  test('one PDF: subject, else file name, else "Shared PDF"', () {
    expect(classifyShare(files: const [SharedFile(name: 'Polity_notes.pdf', size: 10)])
        .single.title, 'Polity_notes');
    expect(classifyShare(subject: 'Notes', files: const [SharedFile(name: 'a.pdf')])
        .single.title, 'Notes');
    expect(classifyShare(files: const [SharedFile()]).single.title, 'Shared PDF');
  });

  test('two PDFs → two drafts', () {
    final ds = classifyShare(files: const [SharedFile(name: 'a.pdf'), SharedFile(name: 'b.pdf')]);
    expect([for (final d in ds) d.title], ['a', 'b']);
    expect(ds.every((d) => d.type == SourceType.pdf), isTrue);
  });

  test('PDF plus text → file draft and text draft', () {
    final ds = classifyShare(text: 'see this', files: const [SharedFile(name: 'a.pdf')]);
    expect(ds.length, 2);
    expect(ds.first.title, 'a');
    expect(ds.last.type, SourceType.notes);
  });

  test('title falls back to host, then "Shared note"', () {
    // A line that is only whitespace around a URL still gives a first line.
    expect(classifyShare(text: 'https://x.org').single.title, 'https://x.org');
    expect(classifyShare(text: '   ').isEmpty, isTrue);
  });

  test('caps: 80-char title, 20,000-char excerpt', () {
    final long = 'a' * 200;
    final d = classifyShare(text: long).single;
    expect(d.title.length, 80);
    expect(d.title.endsWith('…'), isTrue);
    final huge = 'b' * 25000;
    expect(classifyShare(text: huge).single.excerpt!.length, 20000);
  });
}
