import 'package:conduit/features/local_shell/domain/local_shell_paths.dart';
import 'package:conduit/features/local_shell/domain/rootfs_manifest.dart';

class LocalShellDistro {
  const LocalShellDistro({
    required this.id,
    required this.name,
    this.updateCommand = '',
    this.manifest,
    this.loginCommand = const ['/bin/bash', '--login'],
    this.setupCommands = const [],
    this.sourceUrl,
    this.sourceFilePath,
    this.baseProfileId,
  });

  final String id;
  final String name;
  final String updateCommand;
  final RootfsManifest? manifest;
  final List<String> loginCommand;
  final List<String> setupCommands;

  final String? sourceUrl;
  final String? sourceFilePath;
  final String? baseProfileId;

  bool get isCustom =>
      sourceUrl != null ||
      sourceFilePath != null ||
      id == 'custom' ||
      id.startsWith('custom-');
}

class LocalShellLaunch {
  const LocalShellLaunch({required this.distro, required this.paths});

  final LocalShellDistro distro;
  final LocalShellPaths paths;
}
