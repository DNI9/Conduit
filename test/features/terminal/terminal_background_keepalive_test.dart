import 'package:conduit/features/terminal/presentation/terminal_background_keepalive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final log = <MethodCall>[];
  const channel = MethodChannel('conduit/background_keepalive');

  setUp(() {
    log.clear();
    TerminalBackgroundKeepalive.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TerminalBackgroundKeepalive.resetForTesting();
  });

  test('maintains foreground service for active sessions after task stops', () async {
    const keepalive = TerminalBackgroundKeepalive();

    // App has 2 active sessions in background
    await keepalive.start(sessionCount: 2);
    expect(log.last.method, 'start');
    var args = log.last.arguments as Map<Object?, Object?>;
    expect(args['sessionCount'], 2);
    expect(args['message'], isNull);

    // Backup task starts with a message
    await keepalive.start(message: 'Exporting Arch Linux...');
    expect(log.last.method, 'start');
    args = log.last.arguments as Map<Object?, Object?>;
    expect(args['sessionCount'], 2);
    expect(args['message'], 'Exporting Arch Linux...');

    // Backup task finishes -> should keep foreground service alive for the 2 sessions
    await keepalive.stop(isTask: true);
    expect(log.last.method, 'start');
    args = log.last.arguments as Map<Object?, Object?>;
    expect(args['sessionCount'], 2);
    expect(args['message'], isNull);
    await keepalive.stop();
    expect(log.last.method, 'stop');
  });

  test('stops service completely when single task finishes with no sessions', () async {
    const keepalive = TerminalBackgroundKeepalive();

    await keepalive.start(message: 'Exporting...');
    expect(log.last.method, 'start');
    final args = log.last.arguments as Map<Object?, Object?>;
    expect(args['message'], 'Exporting...');
    await keepalive.stop(isTask: true);
    expect(log.last.method, 'stop');
  });
}
