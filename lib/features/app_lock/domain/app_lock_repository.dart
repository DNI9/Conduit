abstract interface class AppLockRepository {
  Future<bool> isLockEnabled();

  Future<void> setLockEnabled(bool enabled);
}
