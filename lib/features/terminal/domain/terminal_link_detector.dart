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
    while (startY > 0 && lines[startY].isWrapped) {
      startY--;
    }

    // Traverse downwards to find the end of the logical line.
    var endY = offset.y;
    while (endY + 1 < lines.length && lines[endY + 1].isWrapped) {
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
          if (line.getCodePoint(i) != 0) {
            lastNonBlank = i;
          }
        }
        maxCol = lastNonBlank + 1;
      }

      for (var x = 0; x < maxCol; x++) {
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

      if (isHit) {
        final parsed = _parseUrl(url);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
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
