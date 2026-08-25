import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/providers.dart';
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
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) =>
          Scaffold(body: Center(child: Text('Something went wrong: $error'))),
      data: (state) {
        final session =
            state.session ?? ref.read(authRepositoryProvider).currentSession;
        if (session == null) {
          return const LoginScreen();
        }
        return const HomeShell();
      },
    );
  }
}
