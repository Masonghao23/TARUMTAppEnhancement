import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/data/models.dart';
import '../../user_management/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.staff:
        return 'Staff';
      case UserRole.student:
        return 'Student';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final profile = profileAsync.value;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary.withValues(alpha: 0.14),
                scheme.surfaceContainerHigh,
              ],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile == null
                    ? 'Welcome'
                    : 'Welcome, ${profile.name.isEmpty ? profile.email : profile.name}',
                style: textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                profile == null
                    ? 'Glad to have you here.'
                    : '${_roleLabel(profile.role)} account',
                style: textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
