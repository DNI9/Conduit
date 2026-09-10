import 'package:conduit/features/app_lock/domain/app_authenticator.dart';
import 'package:conduit/features/app_lock/presentation/app_lock_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/test_doubles.dart';

void main() {
  group('AppLockController', () {
    test('unavailable device shows continue-anyway path', () async {
      final controller = AppLockController(UnavailableAuthenticator());
      await controller.unlock();
      expect(controller.status, AppLockStatus.unavailable);
      controller.continueWithoutAuth();
      expect(controller.isUnlocked, isTrue);
    });

    test('cancelled auth keeps the app locked', () async {
      final controller = AppLockController(
        ScriptedAuthenticator(AppAuthenticationResult.cancelled),
      );
      await controller.unlock();
      expect(controller.status, AppLockStatus.locked);
      expect(controller.message, isNotNull);
    });

    test('successful auth unlocks', () async {
      final controller = AppLockController(AlwaysAuthenticates());
      await controller.unlock();
      expect(controller.isUnlocked, isTrue);
    });

    test('auth errors return to the locked state', () async {
      final controller = AppLockController(const ThrowingAuthenticator());
      await controller.unlock();
      expect(controller.status, AppLockStatus.locked);
      expect(controller.message, isNotNull);
    });

    test('availability errors show the unavailable path', () async {
      final controller = AppLockController(
        const ThrowingAuthenticator(throwFromCanAuthenticate: true),
      );
      await controller.unlock();
      expect(controller.status, AppLockStatus.unavailable);
    });

    test('defaults to unlocked and disabled by default', () {
      final controller = AppLockController(AlwaysAuthenticates());
      expect(controller.isLockEnabled, isFalse);
      expect(controller.isUnlocked, isTrue);
      expect(controller.status, AppLockStatus.unlocked);
    });

    test('initializes as locked when isLockEnabled is true', () {
      final controller = AppLockController(
        AlwaysAuthenticates(),
        isLockEnabled: true,
      );
      expect(controller.isLockEnabled, isTrue);
      expect(controller.isUnlocked, isFalse);
      expect(controller.status, AppLockStatus.locked);
    });

    test(
      'load retrieves lock status from repository without re-locking unlocked session',
      () async {
        final repo = InMemoryAppLockRepository(enabled: true);
        final controller = AppLockController(
          AlwaysAuthenticates(),
          repository: repo,
          isLockEnabled: true,
        );
        expect(controller.isUnlocked, isFalse);
        expect(controller.status, AppLockStatus.locked);

        await controller.load();
        expect(controller.isLockEnabled, isTrue);
        expect(controller.isUnlocked, isFalse);

        await controller.unlock();
        expect(controller.isUnlocked, isTrue);

        // Calling load() while already unlocked should not re-lock
        await controller.load();
        expect(controller.isLockEnabled, isTrue);
        expect(controller.isUnlocked, isTrue);
      },
    );

    test('setLockEnabled(true) authenticates before enabling', () async {
      final repo = InMemoryAppLockRepository();
      final controller = AppLockController(
        AlwaysAuthenticates(),
        repository: repo,
      );

      final enabled = await controller.setLockEnabled(true);
      expect(enabled, isTrue);
      expect(controller.isLockEnabled, isTrue);
      expect(await repo.isLockEnabled(), isTrue);
    });

    test(
      'setLockEnabled(true) fails when device cannot authenticate',
      () async {
        final repo = InMemoryAppLockRepository();
        final controller = AppLockController(
          UnavailableAuthenticator(),
          repository: repo,
        );

        final enabled = await controller.setLockEnabled(true);
        expect(enabled, isFalse);
        expect(controller.isLockEnabled, isFalse);
        expect(await repo.isLockEnabled(), isFalse);
        expect(
          controller.message,
          contains('Device authentication is not configured'),
        );
      },
    );

    test(
      'setLockEnabled(true) fails when authentication is cancelled',
      () async {
        final repo = InMemoryAppLockRepository();
        final controller = AppLockController(
          ScriptedAuthenticator(AppAuthenticationResult.cancelled),
          repository: repo,
        );

        final enabled = await controller.setLockEnabled(true);
        expect(enabled, isFalse);
        expect(controller.isLockEnabled, isFalse);
        expect(await repo.isLockEnabled(), isFalse);
        expect(controller.message, contains('Authentication was cancelled'));
      },
    );

    test('setLockEnabled(false) disables lock without auth', () async {
      final repo = InMemoryAppLockRepository(enabled: true);
      final controller = AppLockController(
        AlwaysAuthenticates(),
        repository: repo,
        isLockEnabled: true,
      );

      final disabled = await controller.setLockEnabled(false);
      expect(disabled, isTrue);
      expect(controller.isLockEnabled, isFalse);
      expect(await repo.isLockEnabled(), isFalse);
    });
  });
}
