import 'package:conduit_vt/conduit_vt.dart';

/// Scans terminal buffer lines around a tapped cell to detect web URLs.
class TerminalLinkDetector {
  static final _urlRegex = RegExp(r'(?:https?://|www\.)[^\s<>"{}|\\^`]+');

  /// Searches the [terminal] buffer around [offset] for a clickable link.
  ///
  /// Returns a valid [Uri] if the tapped cell is part of a URL, or `null` otherwise.
  static Uri? findUriAt(Terminal terminal, CellOffset offset) {
    final lines = terminal.buffer.lines;
    if (offset.y < 0 || offset.y >= lines.length) {
      return null;
    }

    // Traverse upwards to find the start of the logical line.
    var startY = offset.y;
    while (startY > 0 && _isLineContinuation(terminal, startY - 1, startY)) {
      startY--;
    }

    // Traverse downwards to find the end of the logical line.
    var endY = offset.y;
    while (endY + 1 < lines.length &&
        _isLineContinuation(terminal, endY, endY + 1)) {
      endY++;
    }

    final buffer = StringBuffer();
    final cellCoords = <CellOffset>[];

    for (var y = startY; y <= endY; y++) {
      final line = lines[y];
      final isLastLineOfLogical = y == endY;

      var maxCol = line.length;
      if (isLastLineOfLogical) {
        var lastNonBlank = -1;
        for (var i = 0; i < line.length; i++) {
          if (line.getCodePoint(i) != 0 && line.getCodePoint(i) != 0x20) {
            lastNonBlank = i;
          }
        }
        maxCol = lastNonBlank + 1;
      }

      // On hard-wrapped continuation lines (y > startY && !line.isWrapped),
      // skip leading whitespace indentation so wrapped URL tokens concatenate cleanly.
      // On soft-wrapped lines (line.isWrapped), retain all cells as they represent the raw stream.
      var minCol = 0;
      if (y > startY && !line.isWrapped) {
        while (minCol < maxCol &&
            (line.getCodePoint(minCol) == 0 ||
                line.getCodePoint(minCol) == 0x20)) {
          minCol++;
        }
      }

      for (var x = minCol; x < maxCol; x++) {
        final codePoint = line.getCodePoint(x);
        final width = line.getWidth(x);
        if (codePoint != 0 && x + width <= line.length) {
          final charStr = String.fromCharCode(codePoint);
          buffer.write(charStr);
          for (var i = 0; i < charStr.length; i++) {
            cellCoords.add(CellOffset(x, y));
          }
        } else if (x > 0 && line.getWidth(x - 1) == 2) {
          // Second cell of a double-width character: glyph was emitted with first cell.
        } else {
          buffer.write(' ');
          cellCoords.add(CellOffset(x, y));
        }
      }
    }

    final text = buffer.toString();
    if (text.isEmpty) {
      return null;
    }

    final matches = _urlRegex.allMatches(text);
    for (final match in matches) {
      final matchText = match.group(0);
      if (matchText == null || matchText.isEmpty) {
        continue;
      }
      var url = matchText;

      // Trim trailing punctuation that commonly adheres to URLs in prose.
      var trimmedLength = url.length;
      while (trimmedLength > 0) {
        final lastChar = url[trimmedLength - 1];
        if (lastChar == '.' ||
            lastChar == ',' ||
            lastChar == ';' ||
            lastChar == ':' ||
            lastChar == '!' ||
            lastChar == '?' ||
            lastChar == "'" ||
            lastChar == '"' ||
            (lastChar == ')' && _countChar(url, ')') > _countChar(url, '(')) ||
            (lastChar == ']' && _countChar(url, ']') > _countChar(url, '['))) {
          url = url.substring(0, trimmedLength - 1);
          trimmedLength = url.length;
        } else {
          break;
        }
      }

      if (url.isEmpty) {
        continue;
      }

      final matchStart = match.start;
      final matchEnd = matchStart + trimmedLength;

      // Check if the tapped offset falls within this match's cell coordinates.
      var isHit = false;
      for (var i = matchStart; i < matchEnd; i++) {
        if (i < cellCoords.length && cellCoords[i] == offset) {
          isHit = true;
          break;
        }
      }

      // If not a direct hit, check if user tapped in the leading indentation margin
      // of a continuation line occupied by this URL match.
      if (!isHit && offset.y > startY && offset.y <= endY) {
        final matchSlice = cellCoords.sublist(
          matchStart,
          matchEnd.clamp(matchStart, cellCoords.length),
        );
        final rowCoords = matchSlice.where((c) => c.y == offset.y).toList();
        if (rowCoords.isNotEmpty) {
          final firstXInRow = rowCoords
              .map((c) => c.x)
              .reduce((a, b) => a < b ? a : b);
          if (offset.x < firstXInRow) {
            final line = lines[offset.y];
            var isMarginOnly = true;
            for (var x = offset.x; x < firstXInRow; x++) {
              final cp = line.getCodePoint(x);
              if (cp != 0 && cp != 0x20) {
                isMarginOnly = false;
                break;
              }
            }
            if (isMarginOnly) {
              isHit = true;
            }
          }
        }
      }

      if (isHit) {
        final parsed = _parseUrl(url);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  /// Evaluates whether [nextY] is a wrapped continuation of [prevY].
  static bool _isLineContinuation(Terminal terminal, int prevY, int nextY) {
    final lines = terminal.buffer.lines;
    if (prevY < 0 || nextY >= lines.length || prevY >= nextY) {
      return false;
    }

    final nextLine = lines[nextY];
    if (nextLine.isWrapped) {
      return true;
    }

    final prevLine = lines[prevY];
    var prevLastNonBlank = -1;
    for (var x = prevLine.length - 1; x >= 0; x--) {
      if (prevLine.getCodePoint(x) != 0 && prevLine.getCodePoint(x) != 0x20) {
        prevLastNonBlank = x;
        break;
      }
    }
    if (prevLastNonBlank == -1) {
      return false;
    }

    final prevLastCode = prevLine.getCodePoint(prevLastNonBlank);
    if (!_isUrlChar(prevLastCode)) {
      return false;
    }

    final viewWidth = terminal.viewWidth;
    final reachedMargin =
        (prevLastNonBlank >= viewWidth - 4) ||
        (prevLastNonBlank >= 70 && prevLastNonBlank <= 80);
    if (!reachedMargin) {
      return false;
    }

    var nextFirstNonBlank = -1;
    for (var x = 0; x < nextLine.length; x++) {
      final code = nextLine.getCodePoint(x);
      if (code != 0 && code != 0x20) {
        nextFirstNonBlank = x;
        break;
      }
    }
    if (nextFirstNonBlank == -1) {
      return false;
    }

    final nextFirstCode = nextLine.getCodePoint(nextFirstNonBlank);
    if (!_isUrlChar(nextFirstCode)) {
      return false;
    }

    final nextText = nextLine.getText().trimLeft();
    if (nextText.startsWith('https://') ||
        nextText.startsWith('http://') ||
        nextText.startsWith('www.')) {
      return false;
    }

    // If the next line has spaces within the first 5 characters of content,
    // it is ordinary prose (e.g. "We are...", "Please..."), not a wrapped URL.
    for (
      var x = nextFirstNonBlank;
      x < nextLine.length && x < nextFirstNonBlank + 5;
      x++
    ) {
      final code = nextLine.getCodePoint(x);
      if (code == 0 || code == 0x20) {
        return false;
      }
    }

    return true;
  }

  static bool _isUrlChar(int codePoint) {
    if (codePoint <= 0x20 || codePoint >= 0x7F) {
      return false;
    }
    // Exclude characters not permitted unencoded in URLs: < > " { } | \ ^ `
    if (codePoint == 0x3C || // <
        codePoint == 0x3E || // >
        codePoint == 0x22 || // "
        codePoint == 0x7B || // {
        codePoint == 0x7D || // }
        codePoint == 0x7C || // |
        codePoint == 0x5C || // \
        codePoint == 0x5E || // ^
        codePoint == 0x60) {
      // `
      return false;
    }
    return true;
  }

  static Uri? _parseUrl(String url) {
    var raw = url;
    if (raw.startsWith('www.')) {
      raw = 'https://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri;
    }
    return null;
  }

  static int _countChar(String str, String char) {
    var count = 0;
    for (var i = 0; i < str.length; i++) {
      if (str[i] == char) {
        count++;
      }
    }
    return count;
  }
}
