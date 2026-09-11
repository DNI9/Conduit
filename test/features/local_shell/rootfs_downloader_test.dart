import 'dart:io';

import 'package:conduit/features/local_shell/data/rootfs_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  group('HttpRootfsDownloader', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('conduit_downloader_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('downloads from arbitrary URL without manifest checksum', () async {
      final client = MockClient((request) async {
        expect(request.url, Uri.parse('https://example.com/custom-rootfs.tar.xz'));
        return http.Response.bytes(
          List<int>.filled(1024, 0x42),
          200,
          headers: {'content-length': '1024'},
        );
      });

      final downloader = HttpRootfsDownloader(client);
      final dest = p.join(tempDir.path, 'download.tar.xz');
      double lastProgress = 0;

      await downloader.download(
        sourceUrl: Uri.parse('https://example.com/custom-rootfs.tar.xz'),
        destination: dest,
        onProgress: (p) => lastProgress = p,
      );

      final downloaded = File(dest);
      expect(downloaded.existsSync(), isTrue);
      expect(downloaded.lengthSync(), 1024);
      expect(lastProgress, 1.0);
    });

    test('copies local file directly to destination without network', () async {
      final sourceFile = File(p.join(tempDir.path, 'source_rootfs.tar.gz'));
      await sourceFile.writeAsBytes(List<int>.filled(2048, 0x77));

      final downloader = HttpRootfsDownloader();
      final dest = p.join(tempDir.path, 'staging.tar.gz');
      double lastProgress = 0;

      await downloader.download(
        sourceFilePath: sourceFile.path,
        destination: dest,
        onProgress: (p) => lastProgress = p,
      );

      final staged = File(dest);
      expect(staged.existsSync(), isTrue);
      expect(staged.lengthSync(), 2048);
      expect(lastProgress, 1.0);
    });

    test('throws DownloadException when local source file does not exist', () async {
      final downloader = HttpRootfsDownloader();
      final dest = p.join(tempDir.path, 'staging.tar.gz');

      expect(
        () => downloader.download(
          sourceFilePath: p.join(tempDir.path, 'non_existent.tar.gz'),
          destination: dest,
        ),
        throwsA(isA<DownloadException>()),
      );
    });
  });
}
