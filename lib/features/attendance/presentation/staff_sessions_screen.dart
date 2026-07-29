import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';
import 'live_session_screen.dart';

class StaffSessionsScreen extends ConsumerWidget {
  const StaffSessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final lecturerId = ref.watch(currentUserIdProvider);
    if (lecturerId == null) return const SizedBox.shrink();

    final sessionsAsync = ref.watch(mySessionsProvider(lecturerId));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(mySessionsProvider(lecturerId)),
      child: sessionsAsync.when(
        data: (sessions) {
          if (sessions.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              children: [
                Icon(
                  Icons.qr_code_2_rounded,
                  size: 56,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'No class sessions yet',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap "New session" to start taking attendance.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final session = sessions[index];
              return _SessionTile(session: session);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(
            'Could not load sessions',
            style: TextStyle(color: scheme.error),
          ),
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final ClassSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = session.status == SessionStatus.active;

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: isActive
            ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LiveSessionScreen(session: session),
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive
                      ? scheme.tertiaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  isActive ? Icons.sensors_rounded : Icons.check_circle_outline,
                  color: isActive
                      ? scheme.onTertiaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.courseName ?? 'Class session',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive
                          ? 'Live now${session.roomName != null ? ' · ${session.roomName}' : ''}'
                          : 'Ended',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: isActive ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActive)
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
