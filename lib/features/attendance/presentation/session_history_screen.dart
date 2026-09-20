import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';
import 'manage_attendance_screen.dart';

class SessionHistoryScreen extends ConsumerStatefulWidget {
  const SessionHistoryScreen({super.key});

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<SessionHistoryScreen> createState() =>
      _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends ConsumerState<SessionHistoryScreen> {
  static const _pageSize = 20;

  String? _courseId;
  DateTime? _date;

  final List<ClassSession> _sessions = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _error = false;

  /// Initializes state and starts this component’s setup.
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  /// Loads a page of session history and updates pagination.
  Future<void> _load({required bool reset}) async {
    final lecturerId = ref.read(currentUserIdProvider);
    if (lecturerId == null) return;
    setState(() {
      if (reset) {
        _sessions.clear();
        _hasMore = true;
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = false;
    });
    try {
      final page = await ref
          .read(attendanceRepositoryProvider)
          .fetchSessionHistoryPage(
            lecturerId: lecturerId,
            courseId: _courseId,
            date: _date,
            offset: _sessions.length,
            limit: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        _sessions.addAll(page);
        _hasMore = page.length == _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  /// Opens a date picker and updates the selected date.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _load(reset: true);
    }
  }

  /// Formats a date for display.
  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Builds the session history screen interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coursesAsync = ref.watch(coursesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History Classes')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: coursesAsync.when(
                        data: (courses) => _CourseFilterDropdown(
                          courses: courses,
                          value: _courseId,
                          onChanged: (v) {
                            setState(() => _courseId = v);
                            _load(reset: true);
                          },
                        ),
                        loading: () => const SizedBox(
                          height: 44,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _DateFilterButton(
                      date: _date,
                      label: _date == null ? 'Any date' : _fmtDate(_date!),
                      onTap: _pickDate,
                      onClear: _date == null
                          ? null
                          : () {
                              setState(() => _date = null);
                              _load(reset: true);
                            },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error && _sessions.isEmpty
                    ? Center(
                        child: Text(
                          'Could not load sessions',
                          style: TextStyle(color: scheme.error),
                        ),
                      )
                    : _sessions.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 56,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _courseId == null && _date == null
                                ? 'No past class sessions yet'
                                : 'No sessions match your filters',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                        itemCount: _sessions.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (index >= _sessions.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Center(
                                child: _loadingMore
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: () => _load(reset: false),
                                        child: const Text('Load more'),
                                      ),
                              ),
                            );
                          }
                          return _EndedSessionTile(
                            session: _sessions[index],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseFilterDropdown extends StatelessWidget {
  const _CourseFilterDropdown({
    required this.courses,
    required this.value,
    required this.onChanged,
  });

  final List<Course> courses;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Builds the course filter dropdown interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          hint: const Text('All courses'),
          items: [
            const DropdownMenuItem(value: null, child: Text('All courses')),
            for (final course in courses)
              DropdownMenuItem(value: course.id, child: Text(course.label)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DateFilterButton extends StatelessWidget {
  const _DateFilterButton({
    required this.date,
    required this.label,
    required this.onTap,
    required this.onClear,
  });

  final DateTime? date;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  /// Builds the date filter button interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              if (onClear != null) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EndedSessionTile extends StatelessWidget {
  const _EndedSessionTile({required this.session});

  final ClassSession session;

  /// Formats a time for the timetable display.
  String _fmt(DateTime dt) {
    final local = dt.toLocal();
    final date =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date · $time';
  }

  /// Builds the ended session tile interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManageAttendanceScreen(
              sessionId: session.id,
              courseName: session.courseName,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  Icons.check_circle_outline,
                  color: scheme.onSurfaceVariant,
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
                      _fmt(session.startTime),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
