import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/local_shell/data/first_boot_runner.dart';
import 'package:conduit/features/local_shell/data/local_shell_platform.dart';
import 'package:conduit/features/local_shell/data/local_terminal_repository.dart';
import 'package:conduit/features/local_shell/data/proot_runner.dart';
import 'package:conduit/features/local_shell/data/rootfs_extractor.dart';
import 'package:conduit/features/local_shell/domain/local_shell_distro.dart';
import 'package:conduit/features/local_shell/domain/local_shell_paths.dart';
import 'package:conduit/features/local_shell/domain/local_shell_state.dart';
import 'package:conduit/features/local_shell/domain/proot_command.dart';
import 'package:conduit/features/local_shell/domain/pty_process.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

class FakeLocalPlatform extends LocalShellPlatform {
  FakeLocalPlatform(this.tempDir);

  final Directory tempDir;

  @override
  Future<LocalShellEnvironment?> load() async => LocalShellEnvironment(
        nativeLibraryDir: tempDir.path,
        filesDir: tempDir.path,
        sharedStorageFeatureEnabled: true,
        sharedStorageDir: '/storage/emulated/0',
        sharedStorageAccessGranted: true,
        supportedAbis: const ['arm64-v8a'],
      );
}

class FakeFirstBootRunner implements FirstBootRunner {
  FakeFirstBootRunner(this.paths);

  final LocalShellPaths paths;

  @override
  Future<void> run(LocalShellDistro distro) async {
    final marker = File(paths.firstBootMarkerHostPath);
    await marker.parent.create(recursive: true);
    await marker.writeAsString('');
  }
}

Future<ProotRunResult> testProotRunner(ProotCommand command) async {
  final archiveIndex = command.arguments.indexOf('-f') + 1;
  final rootfsIndex = command.arguments.indexOf('-C') + 1;
  final archivePath = command.arguments[archiveIndex];
  final rootfsDir = command.arguments[rootfsIndex];
  final stripIdx =
      command.arguments.indexWhere((a) => a.startsWith('--strip-components='));
  final stripArg = stripIdx >= 0 ? command.arguments[stripIdx] : null;

  final res = await Process.run('tar', [
    ?stripArg,
    '-xf',
    archivePath,
    '-C',
    rootfsDir,
  ]);
  return ProotRunResult(
    exitCode: res.exitCode,
    stderr: res.stderr.toString(),
  );
}

List<int> createTarGz(Map<String, String> files) {
  final buffer = BytesBuilder();

  for (final entry in files.entries) {
    final path = entry.key;
    final content = utf8.encode(entry.value);

    final header = Uint8List(512);
    final nameBytes = utf8.encode(path);
    header.setRange(0, nameBytes.length, nameBytes);

    final mode = utf8.encode('0000755\x00');
    header.setRange(100, 100 + mode.length, mode);

    final zero = utf8.encode('0000000\x00');
    header.setRange(108, 108 + zero.length, zero);
    header.setRange(116, 116 + zero.length, zero);

    final sizeOctal = content.length.toRadixString(8).padLeft(11, '0');
    final sizeBytes = utf8.encode('$sizeOctal\x00');
    header.setRange(124, 124 + sizeBytes.length, sizeBytes);

    header.setRange(136, 136 + zero.length, zero);
    header[156] = 0x30;

    final magic = utf8.encode('ustar\x00');
    header.setRange(257, 257 + magic.length, magic);

    for (var i = 148; i < 156; i++) {
      header[i] = 0x20;
    }
    var checksum = 0;
    for (final b in header) {
      checksum += b;
    }
    final chkOctal = checksum.toRadixString(8).padLeft(6, '0');
    final chkBytes = utf8.encode('$chkOctal\x00 ');
    header.setRange(148, 148 + chkBytes.length, chkBytes);

    buffer.add(header);
    buffer.add(content);

    final remainder = content.length % 512;
    if (remainder != 0) {
      buffer.add(Uint8List(512 - remainder));
    }
  }

  buffer.add(Uint8List(1024));
  return gzip.encode(buffer.toBytes());
}

void main() {
  group('Custom Rootfs Plan Verification', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('conduit_custom_rootfs_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('1. Local Archive Test (No Base Profile): Alpine .tar.gz boots with /bin/sh', () async {
      // 1. Prepare minimal Alpine rootfs archive
      final alpineArchiveBytes = createTarGz({
        'bin/sh': '#!/bin/sh\necho "alpine shell"\n',
        'etc/os-release': 'NAME="Alpine Linux"\nID=alpine\nVERSION_ID=3.20.0\n',
      });
      final archiveFile = File(p.join(tempDir.path, 'alpine-minirootfs.tar.gz'));
      await archiveFile.writeAsBytes(alpineArchiveBytes);

      final controller = LocalShellController(
        platform: FakeLocalPlatform(tempDir),
        extractorFactory: (paths) => ProotRootfsExtractor(
          paths,
          prootRunner: testProotRunner,
        ),
        firstBootRunnerFactory: FakeFirstBootRunner.new,
      );
      await controller.refresh();

      // Install custom distro from local file with no base profile
      await controller.installNew(
        'custom',
        name: 'My Alpine',
        sourceFilePath: archiveFile.path,
      );

      final instance = controller.instances.singleWhere((i) => i.name == 'My Alpine');
      expect(instance.isCustom, isTrue);
      expect(instance.sourceFilePath, archiveFile.path);
      expect(instance.baseProfileId, isNull);
      final state = controller.stateFor(instance.id);
      expect(state.stage, LocalShellStage.ready);

      // Verify launch resolution defaults to /bin/sh -l and empty update command
      final launch = await controller.requireLaunch(localShellHostIdFor(instance.id));
      expect(launch.distro.loginCommand, ['/bin/sh', '-l']);
      expect(launch.distro.updateCommand, '');

      // Check extracted content
      final osReleaseFile = File(p.join(launch.paths.rootfsDir, 'etc', 'os-release'));
      expect(osReleaseFile.existsSync(), isTrue);
      expect(await osReleaseFile.readAsString(), contains('ID=alpine'));

      // Connect terminal repository and verify login command uses /bin/sh -l
      List<String>? launchedArguments;
      final repo = LocalTerminalRepository(
        resolveLaunch: controller.requireLaunch,
        processFactory: ({
          required executable,
          required arguments,
          required environment,
          required rows,
          required columns,
        }) {
          launchedArguments = arguments;
          return _FakePtyProcess();
        },
      );

      final host = controller.localHost(instance);
      await repo.connect(host, columns: 80, rows: 24);

      expect(launchedArguments, isNotNull);
      expect(launchedArguments, containsAllInOrder(['/bin/sh', '-l']));
    });

    test('2. Custom URL + Base Profile Test: Fedora rootfs inherits dnf upgrade and /bin/bash', () async {
      // 1. Prepare custom Fedora rootfs bytes
      final fedoraArchiveBytes = createTarGz({
        'bin/sh': '#!/bin/sh\n',
        'bin/bash': '#!/bin/bash\n',
        'usr/bin/dnf': '#!/bin/sh\n',
        'etc/os-release': 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID=40\n',
      });

      final mockClient = MockClient((request) async {
        if (request.url == Uri.parse('https://custom.repo.org/fedora-custom.tar.gz')) {
          return http.Response.bytes(
            fedoraArchiveBytes,
            200,
            headers: {'content-length': fedoraArchiveBytes.length.toString()},
          );
        }
        return http.Response('Not Found', 404);
      });

      final controller = LocalShellController(
        platform: FakeLocalPlatform(tempDir),
        httpClient: mockClient,
        extractorFactory: (paths) => ProotRootfsExtractor(
          paths,
          prootRunner: testProotRunner,
        ),
        firstBootRunnerFactory: FakeFirstBootRunner.new,
      );
      await controller.refresh();

      // Install custom distro from URL with Fedora as base profile
      await controller.installNew(
        'custom',
        name: 'Fedora Custom',
        sourceUrl: 'https://custom.repo.org/fedora-custom.tar.gz',
        baseProfileId: 'fedora',
      );

      final instance = controller.instances.singleWhere((i) => i.name == 'Fedora Custom');
      expect(instance.isCustom, isTrue);
      expect(instance.sourceUrl, 'https://custom.repo.org/fedora-custom.tar.gz');
      expect(instance.baseProfileId, 'fedora');

      final state = controller.stateFor(instance.id);
      expect(state.stage, LocalShellStage.ready);

      // Verify inherited commands: dnf upgrade and /bin/bash --login
      final launch = await controller.requireLaunch(localShellHostIdFor(instance.id));
      expect(launch.distro.loginCommand, ['/bin/bash', '--login']);
      expect(launch.distro.updateCommand, 'dnf upgrade');

      // Check extracted content
      final osReleaseFile = File(p.join(launch.paths.rootfsDir, 'etc', 'os-release'));
      expect(osReleaseFile.existsSync(), isTrue);
      expect(await osReleaseFile.readAsString(), contains('ID=fedora'));

      // Connect terminal repository and verify login command uses /bin/bash --login
      List<String>? launchedArguments;
      final repo = LocalTerminalRepository(
        resolveLaunch: controller.requireLaunch,
        processFactory: ({
          required executable,
          required arguments,
          required environment,
          required rows,
          required columns,
        }) {
          launchedArguments = arguments;
          return _FakePtyProcess();
        },
      );

      final host = SavedHost.localShell(id: localShellHostIdFor(instance.id), name: instance.name);
      await repo.connect(host, columns: 80, rows: 24);

      expect(launchedArguments, isNotNull);
      expect(launchedArguments, containsAllInOrder(['/bin/bash', '--login']));
    });

    test('3. Invalid Archive Test: Catches missing shell and reports error', () async {
      // Create a generic tarball with text files but no /bin/sh
      final invalidArchiveBytes = createTarGz({
        'documents/readme.txt': 'This is just a document, not a rootfs.',
        'pictures/image.png': 'not an image either',
      });
      final archiveFile = File(p.join(tempDir.path, 'not-a-rootfs.tar.gz'));
      await archiveFile.writeAsBytes(invalidArchiveBytes);

      final controller = LocalShellController(
        platform: FakeLocalPlatform(tempDir),
        extractorFactory: (paths) => ProotRootfsExtractor(
          paths,
          prootRunner: testProotRunner,
        ),
        firstBootRunnerFactory: FakeFirstBootRunner.new,
      );
      await controller.refresh();

      // Install using the invalid archive
      await controller.installNew(
        'custom',
        name: 'Invalid Distro',
        sourceFilePath: archiveFile.path,
      );

      final instance = controller.instances.singleWhere((i) => i.name == 'Invalid Distro');
      final state = controller.stateFor(instance.id);

      expect(state.stage, LocalShellStage.failed);
      expect(state.error?.kind, LocalShellErrorKind.extractionFailed);
      expect(state.error?.message, contains('missing /bin/sh or /usr/bin/sh'));
    });
  });
}

class _FakePtyProcess implements PtyProcess {
  final _outputController = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get output => _outputController.stream;

  @override
  Future<int> get exitCode => Future.value(0);

  @override
  void write(Uint8List data) {}

  @override
  void resize(int rows, int columns) {}

  @override
  void kill() {
    _outputController.close();
  }
}
