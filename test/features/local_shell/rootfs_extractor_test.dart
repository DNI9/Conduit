import 'dart:io';

import 'package:conduit/features/local_shell/data/rootfs_extractor.dart';
import 'package:conduit/features/local_shell/domain/local_shell_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ProotRootfsExtractor', () {
    late Directory tempDir;
    late LocalShellPaths paths;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('conduit_extractor_test_');
      paths = LocalShellPaths(
        instanceId: 'test-instance',
        nativeLibraryDir: tempDir.path,
        dataDir: tempDir.path,
      );
      await Directory(paths.tmpDir).create(recursive: true);
      await Directory(paths.rootfsDir).create(recursive: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('detectArchiveFormat identifies gzip, xz, tar, and unsupported', () async {
      final gzipFile = File(p.join(tempDir.path, 'test.tar.gz'));
      await gzipFile.writeAsBytes([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00]);
      expect(
        await ProotRootfsExtractor.detectArchiveFormat(gzipFile),
        ArchiveFormat.gzip,
      );

      final xzFile = File(p.join(tempDir.path, 'test.tar.xz'));
      await xzFile.writeAsBytes([0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00, 0x01]);
      expect(
        await ProotRootfsExtractor.detectArchiveFormat(xzFile),
        ArchiveFormat.xz,
      );

      final plainTar = File(p.join(tempDir.path, 'archive.tar'));
      await plainTar.writeAsBytes(List.filled(512, 0));
      expect(
        await ProotRootfsExtractor.detectArchiveFormat(plainTar),
        ArchiveFormat.tar,
      );

      final zipFile = File(p.join(tempDir.path, 'test.zip'));
      await zipFile.writeAsBytes([0x50, 0x4b, 0x03, 0x04]);
      expect(
        await ProotRootfsExtractor.detectArchiveFormat(zipFile),
        ArchiveFormat.unsupported,
      );
    });

    test('throws UnsupportedArchiveException on unsupported file format', () async {
      final file = File(paths.downloadPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes([0x50, 0x4b, 0x03, 0x04, 0x00]); // zip magic

      final extractor = ProotRootfsExtractor(paths);
      expect(
        extractor.extract,
        throwsA(isA<UnsupportedArchiveException>()),
      );
    });

    test('normalizes nested single directory containing bin/sh', () async {
      // Simulate extraction that resulted in a single nested folder: rootfs/alpine-3.20/bin/sh
      final nestedDir = Directory(p.join(paths.rootfsDir, 'alpine-3.20'));
      final nestedBin = Directory(p.join(nestedDir.path, 'bin'));
      await nestedBin.create(recursive: true);
      final sh = File(p.join(nestedBin.path, 'sh'));
      await sh.writeAsString('#!/bin/sh');

      final etc = Directory(p.join(nestedDir.path, 'etc'));
      await etc.create(recursive: true);
      await File(p.join(etc.path, 'os-release')).writeAsString('ID=alpine');

      final extractor = ProotRootfsExtractor(paths);
      expect(File(p.join(paths.rootfsDir, 'bin', 'sh')).existsSync(), isFalse);

      await extractor.normalizeExtractedDir();

      expect(File(p.join(paths.rootfsDir, 'bin', 'sh')).existsSync(), isTrue);
      expect(File(p.join(paths.rootfsDir, 'etc', 'os-release')).existsSync(), isTrue);
      expect(nestedDir.existsSync(), isFalse);
      expect(extractor.validateRootfs, returnsNormally);
    });

    test('validateRootfs throws ExtractionException when bin/sh is missing', () {
      final extractor = ProotRootfsExtractor(paths);
      expect(
        extractor.validateRootfs,
        throwsA(isA<ExtractionException>()),
      );
    });
  });
}
