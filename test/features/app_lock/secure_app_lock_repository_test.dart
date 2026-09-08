import 'package:conduit/features/app_lock/data/secure_app_lock_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureAppLockRepository', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('defaults to false when not set', () async {
      const repository = SecureAppLockRepository(FlutterSecureStorage());
      final isEnabled = await repository.isLockEnabled();
      expect(isEnabled, isFalse);
    });

    test('saves and loads true', () async {
      const repository = SecureAppLockRepository(FlutterSecureStorage());
      await repository.setLockEnabled(true);
      final isEnabled = await repository.isLockEnabled();
      expect(isEnabled, isTrue);
    });

    test('saves and loads false', () async {
      const repository = SecureAppLockRepository(FlutterSecureStorage());
      await repository.setLockEnabled(true);
      expect(await repository.isLockEnabled(), isTrue);

      await repository.setLockEnabled(false);
      expect(await repository.isLockEnabled(), isFalse);
    });
  });
}
