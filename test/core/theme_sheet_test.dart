import 'package:conduit/core/presentation/theme_sheet.dart';
import 'package:conduit/core/theme/terminal_appearance.dart';
import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/app_lock/domain/app_lock_repository.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_doubles.dart';

void main() {
  testWidgets('appearance sheet toggles local shell visibility', (
    tester,
  ) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Show local shell'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Show local shell'), findsOneWidget);
    expect(controller.showLocalShell, isTrue);

    await tester.tap(find.text('Show local shell'));
    await tester.pumpAndSettle();

    expect(controller.showLocalShell, isFalse);
  });

  testWidgets('appearance sheet toggles terminal mouse input', (tester) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Send mouse taps'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Send mouse taps'), findsOneWidget);
    expect(controller.terminalMouseInput, isFalse);

    await tester.tap(find.text('Send mouse taps'));
    await tester.pumpAndSettle();

    expect(controller.terminalMouseInput, isTrue);
  });

  testWidgets('appearance sheet toggles terminal standard keyboard', (
    tester,
  ) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Standard keyboard'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Standard keyboard'), findsOneWidget);
    expect(controller.terminalStandardKeyboard, isFalse);

    await tester.tap(find.text('Standard keyboard'));
    await tester.pumpAndSettle();

    expect(controller.terminalStandardKeyboard, isTrue);
  });

  testWidgets('appearance sheet changes terminal enter sequence', (
    tester,
  ) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Enter sends'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(controller.terminalEnterSequence, TerminalEnterSequence.cr);

    await tester.tap(find.text('CRLF'));
    await tester.pumpAndSettle();

    expect(controller.terminalEnterSequence, TerminalEnterSequence.crlf);
  });

  testWidgets('key row editor adds and saves a custom text key', (
    tester,
  ) async {
    final controller = ThemeController(InMemoryThemePreferences());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(context: context, controller: controller);
                  },
                  child: const Text('Appearance'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    final initialCount = controller.terminalKeyboardRows.first.items.length;
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Key Rows (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit keys'));
    await tester.pumpAndSettle();
    expect(find.text('Row 1 Keys ($initialCount)'), findsOneWidget);

    await tester.drag(
      find.byType(ReorderableListView).last,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Custom'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'gs');
    await tester.enterText(find.byType(TextField).at(1), 'git status');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('gs'), findsOneWidget);
    expect(find.text('Row 1 Keys (${initialCount + 1})'), findsOneWidget);
    expect(
      controller.terminalKeyboardRows.first.items.length,
      initialCount + 1,
    );
    expect(tester.getTopLeft(find.text('gs')).dy, greaterThanOrEqualTo(0));
    expect(
      tester.getBottomRight(find.text('gs')).dy,
      lessThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Done').last);
    await tester.pumpAndSettle();

    final custom = controller.terminalKeyboardRows.first.items.first;
    expect(custom.kind, TerminalKeyboardItemKind.customText);
    expect(custom.label, 'gs');
    expect(custom.text, 'git status');
  });

  testWidgets('settings sheet toggles app lock on and off', (tester) async {
    final themeController = ThemeController(InMemoryThemePreferences());
    await themeController.load();
    final repo = InMemoryAppLockRepository();
    final lockController = AppLockController(
      AlwaysAuthenticates(),
      repository: repo,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(
                      context: context,
                      controller: themeController,
                      lockController: lockController,
                    );
                  },
                  child: const Text('Settings'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Require authentication on launch'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Require authentication on launch'), findsOneWidget);
    expect(lockController.isLockEnabled, isFalse);

    // Toggle on
    await tester.tap(find.text('Require authentication on launch'));
    await tester.pumpAndSettle();

    expect(lockController.isLockEnabled, isTrue);
    expect(await repo.isLockEnabled(), isTrue);

    // Toggle off
    await tester.tap(find.text('Require authentication on launch'));
    await tester.pumpAndSettle();

    expect(lockController.isLockEnabled, isFalse);
    expect(await repo.isLockEnabled(), isFalse);
  });

  testWidgets('settings sheet shows snackbar when enabling app lock fails', (
    tester,
  ) async {
    final themeController = ThemeController(InMemoryThemePreferences());
    await themeController.load();
    final repo = InMemoryAppLockRepository();
    final lockController = AppLockController(
      UnavailableAuthenticator(),
      repository: repo,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(
                      context: context,
                      controller: themeController,
                      lockController: lockController,
                    );
                  },
                  child: const Text('Settings'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Require authentication on launch'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(lockController.isLockEnabled, isFalse);

    await tester.tap(find.text('Require authentication on launch'));
    await tester.pumpAndSettle();

    expect(lockController.isLockEnabled, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text(
        'Device authentication is not configured. Set a screen lock to enable app lock.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('settings sheet shows snackbar when setLockEnabled throws', (
    tester,
  ) async {
    final themeController = ThemeController(InMemoryThemePreferences());
    await themeController.load();
    final repo = _ThrowingAppLockRepository();
    final lockController = AppLockController(
      AlwaysAuthenticates(),
      repository: repo,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showThemeSheet(
                      context: context,
                      controller: themeController,
                      lockController: lockController,
                    );
                  },
                  child: const Text('Settings'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Require authentication on launch'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Require authentication on launch'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining(
        'Could not update app lock: Exception: storage disk failure',
      ),
      findsOneWidget,
    );
  });
}

class _ThrowingAppLockRepository implements AppLockRepository {
  @override
  Future<bool> isLockEnabled() async => false;

  @override
  Future<void> setLockEnabled(bool enabled) async {
    throw Exception('storage disk failure');
  }
}
