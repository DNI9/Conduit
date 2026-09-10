import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/terminal/presentation/terminal_page.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/features/terminal/presentation/widgets/terminal_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  testWidgets('TerminalPage renders only a single TerminalSurface', (
    tester,
  ) async {
    final themeController = ThemeController(InMemoryThemePreferences());
    await themeController.load();
    final workspace = TerminalWorkspaceController(
      ImmediateTerminalRepository(FakeTerminalSession()),
    );
    addTearDown(workspace.dispose);

    final host1 = buildHost('host1');
    final host2 = buildHost('host2');

    workspace.open(host1);
    workspace.open(host2);

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalPage(
          workspace: workspace,
          themeController: themeController,
        ),
      ),
    );
    await tester.pump();

    // Verify there is exactly one TerminalSurface
    expect(find.byType(TerminalSurface), findsOneWidget);

    // Verify the active session is host2 (last opened)
    final terminalSurface = tester.widget<TerminalSurface>(
      find.byType(TerminalSurface),
    );
    expect(terminalSurface.key, ObjectKey(workspace.activeSession));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('TerminalPage re-renders TerminalSurface on tab switch', (
    tester,
  ) async {
    final themeController = ThemeController(InMemoryThemePreferences());
    await themeController.load();
    final workspace = TerminalWorkspaceController(
      ImmediateTerminalRepository(FakeTerminalSession()),
    );
    addTearDown(workspace.dispose);

    final host1 = buildHost('host1');
    final host2 = buildHost('host2');

    final session1 = workspace.open(host1);
    final session2 = workspace.open(host2); // Active initially

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalPage(
          workspace: workspace,
          themeController: themeController,
        ),
      ),
    );
    await tester.pump();

    // The TerminalSurface should correspond to session2
    var terminalSurface = tester.widget<TerminalSurface>(
      find.byType(TerminalSurface),
    );
    expect(terminalSurface.session.host.id, 'host2');
    expect(terminalSurface.key, ObjectKey(session2));

    // Switch to session1
    workspace.activate(session1);
    await tester.pump();

    // Verify there is still exactly one TerminalSurface
    expect(find.byType(TerminalSurface), findsOneWidget);

    // The TerminalSurface should correspond to session1
    terminalSurface = tester.widget<TerminalSurface>(
      find.byType(TerminalSurface),
    );
    expect(terminalSurface.session.host.id, 'host1');
    expect(terminalSurface.key, ObjectKey(session1));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
