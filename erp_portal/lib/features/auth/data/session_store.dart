import 'package:shared_preferences/shared_preferences.dart';

/// Remembers who chose "Keep me signed in" and which devices are trusted
/// for two-step sign-in. Browser storage on web.
///
/// Stores only IDs, never passwords or codes. With a real backend this
/// becomes a refresh token kept by the auth provider.
class SessionStore {
  SessionStore(this._prefs, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const _accountKey = 'session.accountId';
  static const _organizationKey = 'session.organizationId';
  static const _trustedPrefix = 'twoStep.trustedUntil.';
  static const trustDuration = Duration(days: 30);

  ({String accountId, String organizationId})? read() {
    final account = _prefs.getString(_accountKey);
    final organization = _prefs.getString(_organizationKey);
    if (account == null || organization == null) return null;
    return (accountId: account, organizationId: organization);
  }

  Future<void> save({
    required String accountId,
    required String organizationId,
  }) async {
    await _prefs.setString(_accountKey, accountId);
    await _prefs.setString(_organizationKey, organizationId);
  }

  Future<void> clear() async {
    await _prefs.remove(_accountKey);
    await _prefs.remove(_organizationKey);
  }

  /// "Don't ask again on this device for 30 days" (board S06).
  Future<void> trustDevice(String accountId) => _prefs.setString(
    '$_trustedPrefix$accountId',
    _now().add(trustDuration).toIso8601String(),
  );

  bool isTrusted(String accountId) {
    final raw = _prefs.getString('$_trustedPrefix$accountId');
    final until = raw == null ? null : DateTime.tryParse(raw);
    return until != null && _now().isBefore(until);
  }
}
