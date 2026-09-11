import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/local_shell/data/local_shell_instance_store.dart';
import 'package:conduit/features/local_shell/local_shell_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LocalShellInstanceStore', () {
    late Directory tempDir;
    late LocalShellInstanceStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'conduit_instance_store_test_',
      );
      store = LocalShellInstanceStore(
        dataDir: tempDir.path,
        catalog: defaultLocalShellDistros(),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('ignores unrelated directories and files', () async {
      await Directory(p.join(tempDir.path, 'cache')).create();
      await Directory(p.join(tempDir.path, 'flutter_assets')).create();
      await File(p.join(tempDir.path, 'archlinux')).create();

      expect(await store.discover(), isEmpty);
    });

    test('legacy detection requires a rootfs directory', () async {
      await Directory(p.join(tempDir.path, 'archlinux')).create();
      expect(await store.discover(), isEmpty);

      await Directory(p.join(tempDir.path, 'archlinux', 'rootfs')).create();
      final instance = (await store.discover()).single;
      expect(instance.id, 'archlinux');
      expect(instance.distroId, 'archlinux');
      expect(instance.name, 'Arch Linux');
    });

    test('metadata rides over the legacy fallback', () async {
      await Directory(
        p.join(tempDir.path, 'alpine', 'rootfs'),
      ).create(recursive: true);
      await File(
        p.join(tempDir.path, 'alpine', LocalShellInstanceStore.metaFileName),
      ).writeAsString(jsonEncode({'distroId': 'alpine', 'name': 'Tiny box'}));

      final instance = (await store.discover()).single;
      expect(instance.name, 'Tiny box');
    });

    test('skips metadata naming an unknown distro', () async {
      await Directory(p.join(tempDir.path, 'mystery')).create();
      await File(
        p.join(tempDir.path, 'mystery', LocalShellInstanceStore.metaFileName),
      ).writeAsString(jsonEncode({'distroId': 'gentoo', 'name': 'Nope'}));

      expect(await store.discover(), isEmpty);
    });

    test('createInstance suffixes past occupied directories', () async {
      final catalog = defaultLocalShellDistros();
      final debian = catalog.singleWhere((distro) => distro.id == 'debian');

      final first = await store.createInstance(debian);
      expect(first.id, 'debian');
      expect(first.name, 'Debian');

      await Directory(p.join(tempDir.path, 'debian')).create();
      await Directory(p.join(tempDir.path, 'debian-2')).create();
      final third = await store.createInstance(debian);
      expect(third.id, 'debian-3');
      expect(third.name, 'Debian 3');

      final named = await store.createInstance(debian, name: '  Sandbox  ');
      expect(named.name, 'Sandbox');
    });

    test('persists and discovers custom distro configurations', () async {
      await Directory(p.join(tempDir.path, 'custom-1')).create();
      await File(
        p.join(tempDir.path, 'custom-1', LocalShellInstanceStore.metaFileName),
      ).writeAsString(
        jsonEncode({
          'distroId': 'custom-1',
          'name': 'My Custom Linux',
          'sourceUrl': 'https://example.com/rootfs.tar.xz',
          'sourceFilePath': '/tmp/rootfs.tar.gz',
          'baseProfileId': 'fedora',
        }),
      );

      final instances = await store.discover();
      expect(instances, hasLength(1));
      final custom = instances.first;
      expect(custom.id, 'custom-1');
      expect(custom.name, 'My Custom Linux');
      expect(custom.sourceUrl, 'https://example.com/rootfs.tar.xz');
      expect(custom.sourceFilePath, '/tmp/rootfs.tar.gz');
      expect(custom.baseProfileId, 'fedora');
      expect(custom.isCustom, isTrue);
    });
  });
}
