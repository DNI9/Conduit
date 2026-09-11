import 'package:conduit/features/local_shell/domain/local_shell_distro.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class LocalShellSetupRequest {
  const LocalShellSetupRequest({
    required this.distroId,
    required this.name,
    this.sourceUrl,
    this.sourceFilePath,
    this.baseProfileId,
  });

  final String distroId;
  final String name;
  final String? sourceUrl;
  final String? sourceFilePath;
  final String? baseProfileId;
}

class LocalShellSetupPage extends StatefulWidget {
  const LocalShellSetupPage({required this.controller, super.key});

  final LocalShellController controller;

  @override
  State<LocalShellSetupPage> createState() => _LocalShellSetupPageState();
}

class _LocalShellSetupPageState extends State<LocalShellSetupPage> {
  late String _distroId;
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  String? _selectedFilePath;
  String? _selectedBaseProfileId;
  bool _nameEdited = false;

  @override
  void initState() {
    super.initState();
    _distroId = widget.controller.catalog.first.id;
    _nameController = TextEditingController(text: _suggestedName(_distroId));
    _urlController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  String _suggestedName(String distroId) {
    final String baseName;
    if (distroId == 'custom') {
      if (_selectedBaseProfileId != null) {
        final base = widget.controller.distroById(_selectedBaseProfileId!);
        baseName = base != null ? '${base.name} (Custom)' : 'Custom Linux';
      } else if (_selectedFilePath != null) {
        final fileName = p.basenameWithoutExtension(_selectedFilePath!);
        baseName = fileName.replaceAll(RegExp(r'[\._-]'), ' ').trim();
      } else {
        baseName = 'Custom Linux';
      }
    } else {
      final distro = widget.controller.distroById(distroId);
      if (distro == null) return '';
      baseName = distro.name;
    }
    final taken = widget.controller.instances
        .map((instance) => instance.name)
        .toSet();
    if (!taken.contains(baseName)) return baseName;
    var suffix = 2;
    while (taken.contains('$baseName $suffix')) {
      suffix += 1;
    }
    return '$baseName $suffix';
  }

  void _selectDistro(String distroId) {
    setState(() {
      _distroId = distroId;
      if (!_nameEdited) {
        _nameController.text = _suggestedName(distroId);
      }
    });
  }

  Future<void> _pickLocalArchive() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tar', 'gz', 'xz', 'tgz'],
      );
      final path = result?.files.single.path;
      if (path != null && mounted) {
        setState(() {
          _selectedFilePath = path;
          _urlController.clear();
          if (!_nameEdited) {
            _nameController.text = _suggestedName('custom');
          }
        });
      }
    } catch (_) {}
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (_distroId == 'custom') {
      final url = _urlController.text.trim();
      final filePath = _selectedFilePath;
      if (url.isEmpty && (filePath == null || filePath.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a rootfs URL or choose a local archive.'),
          ),
        );
        return;
      }
      Navigator.of(context).pop(
        LocalShellSetupRequest(
          distroId: 'custom',
          name: name.isEmpty ? _suggestedName('custom') : name,
          sourceUrl: url.isNotEmpty ? url : null,
          sourceFilePath: filePath,
          baseProfileId: _selectedBaseProfileId,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      LocalShellSetupRequest(
        distroId: _distroId,
        name: name.isEmpty ? _suggestedName(_distroId) : name,
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.controller.distroById(_distroId);
    return Scaffold(
      appBar: AppBar(title: const Text('New local shell')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Run Linux on this phone',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A full Linux userland running locally through proot - no '
                'server, no root. Pick a distribution; you can set up as '
                'many shells as you like, including several of the same '
                'distribution.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              for (final distro in widget.controller.catalog) ...[
                _DistroOption(
                  distro: distro,
                  selected: distro.id == _distroId,
                  onTap: () => _selectDistro(distro.id),
                ),
                const SizedBox(height: 8),
              ],
              _CustomDistroOption(
                selected: _distroId == 'custom',
                onTap: () => _selectDistro('custom'),
              ),
              const SizedBox(height: 8),
              if (_distroId == 'custom') ...[
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Rootfs Source',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _urlController,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'Download URL (HTTP / HTTPS)',
                            hintText: 'https://example.com/rootfs.tar.xz',
                            helperText:
                                'Direct URL to a .tar.gz or .tar.xz archive.',
                            suffixIcon: _urlController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded),
                                    onPressed: () {
                                      setState(() {
                                        _urlController.clear();
                                      });
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (_) {
                            setState(() {
                              if (_urlController.text.trim().isNotEmpty) {
                                _selectedFilePath = null;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'OR',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickLocalArchive,
                                icon: const Icon(Icons.folder_open_rounded),
                                label: Text(
                                  _selectedFilePath != null
                                      ? p.basename(_selectedFilePath!)
                                      : 'Choose local archive (.tar.gz, .tar.xz)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (_selectedFilePath != null) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close_rounded),
                                tooltip: 'Clear selection',
                                onPressed: () {
                                  setState(() {
                                    _selectedFilePath = null;
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          initialValue: _selectedBaseProfileId,
                          decoration: const InputDecoration(
                            labelText: 'Base Profile (optional)',
                            helperText:
                                'Inherits setup commands, login shell, and update command.',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              child: Text('None (Generic Linux)'),
                            ),
                            for (final distro in widget.controller.catalog)
                              DropdownMenuItem<String?>(
                                value: distro.id,
                                child: Text(distro.name),
                              ),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedBaseProfileId = val;
                              if (!_nameEdited) {
                                _nameController.text =
                                    _suggestedName('custom');
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                onChanged: (_) => _nameEdited = true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  helperText: 'Shown on the home screen and terminal tabs.',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _distroId == 'custom' &&
                        _urlController.text.trim().isEmpty &&
                        (_selectedFilePath == null ||
                            _selectedFilePath!.isEmpty)
                    ? null
                    : _submit,
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  _distroId == 'custom'
                      ? 'Install'
                      : selected == null
                      ? 'Install'
                      : 'Install · ${formatLocalShellBytes(selected.manifest?.downloadSizeBytes)}',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'The image downloads once and unpacks on your device. '
                'Wi-Fi recommended.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DistroOption extends StatelessWidget {
  const _DistroOption({
    required this.distro,
    required this.selected,
    required this.onTap,
  });

  final LocalShellDistro distro;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.55)
                  : colorScheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      distro.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Download '
                      '${formatLocalShellBytes(distro.manifest?.downloadSizeBytes)}',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomDistroOption extends StatelessWidget {
  const _CustomDistroOption({
    required this.selected,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.55)
                  : colorScheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Custom (Bring your own rootfs)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Provide a direct URL or local .tar.gz / .tar.xz archive',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String formatLocalShellBytes(int? bytes) {
  if (bytes == null || bytes < -2 || bytes == 0) return 'unknown';
  if (bytes == -1) return '> 1 GB';
  if (bytes == -2) return 'calculating…';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final fixed = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$fixed ${units[unit]}';
}
