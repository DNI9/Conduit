import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/local_shell/domain/proot_command.dart';

class ProotRunResult {
  const ProotRunResult({required this.exitCode, required this.stderr});

  final int exitCode;
  final String stderr;
}

Future<ProotRunResult> runProot(
  ProotCommand command, {
  void Function(String line)? onStderr,
}) async {
  final process = await Process.start(
    command.executable,
    command.arguments,
    environment: command.environment,
  );

  final stderrBuffer = StringBuffer();
  final stdoutDrain = process.stdout.drain<void>();
  final stderrDrain = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
        stderrBuffer.writeln(line);
        onStderr?.call(line);
      });
  final exitCode = await process.exitCode;
  await stdoutDrain;
  await stderrDrain;

  return ProotRunResult(exitCode: exitCode, stderr: stderrBuffer.toString());
}
