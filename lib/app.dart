import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/reset_password_screen.dart';
import 'features/auth/providers.dart';
import 'features/home/providers.dart' as home_providers;
import 'features/user_management/presentation/home_shell.dart';

class TarumtApp extends ConsumerWidget {
  const TarumtApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'TARUMT App Enhancement',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // signedIn only fires for an interactive sign-in (session restored on
    // cold start is initialSession instead), so this resets HomeShell back
    // to its Home tab on every real login — otherwise homeShellTabIndexProvider
    // (not autoDispose) would keep whatever tab a previous session left it
    // on if the user logs out and back in without restarting the app.
    ref.listen<AsyncValue<AuthState>>(authStateChangesProvider, (
      previous,
      next,
    ) {
      if (next.value?.event == AuthChangeEvent.signedIn) {
        ref.read(home_providers.homeShellTabIndexProvider.notifier).state = 2;
      }
    });

    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // A stale/reused/cross-browser reset link fails right here — Supabase
      // can't exchange it and the stream errors instead of emitting a
      // state. Recoverable: signing out clears whatever half-formed
      // session exists and pushes a fresh signedOut event, which flips
      // this back to the data branch below and lands on LoginScreen.
      error: (error, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.link_off_rounded,
                  size: 40,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'This link has expired or was already used',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Request a new password reset link and open it in the '
                  'same browser you requested it from.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () =>
                      ref.read(authRepositoryProvider).signOut(),
                  child: const Text('Back to sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (state) {
        final session =
            state.session ?? ref.read(authRepositoryProvider).currentSession;
        if (session == null) {
          return const LoginScreen();
        }
        // The session Supabase grants right after a reset-link exchange is
        // this recovery event — route to setting a new password instead of
        // straight into the app. Submitting there triggers userUpdated,
        // which replaces this event on the next stream tick and falls
        // through to HomeShell normally.
        if (state.event == AuthChangeEvent.passwordRecovery) {
          return const ResetPasswordScreen();
        }
        return const HomeShell();
      },
    );
  }
}
