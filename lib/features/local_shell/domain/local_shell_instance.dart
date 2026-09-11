class LocalShellInstance {
  const LocalShellInstance({
    required this.id,
    required this.distroId,
    required this.name,
    this.sourceUrl,
    this.sourceFilePath,
    this.baseProfileId,
  });

  final String id;
  final String distroId;
  final String name;
  final String? sourceUrl;
  final String? sourceFilePath;
  final String? baseProfileId;

  bool get isCustom =>
      sourceUrl != null ||
      sourceFilePath != null ||
      distroId == 'custom' ||
      distroId.startsWith('custom-');

  LocalShellInstance copyWith({
    String? name,
    String? sourceUrl,
    String? sourceFilePath,
    String? baseProfileId,
  }) =>
      LocalShellInstance(
        id: id,
        distroId: distroId,
        name: name ?? this.name,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        sourceFilePath: sourceFilePath ?? this.sourceFilePath,
        baseProfileId: baseProfileId ?? this.baseProfileId,
      );
}
