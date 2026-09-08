import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/local_shell/domain/proot_command.dart';
import 'package:flutter/foundation.dart';


class ProotRunResult {
  const ProotRunResult({required this.exitCode, required this.stderr});

  final int exitCode;
  final String stderr;
}

Future<ProotRunResult> runProot(
  ProotCommand command, {
  void Function(String line)? onStderr,
}) async {
  if (kDebugMode) {
    debugPrint(
      '[local_shell] runProot: ${command.executable} ${command.arguments.join(" ")}',
    );
    debugPrint('[local_shell] runProot env: ${command.environment}');
  }

  final process = await Process.start(
    command.executable,
    command.arguments,
    environment: command.environment,
  );
  unawaited(process.stdin.close());
  final stderrBuffer = StringBuffer();
  final stdoutDrain = process.stdout.drain<void>();
  final stderrDrain = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .forEach((line) {
        stderrBuffer.writeln(line);
        if (kDebugMode) {
          debugPrint('[local_shell] runProot stderr: $line');
        }
        onStderr?.call(line);
      });
  final exitCode = await process.exitCode;
  await stdoutDrain;
  await stderrDrain;
  if (kDebugMode) {
    debugPrint(
      '[local_shell] runProot finished (pid: ${process.pid}, exitCode: $exitCode)',
    );
  }
  return ProotRunResult(exitCode: exitCode, stderr: stderrBuffer.toString());
}
