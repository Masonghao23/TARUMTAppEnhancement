import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// [identifier] is whatever the login screen's single field holds — an
  /// email, or a campus ID. Supabase Auth only signs in by email, so a
  /// non-email identifier is resolved to its owner's email first via
  /// `resolve_login_email` (a security-definer RPC, since profiles isn't
  /// publicly readable and this runs before the caller is authenticated).
  /// An unresolved campus ID throws AuthApiException with the same
  /// "invalid credentials" code Supabase itself uses for a wrong password,
  /// so the login screen's error handling doesn't need to change and a
  /// wrong campus ID looks identical to a wrong password to the user.
  Future<AuthResponse> signInWithPassword({
    required String identifier,
    required String password,
  }) async {
    final email = identifier.contains('@')
        ? identifier
        : await _resolveEmailForCampusId(identifier);
    if (email == null) {
      throw AuthApiException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      );
    }
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<String?> _resolveEmailForCampusId(String campusId) async {
    final result = await _client.rpc(
      'resolve_login_email',
      params: {'p_identifier': campusId},
    );
    return result as String?;
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(email);
  }

  /// Only valid mid password-recovery — the session at that point is the
  /// short-lived one Supabase grants after the reset-link exchange
  /// succeeds, not a normal sign-in. Emits AuthChangeEvent.userUpdated on
  /// success, which is what tells _AuthGate the recovery flow is done.
  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }
}
