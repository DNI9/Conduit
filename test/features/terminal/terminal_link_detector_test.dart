import 'package:conduit/features/terminal/domain/terminal_link_detector.dart';
import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalLinkDetector', () {
    test('detects https and http URLs and parses correctly', () {
      final terminal = Terminal(maxLines: 50);
      terminal.resize(80, 24);
      terminal.write('Check out https://github.com/gwitko/conduit for info');

      // Tapping on 'h' of https:// (x=10, y=0)
      final hitStart = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(10, 0),
      );
      expect(hitStart, Uri.parse('https://github.com/gwitko/conduit'));

      // Tapping on 't' of 'conduit' (x=42, y=0)
      final hitEnd = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(42, 0),
      );
      expect(hitEnd, Uri.parse('https://github.com/gwitko/conduit'));

      // Tapping on 'Check' (x=2, y=0) - before URL
      final missBefore = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(2, 0),
      );
      expect(missBefore, isNull);

      // Tapping on 'info' (x=50, y=0) - after URL
      final missAfter = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(50, 0),
      );
      expect(missAfter, isNull);
    });

    test('detects www. URLs and prepends https schema', () {
      final terminal = Terminal(maxLines: 50);
      terminal.resize(80, 24);
      terminal.write('Visit www.google.com today');

      final uri = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(10, 0),
      );
      expect(uri, Uri.parse('https://www.google.com'));
    });

    test('trims trailing punctuation from URLs in prose', () {
      final terminal = Terminal(maxLines: 50);
      terminal.resize(80, 24);
      terminal.write(
        'See https://example.com/api, and https://example.com/docs.',
      );

      final uriComma = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(10, 0),
      );
      expect(uriComma, Uri.parse('https://example.com/api'));

      final uriPeriod = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(35, 0),
      );
      expect(uriPeriod, Uri.parse('https://example.com/docs'));
    });

    test('handles balanced vs unbalanced parentheses and brackets', () {
      final terminal = Terminal(maxLines: 50);
      terminal.resize(80, 24);
      terminal.write(
        '(https://example.com/wiki_(disambiguation)) [https://example.com/doc]',
      );

      // Tapping inside (https://example.com/wiki_(disambiguation))
      final uriWiki = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(5, 0),
      );
      expect(uriWiki, Uri.parse('https://example.com/wiki_(disambiguation)'));

      // Tapping inside [https://example.com/doc]
      final uriDoc = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(50, 0),
      );
      expect(uriDoc, Uri.parse('https://example.com/doc'));
    });

    test('detects URL wrapped across multiple terminal lines', () {
      final terminal = Terminal(maxLines: 50);
      terminal.resize(20, 10);
      // "Go to https://example.com/long/path/here now" is 43 chars
      // On 20-col terminal:
      // Line 0: "Go to https://exampl" (wrapped)
      // Line 1: "e.com/long/path/here" (wrapped)
      // Line 2: " now"
      terminal.write('Go to https://example.com/long/path/here now');

      // Tap on line 0 in the URL ('h' in https) -> col 6
      final hitLine0 = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(6, 0),
      );
      expect(hitLine0, Uri.parse('https://example.com/long/path/here'));

      // Tap on line 1 in the URL ('p' in path) -> col 11
      final hitLine1 = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(11, 1),
      );
      expect(hitLine1, Uri.parse('https://example.com/long/path/here'));

      // Tap on line 2 outside URL -> col 1 ("now")
      final missLine2 = TerminalLinkDetector.findUriAt(
        terminal,
        const CellOffset(1, 2),
      );
      expect(missLine2, isNull);
    });

    test(
      'correctly offsets characters when wide unicode emojis are present',
      () {
        final terminal = Terminal(maxLines: 50);
        terminal.resize(80, 24);
        // Emoji 🚀 takes 2 terminal columns
        terminal.write('🚀 Launch https://example.com');

        // '🚀' is at col 0 and 1, ' ' at col 2, 'Launch ' at cols 3..9
        // 'https://example.com' starts at col 10
        final hit = TerminalLinkDetector.findUriAt(
          terminal,
          const CellOffset(15, 0),
        );
        expect(hit, Uri.parse('https://example.com'));

        final missEmoji = TerminalLinkDetector.findUriAt(
          terminal,
          const CellOffset(0, 0),
        );
        expect(missEmoji, isNull);
      },
    );

    test('returns null for empty lines or out-of-bounds rows', () {
      final terminal = Terminal(maxLines: 50);
      terminal.resize(80, 24);
      terminal.write('Just regular text');

      expect(
        TerminalLinkDetector.findUriAt(terminal, const CellOffset(0, 5)),
        isNull,
      );
      expect(
        TerminalLinkDetector.findUriAt(terminal, const CellOffset(0, 100)),
        isNull,
      );
      expect(
        TerminalLinkDetector.findUriAt(terminal, const CellOffset(0, -1)),
        isNull,
      );
    });

    test(
      'reconstructs hard-wrapped multi-line OAuth URL with indentation across lines',
      () {
        final terminal = Terminal(maxLines: 100);
        terminal.resize(56, 24);

        final rawLines = [
          ' https://accounts.google.com/o/oauth2/auth?access_type=o\r\n',
          ' ffline&client_id=1071006060591-tmhssin2h21lcre235vtoloj\r\n',
          ' h4g403ep.apps.googleusercontent.com&code_challenge=CCpD\r\n',
          ' DD3IUGapXkqYgvLfQSb1-Msphyz4NMpw_Q5MoOQ&code_challenge_\r\n',
          ' method=S256&prompt=consent&redirect_uri=https%3A%2F%2Fa\r\n',
          ' ntigravity.google%2Foauth-callback&response_type=code&s\r\n',
          ' cope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcloud-pl\r\n',
          ' atform+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserin\r\n',
          ' fo.email+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuser\r\n',
          ' info.profile+https%3A%2F%2Fwww.googleapis.com%2Fauth%2F\r\n',
          ' cclog+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fexperim\r\n',
          ' entsandconfigs+https%3A%2F%2Fwww.googleapis.com%2Fauth%\r\n',
          ' 2Faicode+openid&state=7pSZsLM3g6Hyl3TtJh0nCw \r\n',
        ];

        for (final l in rawLines) {
          terminal.write(l);
        }

        const expectedUrl =
            'https://accounts.google.com/o/oauth2/auth?access_type=offline&client_id=1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com&code_challenge=CCpDDD3IUGapXkqYgvLfQSb1-Msphyz4NMpw_Q5MoOQ&code_challenge_method=S256&prompt=consent&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback&response_type=code&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcloud-platform+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.email+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.profile+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcclog+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fexperimentsandconfigs+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Faicode+openid&state=7pSZsLM3g6Hyl3TtJh0nCw';

        // Tapping on line 0
        final hitLine0 = TerminalLinkDetector.findUriAt(
          terminal,
          const CellOffset(10, 0),
        );
        expect(hitLine0?.toString(), expectedUrl);

        // Tapping on line 3
        final hitLine3 = TerminalLinkDetector.findUriAt(
          terminal,
          const CellOffset(15, 3),
        );
        expect(hitLine3?.toString(), expectedUrl);

        // Tapping on line 12 (last line)
        final hitLine12 = TerminalLinkDetector.findUriAt(
          terminal,
          const CellOffset(20, 12),
        );
        expect(hitLine12?.toString(), expectedUrl);

        // Tapping on column 0 (indent margin) of line 5
        final hitIndent = TerminalLinkDetector.findUriAt(
          terminal,
          const CellOffset(0, 5),
        );
        expect(hitIndent?.toString(), expectedUrl);
      },
    );
  });
}
