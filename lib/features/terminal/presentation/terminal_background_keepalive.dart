import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TerminalBackgroundKeepalive {
  const TerminalBackgroundKeepalive();
  static const _channel = MethodChannel('conduit/background_keepalive');

  static int _activeSessions = 0;
  static int _activeTasks = 0;
  static String? _taskMessage;

  @visibleForTesting
  static void resetForTesting() {
    _activeSessions = 0;
    _activeTasks = 0;
    _taskMessage = null;
  }

  Future<void> start({int sessionCount = 0, String? message}) async {
    if (message != null) {
      _activeTasks++;
      _taskMessage = message;
    } else {
      _activeSessions = sessionCount;
    }

    try {
      await _channel.invokeMethod<void>('start', {
        'sessionCount': _activeSessions,
        'message': ?_taskMessage,
      });
    } catch (_) {
      // Keepalive is best-effort (e.g. tests or platforms without service support).
    }
  }

  Future<void> stop({bool isTask = false}) async {
    if (isTask) {
      _activeTasks = _activeTasks > 0 ? _activeTasks - 1 : 0;
      if (_activeTasks == 0) _taskMessage = null;
    } else {
      _activeSessions = 0;
    }

    try {
      if (_activeSessions > 0 || _activeTasks > 0) {
        await _channel.invokeMethod<void>('start', {
          'sessionCount': _activeSessions,
          'message': ?_taskMessage,
        });
      } else {
        await _channel.invokeMethod<void>('stop');
      }
    } catch (_) {
      // Keepalive is best-effort.
    }
  }
  Future<void> requestNotificationPermission() async {
    await _channel.invokeMethod<void>('requestNotificationPermission');
  }
}
