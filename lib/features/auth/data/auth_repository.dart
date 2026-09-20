import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// Returns the current authentication session.
  Session? get currentSession => _client.auth.currentSession;

  /// Streams authentication state changes.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Signs in using an email address or campus ID and password.
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

  /// Resolves a campus ID to its sign-in email address.
  Future<String?> _resolveEmailForCampusId(String campusId) async {
    final result = await _client.rpc(
      'resolve_login_email',
      params: {'p_identifier': campusId},
    );
    return result as String?;
  }

  /// Sends a password recovery email.
  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(email);
  }

  /// Updates the user’s password during account recovery.
  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Signs out the current user.
  Future<void> signOut() {
    return _client.auth.signOut();
  }
}
