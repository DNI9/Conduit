import 'package:conduit/features/local_shell/data/proot_runner.dart';
import 'package:conduit/features/local_shell/domain/proot_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runProot collects stderr and calls onStderr for each line', () async {
    final lines = <String>[];
    const command = ProotCommand(
      executable: '/bin/sh',
      arguments: ['-c', 'echo 10000 >&2; echo 20000 >&2'],
      environment: {},
    );

    final result = await runProot(
      command,
      onStderr: lines.add,
    );

    expect(result.exitCode, 0);
    expect(lines, ['10000', '20000']);
    expect(result.stderr, contains('10000\n20000\n'));
  });
  test('checkpoint regex matches both raw numbers and tar: prefixed checkpoints', () {
    final regex = RegExp(r'^(?:tar:\s*)?(\d+)$');
    expect(regex.firstMatch('tar: 1000')?.group(1), '1000');
    expect(regex.firstMatch('tar:   2000')?.group(1), '2000');
    expect(regex.firstMatch('3000')?.group(1), '3000');
    expect(regex.firstMatch('tar: warning: something'), isNull);
  });
}
