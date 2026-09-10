import 'package:conduit/features/app_lock/domain/app_authenticator.dart';
import 'package:conduit/features/app_lock/domain/app_lock_repository.dart';
import 'package:flutter/foundation.dart';

enum AppLockStatus { locked, checking, unlocked, unavailable }

class AppLockController extends ChangeNotifier {
  AppLockController(
    this._authenticator, {
    this.repository,
    bool isLockEnabled = false,
  }) : _isLockEnabled = isLockEnabled,
       _status = isLockEnabled ? AppLockStatus.locked : AppLockStatus.unlocked;

  final AppAuthenticator _authenticator;
  final AppLockRepository? repository;

  bool _isLockEnabled;
  AppLockStatus _status;
  String? _message;

  bool get isLockEnabled => _isLockEnabled;
  AppLockStatus get status => _status;
  String? get message => _message;
  bool get isUnlocked => _status == AppLockStatus.unlocked;

  Future<void> load() async {
    if (repository == null) {
      return;
    }
    _isLockEnabled = await repository!.isLockEnabled();
    if (!isUnlocked) {
      _status = _isLockEnabled ? AppLockStatus.locked : AppLockStatus.unlocked;
    }
    _message = null;
    notifyListeners();
  }

  Future<bool> setLockEnabled(bool enabled) async {
    if (_isLockEnabled == enabled) {
      return true;
    }

    if (enabled) {
      final canAuthenticate = await _canAuthenticate();
      if (!canAuthenticate) {
        _message =
            'Device authentication is not configured. '
            'Set a screen lock to enable app lock.';
        notifyListeners();
        return false;
      }

      final result = await _authenticate();
      if (result != AppAuthenticationResult.success) {
        if (result == AppAuthenticationResult.cancelled) {
          _message = 'Authentication was cancelled.';
        } else {
          _message =
              'Device authentication is unavailable on this device. '
              'Set a screen lock for better protection.';
        }
        notifyListeners();
        return false;
      }
    }

    _isLockEnabled = enabled;
    _message = null;
    await repository?.setLockEnabled(enabled);
    notifyListeners();
    return true;
  }

  Future<void> unlock() async {
    if (_status == AppLockStatus.checking) {
      return;
    }

    _status = AppLockStatus.checking;
    _message = null;
    notifyListeners();

    final canAuthenticate = await _canAuthenticate();
    if (!canAuthenticate) {
      _status = AppLockStatus.unavailable;
      _message =
          'Device authentication is not configured. '
          'Set a screen lock to keep saved hosts private.';
      notifyListeners();
      return;
    }

    final result = await _authenticate();
    switch (result) {
      case AppAuthenticationResult.success:
        _status = AppLockStatus.unlocked;
        _message = null;
      case AppAuthenticationResult.cancelled:
        _status = AppLockStatus.locked;
        _message = 'Authentication was cancelled.';
      case AppAuthenticationResult.unavailable:
        _status = AppLockStatus.unavailable;
        _message =
            'Device authentication is unavailable on this device. '
            'Set a screen lock for better protection.';
    }
    notifyListeners();
  }

  Future<bool> _canAuthenticate() async {
    try {
      return await _authenticator.canAuthenticate();
    } catch (_) {
      return false;
    }
  }

  Future<AppAuthenticationResult> _authenticate() async {
    try {
      return await _authenticator.authenticate();
    } catch (_) {
      return AppAuthenticationResult.cancelled;
    }
  }

  void continueWithoutAuth() {
    if (_status != AppLockStatus.unavailable) {
      return;
    }
    _status = AppLockStatus.unlocked;
    notifyListeners();
  }

  void lock() {
    _status = AppLockStatus.locked;
    _message = null;
    notifyListeners();
  }
}
