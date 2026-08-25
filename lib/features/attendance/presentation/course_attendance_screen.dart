import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';

/// Stage 2 of the Timetable feature — the hour-based percentage per
/// enrolled course, same math as the Home ring (overallAttendanceHoursProvider)
/// just broken out instead of averaged.
class CourseAttendanceScreen extends ConsumerWidget {
  const CourseAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentId = ref.watch(currentUserIdProvider);
    if (studentId == null) return const SizedBox.shrink();

    final coursesAsync = ref.watch(myEnrolledCoursesProvider(studentId));
    final overallAsync = ref.watch(overallAttendanceHoursProvider(studentId));

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: SafeArea(
        child: coursesAsync.when(
          data: (courses) {
            if (courses.isEmpty) {
              return Center(
                child: Text(
                  'Not enrolled in any courses yet',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                _OverallCard(hours: overallAsync.value),
                const SizedBox(height: 16),
                for (final course in courses) ...[
                  _CourseRow(studentId: studentId, course: course),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Could not load courses: $error')),
        ),
      ),
    );
  }
}

/// Overall attendance across every enrolled course, in one bordered card —
/// the border/tint colour reflects the same 80% good/bad threshold as each
/// [_CourseRow] below it, so a struggling overall average is visible before
/// even reading the number.
class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.hours});

  final CourseAttendanceHours? hours;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = hours?.percent;
    final good = percent == null || percent >= 80;
    final accent = good ? AppTheme.success(context) : scheme.error;
    final tint = good ? AppTheme.successContainer(context) : scheme.errorContainer;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.donut_large_rounded, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Overall Attendance %',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                percent == null ? '—' : '${percent.round()}%',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: LinearProgressIndicator(
              value: percent == null ? 0 : (percent / 100).clamp(0, 1),
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hours == null
                ? 'Loading…'
                : '${hours!.attendedHours.toStringAsFixed(1)} / '
                      '${hours!.totalHours.toStringAsFixed(1)} hrs attended',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CourseRow extends ConsumerWidget {
  const _CourseRow({required this.studentId, required this.course});

  final String studentId;
  final Course course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hoursAsync = ref.watch(
      courseAttendanceHoursProvider((
        studentId: studentId,
        courseId: course.id,
      )),
    );
    final hours = hoursAsync.value;
    final percent = hours?.percent;
    final good = percent == null || percent >= 80;
    final barColor = good ? AppTheme.success(context) : scheme.error;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  course.courseName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: good
                      ? AppTheme.successContainer(context)
                      : scheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Text(
                  percent == null ? '—' : '${percent.round()}%',
                  style: TextStyle(
                    color: good
                        ? AppTheme.success(context)
                        : scheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: LinearProgressIndicator(
              value: percent == null ? 0 : (percent / 100).clamp(0, 1),
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hours == null
                ? 'Loading…'
                : '${hours.attendedHours.toStringAsFixed(1)} / '
                      '${hours.totalHours.toStringAsFixed(1)} hrs',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
