import 'package:conduit/features/local_shell/data/proot_runner.dart';
import 'package:conduit/features/local_shell/domain/local_shell_paths.dart';
import 'package:conduit/features/local_shell/domain/proot_command.dart';

class ExtractionException implements Exception {
  const ExtractionException(this.message);

  final String message;

  @override
  String toString() => 'ExtractionException($message)';
}

abstract interface class RootfsExtractor {
  Future<void> extract();
}

class ProotRootfsExtractor implements RootfsExtractor {
  ProotRootfsExtractor(this.paths, {this.stripComponents = 1});

  final LocalShellPaths paths;
  final int stripComponents;

  @override
  Future<void> extract() async {
    final command =
        ProotCommandBuilder(
          prootBinary: paths.prootBinary,
          loaderPath: paths.loaderPath,
          libraryPath: paths.nativeLibraryDir,
          tmpDir: paths.tmpDir,
        ).extractTar(
          stripComponents: stripComponents,
          archivePath: paths.downloadPath,
          rootfsDir: paths.rootfsDir,
          tarBinary: paths.tarBinary,
          xzBinary: paths.xzBinary,
        );

    final ProotRunResult result;
    try {
      result = await runProot(command);
    } catch (error) {
      throw ExtractionException('Could not launch proot/tar: $error');
    }

    if (result.exitCode != 0) {
      throw ExtractionException(
        'tar exited with ${result.exitCode}: ${result.stderr}',
      );
    }
  }
}

class ProotRootfsArchiver {
  ProotRootfsArchiver(this.paths);

  final LocalShellPaths paths;

  Future<void> archive(String archivePath) async {
    final command =
        ProotCommandBuilder(
          prootBinary: paths.prootBinary,
          loaderPath: paths.loaderPath,
          libraryPath: paths.nativeLibraryDir,
          tmpDir: paths.tmpDir,
        ).createTar(
          archivePath: archivePath,
          rootfsDir: paths.rootfsDir,
          tarBinary: paths.tarBinary,
          xzBinary: paths.xzBinary,
        );

    final ProotRunResult result;
    try {
      result = await runProot(command);
    } catch (error) {
      throw ExtractionException('Could not launch proot/tar: $error');
    }

    // GNU tar exits with 1 for non-fatal warnings (e.g. file changed as we read it).
    if (result.exitCode > 1) {
      throw ExtractionException(
        'tar exited with ${result.exitCode}: ${result.stderr}',
      );
    }
  }
}
