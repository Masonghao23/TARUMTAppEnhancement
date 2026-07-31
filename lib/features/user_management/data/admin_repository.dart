import 'package:supabase_flutter/supabase_flutter.dart';

class AdminCreateUserException implements Exception {
  const AdminCreateUserException(this.message);

  final String message;
}

class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  /// Only succeeds when the current session belongs to an admin — enforced
  /// server-side by the `admin-create-user` edge function, which is the only
  /// place the Supabase service role key is used.
  Future<String> createUser({
    required String email,
    required String password,
    required String name,
    required String campusId,
    required String role,
    List<String> courseIds = const [],
  }) async {
    try {
      final response = await _client.functions.invoke(
        'admin-create-user',
        body: {
          'email': email,
          'password': password,
          'name': name,
          'campusId': campusId,
          'role': role,
          if (courseIds.isNotEmpty) 'courseIds': courseIds,
        },
      );

      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw AdminCreateUserException(data['error'].toString());
      }
      if (data is Map && data['userId'] != null) {
        if (data['enrollmentWarning'] != null) {
          throw AdminCreateUserException(
            'Account created, but enrollment failed: '
            '${data['enrollmentWarning']}',
          );
        }
        return data['userId'].toString();
      }
      throw const AdminCreateUserException('Unexpected response from server.');
    } on FunctionException catch (e) {
      final details = e.details;
      final message = (details is Map && details['error'] != null)
          ? details['error'].toString()
          : (e.reasonPhrase ?? 'Failed to create user.');
      throw AdminCreateUserException(message);
    }
  }
}
