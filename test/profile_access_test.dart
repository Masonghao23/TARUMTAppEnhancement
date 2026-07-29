import 'package:app_enhancement/core/config/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'admin can authenticate and read own + directory profiles without RLS recursion',
    () async {
      final client = SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);

      final authResponse = await client.auth.signInWithPassword(
        email: 'admin@tarumt.edu.my',
        password: 'Testing123',
      );
      expect(authResponse.session, isNotNull, reason: 'Login should succeed.');

      final userId = authResponse.user!.id;

      final ownProfile = await client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      expect(ownProfile['role'], 'admin');

      // This is the exact query HomeShell/ProfileScreen depend on. It used to
      // throw PostgrestException 42P17 (infinite recursion detected in
      // policy for relation "profiles") before the current_user_role() fix.
      final directory = await client.from('profiles').select().order('name').limit(50);
      expect(directory, isA<List>());

      await client.auth.signOut();
    },
  );
}
