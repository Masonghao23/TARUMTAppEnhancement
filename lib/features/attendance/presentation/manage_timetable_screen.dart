import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers.dart';
import 'timetable_calendar_screen.dart';

class ManageTimetableScreen extends ConsumerStatefulWidget {
  const ManageTimetableScreen({super.key});

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<ManageTimetableScreen> createState() =>
      _ManageTimetableScreenState();
}

class _ManageTimetableScreenState extends ConsumerState<ManageTimetableScreen> {
  final Set<String> _selectedCourseIds = {};

  /// Opens the timetable calendar for the selected courses.
  void _continue() {
    final sortedIds = _selectedCourseIds.toList()..sort();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TimetableCalendarScreen(courseIdsKey: sortedIds.join(',')),
      ),
    );
  }

  /// Builds the manage timetable screen interface.
  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Timetable')),
      body: SafeArea(
        child: coursesAsync.when(
          data: (courses) {
            if (courses.isEmpty) {
              return Center(
                child: Text(
                  'No courses yet.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              );
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'Which courses do you want to manage?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'The calendar will highlight days with classes for '
                    'whichever courses you pick here.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    itemCount: courses.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final course = courses[index];
                      final selected = _selectedCourseIds.contains(course.id);
                      return Material(
                        color: selected
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          onTap: () => setState(() {
                            if (selected) {
                              _selectedCourseIds.remove(course.id);
                            } else {
                              _selectedCourseIds.add(course.id);
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selected
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  color: selected
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    course.label,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: ElevatedButton(
                    onPressed: _selectedCourseIds.isEmpty ? null : _continue,
                    child: const Text('Continue'),
                  ),
                ),
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
