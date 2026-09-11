import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalShellSetupRequest? result;

  Future<void> pumpSetupPage(
    WidgetTester tester,
    LocalShellController controller,
  ) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<LocalShellSetupRequest>(
                MaterialPageRoute(
                  builder: (_) => LocalShellSetupPage(controller: controller),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  String nameFieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller?.text ?? '';

  testWidgets('lists the catalog and prefills the name', (tester) async {
    final controller = LocalShellController();
    await pumpSetupPage(tester, controller);

    for (final distro in controller.catalog) {
      expect(find.text(distro.name), findsWidgets);
    }
    expect(nameFieldText(tester), 'Arch Linux');
  });

  testWidgets('selecting a distro updates the suggested name', (tester) async {
    await pumpSetupPage(tester, LocalShellController());

    await tester.tap(find.text('Debian'));
    await tester.pump();
    expect(nameFieldText(tester), 'Debian');
  });

  testWidgets('a custom name survives switching distros', (tester) async {
    await pumpSetupPage(tester, LocalShellController());

    await tester.enterText(find.byType(TextField), 'Sandbox');
    await tester.tap(find.text('Ubuntu'));
    await tester.pump();
    expect(nameFieldText(tester), 'Sandbox');
  });

  testWidgets('submitting returns the chosen distro and name', (tester) async {
    await pumpSetupPage(tester, LocalShellController());

    await tester.ensureVisible(find.text('Alpine Linux'));
    await tester.tap(find.text('Alpine Linux'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Tiny box');
    await tester.ensureVisible(find.textContaining('Install ·'));
    await tester.tap(find.textContaining('Install ·'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.distroId, 'alpine');
    expect(result!.name, 'Tiny box');
  });

  testWidgets('selecting custom reveals custom source fields and base profile',
      (tester) async {
    await pumpSetupPage(tester, LocalShellController());

    await tester.ensureVisible(find.text('Custom (Bring your own rootfs)'));
    expect(find.text('Custom (Bring your own rootfs)'), findsOneWidget);

    await tester.tap(find.text('Custom (Bring your own rootfs)'));
    await tester.pumpAndSettle();

    expect(find.text('Rootfs Source'), findsOneWidget);
    expect(find.text('Download URL (HTTP / HTTPS)'), findsOneWidget);
    expect(find.text('Base Profile (optional)'), findsOneWidget);
    expect(find.text('Choose local archive (.tar.gz, .tar.xz)'), findsOneWidget);

    // Enter custom URL
    await tester.enterText(
      find.widgetWithText(TextField, 'Download URL (HTTP / HTTPS)'),
      'https://example.com/fedora-rootfs.tar.xz',
    );
    await tester.pump();

    // Select Fedora as Base Profile
    final dropdownFinder = find.byType(DropdownButtonFormField<String?>);
    await tester.ensureVisible(dropdownFinder);
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fedora').last);
    await tester.pumpAndSettle();

    // Submit
    final submitButton = find.widgetWithText(FilledButton, 'Install');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.distroId, 'custom');
    expect(result!.sourceUrl, 'https://example.com/fedora-rootfs.tar.xz');
    expect(result!.baseProfileId, 'fedora');
  });

  testWidgets(
      'install button is disabled for custom distro until source provided',
      (tester) async {
    await pumpSetupPage(tester, LocalShellController());

    await tester.ensureVisible(find.text('Custom (Bring your own rootfs)'));
    await tester.tap(find.text('Custom (Bring your own rootfs)'));
    await tester.pumpAndSettle();

    final submitButton = find.widgetWithText(FilledButton, 'Install');
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Download URL (HTTP / HTTPS)'),
      'https://example.com/rootfs.tar.xz',
    );
    await tester.pump();

    expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull);
  });
}
