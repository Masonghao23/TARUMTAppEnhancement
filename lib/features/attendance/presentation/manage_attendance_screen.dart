import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';
import '../providers.dart';

class ManageAttendanceScreen extends ConsumerStatefulWidget {
  const ManageAttendanceScreen({
    super.key,
    required this.sessionId,
    required this.courseName,
  });

  final String sessionId;
  final String? courseName;

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<ManageAttendanceScreen> createState() =>
      _ManageAttendanceScreenState();
}

class _ManageAttendanceScreenState
    extends ConsumerState<ManageAttendanceScreen> {
  final Set<String> _busyStudentIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  AttendanceStatus? _statusFilter;

  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  bool _bulkBusy = false;

  /// Releases resources and subscriptions owned by this component.
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Toggles bulk attendance selection mode.
  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selectedIds.clear();
    });
  }

  /// Adds or removes a student from the current selection.
  void _toggleSelected(String studentId) {
    setState(() {
      if (_selectedIds.contains(studentId)) {
        _selectedIds.remove(studentId);
      } else {
        _selectedIds.add(studentId);
      }
    });
  }

  /// Updates one student’s attendance status.
  Future<void> _setStatus(String studentId, AttendanceStatus status) async {
    setState(() => _busyStudentIds.add(studentId));
    try {
      final result = await ref
          .read(attendanceRepositoryProvider)
          .setAttendanceStatus(
            sessionId: widget.sessionId,
            studentId: studentId,
            status: status,
          );
      if (!mounted) return;
      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.reason ?? 'Could not update status.')),
        );
        return;
      }
      ref.invalidate(sessionRosterProvider(widget.sessionId));
    } finally {
      if (mounted) setState(() => _busyStudentIds.remove(studentId));
    }
  }

  /// Updates attendance for the selected students.
  Future<void> _bulkSetStatus(AttendanceStatus status) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    setState(() => _bulkBusy = true);
    try {
      final repo = ref.read(attendanceRepositoryProvider);
      final results = await Future.wait(
        ids.map(
          (id) => repo.setAttendanceStatus(
            sessionId: widget.sessionId,
            studentId: id,
            status: status,
          ),
        ),
      );
      if (!mounted) return;
      final failed = results.where((r) => !r.success).length;
      if (failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not update $failed of ${ids.length} students.',
            ),
          ),
        );
      }
      ref.invalidate(sessionRosterProvider(widget.sessionId));
    } finally {
      if (mounted) {
        setState(() {
          _bulkBusy = false;
          _selectedIds.clear();
          _selectMode = false;
        });
      }
    }
  }

  /// Shows the attendance status picker.
  Future<void> _pickStatus(RosterEntry entry) async {
    final picked = await showModalBottomSheet<AttendanceStatus>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    entry.studentName,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              for (final status in const [
                AttendanceStatus.present,
                AttendanceStatus.late,
                AttendanceStatus.absent,
                AttendanceStatus.leave,
              ])
                ListTile(
                  leading: Icon(
                    _statusIcon(status),
                    color: _statusColor(sheetContext, status),
                  ),
                  title: Text(status.label),
                  trailing: entry.status == status
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(status),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked != null && picked != entry.status) {
      await _setStatus(entry.studentId, picked);
    }
  }

  /// Returns the icon for the selected status.
  static IconData _statusIcon(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return Icons.check_circle_rounded;
      case AttendanceStatus.late:
        return Icons.schedule_rounded;
      case AttendanceStatus.absent:
        return Icons.cancel_rounded;
      case AttendanceStatus.leave:
        return Icons.event_busy_rounded;
      case AttendanceStatus.pending:
        return Icons.hourglass_empty_rounded;
    }
  }

  /// Returns the display color for the selected status.
  static Color _statusColor(BuildContext context, AttendanceStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case AttendanceStatus.present:
        return AppTheme.success(context);
      case AttendanceStatus.late:
        return scheme.tertiary;
      case AttendanceStatus.absent:
        return scheme.error;
      case AttendanceStatus.leave:
        return scheme.secondary;
      case AttendanceStatus.pending:
        return scheme.onSurfaceVariant;
    }
  }

  /// Builds the manage attendance screen interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rosterAsync = ref.watch(sessionRosterProvider(widget.sessionId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.courseName ?? 'Manage attendance'),
        actions: [
          IconButton(
            tooltip: _selectMode ? 'Cancel selection' : 'Select students',
            icon: Icon(
              _selectMode ? Icons.close_rounded : Icons.checklist_rounded,
            ),
            onPressed: _toggleSelectMode,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(sessionRosterProvider(widget.sessionId)),
          child: rosterAsync.when(
            data: (roster) {
              final query = _query.trim().toLowerCase();
              final filtered = roster.where((e) {
                if (_statusFilter != null && e.status != _statusFilter) {
                  return false;
                }
                if (query.isNotEmpty &&
                    !e.studentName.toLowerCase().contains(query)) {
                  return false;
                }
                return true;
              }).toList();

              if (roster.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                  children: [
                    Icon(
                      Icons.groups_outlined,
                      size: 56,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No students enrolled in this course',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search students by name',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        filled: true,
                        fillColor: scheme.surfaceContainerHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      children: [
                        _StatusFilterChip(
                          label: 'All',
                          selected: _statusFilter == null,
                          onSelected: () =>
                              setState(() => _statusFilter = null),
                        ),
                        for (final status in const [
                          AttendanceStatus.present,
                          AttendanceStatus.late,
                          AttendanceStatus.absent,
                          AttendanceStatus.leave,
                          AttendanceStatus.pending,
                        ]) ...[
                          const SizedBox(width: 8),
                          _StatusFilterChip(
                            label: status.label,
                            color: _statusColor(context, status),
                            selected: _statusFilter == status,
                            onSelected: () =>
                                setState(() => _statusFilter = status),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_selectMode)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Row(
                        children: [
                          Text(
                            '${_selectedIds.length} selected',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() {
                              final allIds = filtered
                                  .map((e) => e.studentId)
                                  .toSet();
                              if (_selectedIds.containsAll(allIds) &&
                                  allIds.isNotEmpty) {
                                _selectedIds.removeAll(allIds);
                              } else {
                                _selectedIds.addAll(allIds);
                              }
                            }),
                            child: const Text('Select all shown'),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: filtered.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                            children: [
                              Text(
                                'No students match your filters',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final entry = filtered[index];
                              final busy = _busyStudentIds.contains(
                                entry.studentId,
                              );
                              return _RosterTile(
                                entry: entry,
                                busy: busy,
                                color: _statusColor(context, entry.status),
                                icon: _statusIcon(entry.status),
                                selectMode: _selectMode,
                                selected: _selectedIds.contains(
                                  entry.studentId,
                                ),
                                onTap: busy
                                    ? null
                                    : _selectMode
                                    ? () => _toggleSelected(entry.studentId)
                                    : () => _pickStatus(entry),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Text(
                'Could not load roster',
                style: TextStyle(color: scheme.error),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _selectMode && _selectedIds.isNotEmpty
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                ),
                child: _bulkBusy
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final status in const [
                            AttendanceStatus.present,
                            AttendanceStatus.late,
                            AttendanceStatus.absent,
                            AttendanceStatus.leave,
                          ])
                            FilledButton.tonalIcon(
                              onPressed: () => _bulkSetStatus(status),
                              icon: Icon(_statusIcon(status), size: 18),
                              label: Text(
                                'Mark ${status.label} (${_selectedIds.length})',
                              ),
                            ),
                        ],
                      ),
              ),
            )
          : null,
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Color? color;

  /// Builds the status filter chip interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? accent : scheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12.5,
      ),
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: accent.withValues(alpha: 0.14),
      side: BorderSide(color: selected ? accent : Colors.transparent),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({
    required this.entry,
    required this.busy,
    required this.color,
    required this.icon,
    required this.onTap,
    this.selectMode = false,
    this.selected = false,
  });

  final RosterEntry entry;
  final bool busy;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selectMode;
  final bool selected;

  /// Builds the roster tile interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.4)
          : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (selectMode) ...[
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.studentName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (entry.isManual)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Edited by lecturer',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 6),
                      Text(
                        entry.status.label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
