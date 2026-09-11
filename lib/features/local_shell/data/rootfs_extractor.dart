import 'dart:io';

import 'package:conduit/features/local_shell/data/proot_runner.dart';
import 'package:conduit/features/local_shell/domain/local_shell_paths.dart';
import 'package:conduit/features/local_shell/domain/proot_command.dart';
import 'package:path/path.dart' as p;

class ExtractionException implements Exception {
  const ExtractionException(this.message);

  final String message;

  @override
  String toString() => 'ExtractionException($message)';
}

class UnsupportedArchiveException implements ExtractionException {
  const UnsupportedArchiveException(this.message);

  @override
  final String message;

  @override
  String toString() => 'UnsupportedArchiveException($message)';
}

enum ArchiveFormat { gzip, xz, tar, unsupported }

abstract interface class RootfsExtractor {
  Future<void> extract();
}
typedef ProotRunner = Future<ProotRunResult> Function(ProotCommand command);

class ProotRootfsExtractor implements RootfsExtractor {
  ProotRootfsExtractor(
    this.paths, {
    this.stripComponents,
    this.prootRunner = runProot,
  });

  final LocalShellPaths paths;
  final int? stripComponents;
  final ProotRunner prootRunner;

  static Future<ArchiveFormat> detectArchiveFormat(File file) async {
    if (!await file.exists()) return ArchiveFormat.unsupported;
    final raf = await file.open();
    try {
      final header = await raf.read(512);
      if (header.length >= 2 && header[0] == 0x1f && header[1] == 0x8b) {
        return ArchiveFormat.gzip;
      }
      if (header.length >= 6 &&
          header[0] == 0xfd &&
          header[1] == 0x37 &&
          header[2] == 0x7a &&
          header[3] == 0x58 &&
          header[4] == 0x5a &&
          header[5] == 0x00) {
        return ArchiveFormat.xz;
      }
      if (header.length >= 262) {
        final magic = String.fromCharCodes(header.sublist(257, 262));
        if (magic == 'ustar') {
          return ArchiveFormat.tar;
        }
      }
      final lower = file.path.toLowerCase();
      if (lower.endsWith('.tar')) return ArchiveFormat.tar;
      return ArchiveFormat.unsupported;
    } finally {
      await raf.close();
    }
  }

  @override
  Future<void> extract() async {
    final archiveFile = File(paths.downloadPath);
    if (!await archiveFile.exists()) {
      throw const ExtractionException('Rootfs archive file not found.');
    }

    final format = await detectArchiveFormat(archiveFile);
    if (format == ArchiveFormat.unsupported) {
      throw const UnsupportedArchiveException(
        'Unsupported archive format. Please provide a standard .tar.gz or .tar.xz rootfs archive.',
      );
    }

    String pathToExtract = paths.downloadPath;
    String? compressProgram;
    File? tempUncompressedFile;
    final resolvedStripComponents = stripComponents ?? 0;

    if (format == ArchiveFormat.gzip) {
      final tempTarPath = p.join(paths.tmpDir, 'staging.tar');
      tempUncompressedFile = File(tempTarPath);
      await tempUncompressedFile.parent.create(recursive: true);
      try {
        final sink = tempUncompressedFile.openWrite();
        await archiveFile.openRead().transform(gzip.decoder).pipe(sink);
      } catch (error) {
        await tempUncompressedFile.delete().catchError((_) => tempUncompressedFile!);
        throw ExtractionException('Failed to decompress gzip archive: $error');
      }
      pathToExtract = tempTarPath;
      compressProgram = null;
    } else if (format == ArchiveFormat.xz) {
      compressProgram = paths.xzBinary;
    } else {
      compressProgram = null;
    }

    try {
      final command = ProotCommandBuilder(
        prootBinary: paths.prootBinary,
        loaderPath: paths.loaderPath,
        libraryPath: paths.nativeLibraryDir,
        tmpDir: paths.tmpDir,
      ).extractTar(
        archivePath: pathToExtract,
        rootfsDir: paths.rootfsDir,
        tarBinary: paths.tarBinary,
        compressProgram: compressProgram,
        stripComponents: resolvedStripComponents,
      );

      final ProotRunResult result;
      try {
        result = await prootRunner(command);
      } catch (error) {
        throw ExtractionException('Could not launch proot/tar: $error');
      }

      if (result.exitCode != 0) {
        throw ExtractionException(
          'tar exited with ${result.exitCode}: ${result.stderr}',
        );
      }
      await normalizeExtractedDir();
      validateRootfs();
    } finally {
      if (tempUncompressedFile != null && await tempUncompressedFile.exists()) {
        await tempUncompressedFile.delete().catchError((_) => tempUncompressedFile!);
      }
    }
  }

  Future<void> normalizeExtractedDir() async {
    final root = Directory(paths.rootfsDir);
    if (!await root.exists()) return;

    final hasDirectShell =
        File(p.join(paths.rootfsDir, 'bin', 'sh')).existsSync() ||
        File(p.join(paths.rootfsDir, 'usr', 'bin', 'sh')).existsSync();
    if (hasDirectShell) return;

    final entries = await root.list(followLinks: false).toList();
    final dirs = entries.whereType<Directory>().toList();
    if (dirs.length == 1) {
      final singleDir = dirs.first;
      final nestedShell =
          File(p.join(singleDir.path, 'bin', 'sh')).existsSync() ||
          File(p.join(singleDir.path, 'usr', 'bin', 'sh')).existsSync();
      if (nestedShell) {
        for (final child in await singleDir.list(followLinks: false).toList()) {
          final target = p.join(paths.rootfsDir, p.basename(child.path));
          await child.rename(target);
        }
        await singleDir.delete().catchError((_) => singleDir);
      }
    }
  }

  void validateRootfs() {
    final hasShell =
        File(p.join(paths.rootfsDir, 'bin', 'sh')).existsSync() ||
        File(p.join(paths.rootfsDir, 'usr', 'bin', 'sh')).existsSync();
    if (!hasShell) {
      throw const ExtractionException(
        'Invalid rootfs: missing /bin/sh or /usr/bin/sh. Ensure the archive is a valid Linux rootfs.',
      );
    }
  }
}
