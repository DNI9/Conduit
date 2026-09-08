import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/app_lock/domain/app_authenticator.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:conduit/features/app_lock/presentation/lock_page.dart';
import 'package:conduit/features/backup/data/app_backup_service.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/hosts/presentation/hosts_page.dart';
import 'package:conduit/features/local_shell/presentation/local_shell_controller.dart';
import 'package:conduit/features/terminal/presentation/host_key_prompt_coordinator.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:conduit/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/test_doubles.dart';

class CallCountingAuthenticator implements AppAuthenticator {
  int authenticateCallCount = 0;
  int canAuthenticateCallCount = 0;
  bool shouldSucceed = true;

  @override
  Future<AppAuthenticationResult> authenticate() async {
    authenticateCallCount++;
    return shouldSucceed
        ? AppAuthenticationResult.success
        : AppAuthenticationResult.cancelled;
  }

  @override
  Future<bool> canAuthenticate() async {
    canAuthenticateCallCount++;
    return true;
  }
}

Widget buildTestApp({
  required AppLockController lockController,
  ThemeController? themeController,
  HostsController? hostsController,
}) {
  final effectiveThemeController =
      themeController ?? ThemeController(InMemoryThemePreferences());
  final effectiveHostsController =
      hostsController ?? HostsController(EmptyHostsRepository());
  final promptCoordinator = HostKeyPromptCoordinator();
  final verifier = NoopVerifier();

  return ConduitApp(
    lockController: lockController,
    themeController: effectiveThemeController,
    hostsController: effectiveHostsController,
    terminalRepository: NoNetworkTerminalRepository(),
    workspaceController: TerminalWorkspaceController(
      NoNetworkTerminalRepository(),
    ),
    localShellController: LocalShellController(),
    hostKeyVerifier: verifier,
    promptCoordinator: promptCoordinator,
    sftpRepository: NoNetworkSftpRepository(),
    backupService: AppBackupService(
      hostsController: effectiveHostsController,
      themeController: effectiveThemeController,
      hostKeyVerifier: verifier,
    ),
    fileExport: RecordingFileExport(),
  );
}

void main() {
  group('App Lock Launch Behavior', () {
    testWidgets(
      'launches directly to HostsPage without asking for auth when disabled by default',
      (tester) async {
        final authenticator = CallCountingAuthenticator();
        final repo = InMemoryAppLockRepository();
        final lockController = AppLockController(
          authenticator,
          repository: repo,
        );

        await tester.pumpWidget(buildTestApp(lockController: lockController));
        await tester.pumpAndSettle();

        expect(find.byType(LockPage), findsNothing);
        expect(find.byType(HostsPage), findsOneWidget);
        expect(find.text('Saved machines'), findsOneWidget);
        expect(authenticator.authenticateCallCount, 0);
      },
    );

    testWidgets(
      'prompts for authentication on launch and stays on LockPage when auth is cancelled',
      (tester) async {
        final authenticator = CallCountingAuthenticator()..shouldSucceed = false;
        final repo = InMemoryAppLockRepository(enabled: true);
        final lockController = AppLockController(
          authenticator,
          repository: repo,
          isLockEnabled: true,
        );

        await tester.pumpWidget(buildTestApp(lockController: lockController));
        await tester.pumpAndSettle();

        expect(find.byType(LockPage), findsOneWidget);
        expect(find.byType(HostsPage), findsNothing);
        expect(authenticator.authenticateCallCount, greaterThanOrEqualTo(1));
        expect(find.text('Authentication was cancelled.'), findsOneWidget);
      },
    );

    testWidgets(
      'unlocks and shows HostsPage when auth succeeds on launch',
      (tester) async {
        final authenticator = CallCountingAuthenticator()..shouldSucceed = true;
        final repo = InMemoryAppLockRepository(enabled: true);
        final lockController = AppLockController(
          authenticator,
          repository: repo,
          isLockEnabled: true,
        );

        await tester.pumpWidget(buildTestApp(lockController: lockController));
        await tester.pumpAndSettle();

        expect(find.byType(LockPage), findsNothing);
        expect(find.byType(HostsPage), findsOneWidget);
        expect(find.text('Saved machines'), findsOneWidget);
        expect(authenticator.authenticateCallCount, 1);
      },
    );

    testWidgets(
      'enabling app lock in settings causes subsequent lock/launch to require authentication',
      (tester) async {
        final authenticator = CallCountingAuthenticator()..shouldSucceed = true;
        final repo = InMemoryAppLockRepository();
        final lockController = AppLockController(
          authenticator,
          repository: repo,
        );

        await tester.pumpWidget(buildTestApp(lockController: lockController));
        await tester.pumpAndSettle();

        // Launched directly
        expect(find.byType(HostsPage), findsOneWidget);
        expect(authenticator.authenticateCallCount, 0);

        // Open settings
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();

        // Scroll to App Lock setting
        await tester.scrollUntilVisible(
          find.text('Require authentication on launch'),
          120,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();

        // Turn on
        await tester.tap(find.text('Require authentication on launch'));
        await tester.pumpAndSettle();

        expect(lockController.isLockEnabled, isTrue);
        expect(await repo.isLockEnabled(), isTrue);
        // Verified auth when turning on
        expect(authenticator.authenticateCallCount, 1);

        // Close settings sheet
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Verify lock icon is removed from home header
        expect(find.byTooltip('Lock'), findsNothing);

        // Simulate relaunching the app where auth fails/cancels
        authenticator.shouldSucceed = false;
        final lockedLaunchController = AppLockController(
          authenticator,
          repository: repo,
          isLockEnabled: await repo.isLockEnabled(),
        );
        await tester.pumpWidget(buildTestApp(lockController: lockedLaunchController));
        await tester.pumpAndSettle();

        expect(find.byType(LockPage), findsOneWidget);
        expect(find.byType(HostsPage), findsNothing);
        expect(authenticator.authenticateCallCount, 2);

        // Unlock on retry
        authenticator.shouldSucceed = true;
        await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
        await tester.pumpAndSettle();
        expect(find.byType(LockPage), findsNothing);
        expect(find.byType(HostsPage), findsOneWidget);
        expect(authenticator.authenticateCallCount, 3);
      },
    );
  });
}
