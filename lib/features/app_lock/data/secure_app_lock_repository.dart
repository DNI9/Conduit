import 'package:conduit/features/app_lock/domain/app_lock_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureAppLockRepository implements AppLockRepository {
  const SecureAppLockRepository(this._storage);

  static const _appLockEnabledKey = 'conduit.app_lock_enabled.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<bool> isLockEnabled() async {
    final raw = await _storage.read(key: _appLockEnabledKey);
    return raw == 'true';
  }

  @override
  Future<void> setLockEnabled(bool enabled) async {
    await _storage.write(
      key: _appLockEnabledKey,
      value: enabled ? 'true' : 'false',
    );
  }
}
