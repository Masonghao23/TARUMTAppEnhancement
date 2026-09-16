import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';
import '../providers.dart';

/// Staff-facing attendance analytics for one course at a time: how its
/// attendance has moved session by session, and how many of its students
/// are currently meeting the 80% requirement. Every figure is scoped
/// server-side to the courses the caller teaches (admin sees all).
///
/// One course filter at the top scopes both charts, so they always show
/// the same slice. Status colour (green = meeting 80%, red = below) is
/// always paired with a count and a label, never carried by colour alone.
class AttendanceChartsScreen extends ConsumerStatefulWidget {
  const AttendanceChartsScreen({super.key});

  @override
  ConsumerState<AttendanceChartsScreen> createState() =>
      _AttendanceChartsScreenState();
}

class _AttendanceChartsScreenState
    extends ConsumerState<AttendanceChartsScreen> {
  String? _courseId;

  Future<void> _refresh() async {
    ref.invalidate(courseAttendanceSummaryProvider);
    final id = _courseId;
    if (id != null) {
      ref.invalidate(courseAttendanceTrendProvider(id));
      ref.invalidate(courseStudentAttendanceProvider(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(courseAttendanceSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance charts')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: summaryAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorState(message: '$error'),
            data: (courses) {
              if (courses.isEmpty) {
                return const _EmptyState(
                  icon: Icons.insights_outlined,
                  message:
                      'No courses assigned to you yet — charts appear once '
                      'you have classes on your timetable.',
                );
              }
              // A course that disappeared (reassignment) would otherwise
              // leave both charts querying an id that's no longer visible.
              if (_courseId == null ||
                  !courses.any((c) => c.courseId == _courseId)) {
                _courseId = courses.first.courseId;
              }
              final courseId = _courseId!;

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _KpiRow(courses: courses),
                  const SizedBox(height: 20),
                  _FilterDropdown<String>(
                    icon: Icons.menu_book_outlined,
                    value: courseId,
                    items: [
                      for (final c in courses)
                        DropdownMenuItem(
                          value: c.courseId,
                          child: Text('${c.courseCode} · ${c.courseName}'),
                        ),
                    ],
                    onChanged: (id) => setState(() => _courseId = id),
                  ),
                  const SizedBox(height: 24),
                  _SectionHeading(
                    title: 'Trend over time',
                    subtitle: 'Share of enrolled students present at each '
                        'completed class. Students on leave aren\'t counted.',
                  ),
                  const SizedBox(height: 12),
                  _TrendSection(courseId: courseId),
                  const SizedBox(height: 28),
                  _SectionHeading(
                    title: 'Meeting the 80% requirement',
                    subtitle: 'Where this course\'s students stand right now.',
                  ),
                  const SizedBox(height: 12),
                  _StandingSection(courseId: courseId),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- KPI row

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.courses});

  final List<CourseAttendanceSummary> courses;

  @override
  Widget build(BuildContext context) {
    var attended = 0.0;
    var total = 0.0;
    for (final c in courses) {
      attended += c.attendedHours;
      total += c.totalHours;
    }
    final overall = total > 0 ? (attended / total) * 100 : null;

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            value: overall == null ? '—' : '${overall.toStringAsFixed(1)}%',
            label: 'Overall attendance',
            emphasis: overall != null && overall < 80,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            value: '${courses.length}',
            label: courses.length == 1 ? 'Course' : 'Courses',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    this.emphasis = false,
  });

  final String value;
  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: emphasis ? scheme.error : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- trend

class _TrendSection extends ConsumerStatefulWidget {
  const _TrendSection({required this.courseId});

  final String courseId;

  @override
  ConsumerState<_TrendSection> createState() => _TrendSectionState();
}

class _TrendSectionState extends ConsumerState<_TrendSection> {
  // Tracked by session id rather than list position: a refresh can add or
  // reorder sessions, and a stored index would then silently point the
  // open tooltip at a different class's numbers.
  String? _selectedSessionId;

  @override
  void didUpdateWidget(_TrendSection old) {
    super.didUpdateWidget(old);
    // Switching course invalidates whichever point was open.
    if (old.courseId != widget.courseId) _selectedSessionId = null;
  }

  void _handleTap(Offset position, Size size, List<AttendanceTrendPoint> pts) {
    final coords = _TrendPainter.pointOffsets(size, pts);
    int? nearest;
    var bestDistance = double.infinity;
    for (final entry in coords.entries) {
      final d = (entry.value - position).distance;
      // Hit target is deliberately far bigger than the 8px dot.
      if (d < 28 && d < bestDistance) {
        bestDistance = d;
        nearest = entry.key;
      }
    }
    final tappedId = nearest == null ? null : pts[nearest].sessionId;
    setState(() {
      // Tapping the open point (or empty space) closes the box.
      _selectedSessionId = tappedId == _selectedSessionId ? null : tappedId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trendAsync = ref.watch(
      courseAttendanceTrendProvider(widget.courseId),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: trendAsync.when(
        loading: () => const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => SizedBox(
          height: 120,
          child: Center(
            child: Text(
              'Could not load trend',
              style: TextStyle(color: scheme.error),
            ),
          ),
        ),
        data: (points) {
          if (points.isEmpty) {
            return const SizedBox(
              height: 120,
              child: Center(
                child: Text('No sessions held for this course yet.'),
              ),
            );
          }
          // Resolve the open session back to its current position; if a
          // refresh removed it, the tooltip simply closes.
          final found = _selectedSessionId == null
              ? -1
              : points.indexWhere((p) => p.sessionId == _selectedSessionId);
          final selected = found >= 0 ? found : null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 210,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) =>
                          _handleTap(d.localPosition, size, points),
                      child: CustomPaint(
                        size: size,
                        painter: _TrendPainter(
                          points: points,
                          selectedIndex: selected,
                          lineColor: scheme.primary,
                          gridColor: scheme.outlineVariant,
                          thresholdColor: scheme.onSurfaceVariant,
                          surfaceColor: scheme.surfaceContainerHigh,
                          tooltipColor: scheme.inverseSurface,
                          tooltipTextColor: scheme.onInverseSurface,
                          labelStyle: Theme.of(context).textTheme.bodySmall!,
                          endLabelStyle: Theme.of(context)
                              .textTheme
                              .labelMedium!
                              .copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap a point for that session\'s numbers.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.selectedIndex,
    required this.lineColor,
    required this.gridColor,
    required this.thresholdColor,
    required this.surfaceColor,
    required this.tooltipColor,
    required this.tooltipTextColor,
    required this.labelStyle,
    required this.endLabelStyle,
  });

  final List<AttendanceTrendPoint> points;
  final int? selectedIndex;
  final Color lineColor;
  final Color gridColor;
  final Color thresholdColor;
  final Color surfaceColor;
  final Color tooltipColor;
  final Color tooltipTextColor;
  final TextStyle labelStyle;
  final TextStyle endLabelStyle;

  static const _leftPad = 34.0;
  static const _rightPad = 12.0;
  static const _topPad = 14.0;
  // Reserved for the x-axis band so date labels are never clipped.
  static const _bottomPad = 26.0;

  /// Plotted position of every point that has a value, keyed by its index
  /// in [points]. Shared with the widget so tap hit-testing and painting
  /// can never drift apart.
  static Map<int, Offset> pointOffsets(
    Size size,
    List<AttendanceTrendPoint> points,
  ) {
    final plotLeft = _leftPad;
    final plotRight = size.width - _rightPad;
    final plotTop = _topPad;
    final plotBottom = size.height - _bottomPad;
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;
    final result = <int, Offset>{};
    if (plotWidth <= 0 || plotHeight <= 0) return result;

    for (var i = 0; i < points.length; i++) {
      final percent = points[i].attendancePercent;
      if (percent == null) continue;
      final x = points.length == 1
          ? plotLeft + plotWidth / 2
          : plotLeft + (i / (points.length - 1)) * plotWidth;
      final y = plotBottom - (percent.clamp(0, 100) / 100) * plotHeight;
      result[i] = Offset(x, y);
    }
    return result;
  }

  void _text(Canvas canvas, String s, Offset at, TextStyle style,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    var dx = at.dx;
    if (align == TextAlign.center) dx -= tp.width / 2;
    if (align == TextAlign.right) dx -= tp.width;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = _leftPad;
    final plotRight = size.width - _rightPad;
    final plotTop = _topPad;
    final plotBottom = size.height - _bottomPad;
    final plotHeight = plotBottom - plotTop;
    final plotWidth = plotRight - plotLeft;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    double yFor(double percent) =>
        plotBottom - (percent.clamp(0, 100) / 100) * plotHeight;

    // Recessive hairline grid at 0 / 50 / 100, solid (never dashed).
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final v in [0.0, 50.0, 100.0]) {
      final y = yFor(v);
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), grid);
      _text(canvas, '${v.toInt()}', Offset(plotLeft - 6, y - 7), labelStyle,
          align: TextAlign.right);
    }

    // The 80% requirement — a real threshold, so it gets its own rule in
    // neutral ink (not a second data hue) plus a label.
    final threshold = Paint()
      ..color = thresholdColor.withValues(alpha: 0.55)
      ..strokeWidth = 1.5;
    final ty = yFor(80);
    canvas.drawLine(Offset(plotLeft, ty), Offset(plotRight, ty), threshold);
    _text(canvas, '80%', Offset(plotRight, ty - 15), labelStyle,
        align: TextAlign.right);

    final offsets = pointOffsets(size, points);
    if (offsets.isEmpty) return;
    final coords = offsets.values.toList(growable: false);

    // Soft area under the single series, then the 2px line over it.
    if (coords.length > 1) {
      final area = Path()..moveTo(coords.first.dx, plotBottom);
      for (final c in coords) {
        area.lineTo(c.dx, c.dy);
      }
      area
        ..lineTo(coords.last.dx, plotBottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()..color = lineColor.withValues(alpha: 0.10),
      );

      final line = Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(coords.first.dx, coords.first.dy);
      for (final c in coords.skip(1)) {
        path.lineTo(c.dx, c.dy);
      }
      canvas.drawPath(path, line);
    }

    // Markers: 8px, each with a 2px surface ring so overlapping points
    // stay countable. The open one grows so it's obvious which is which.
    for (final entry in offsets.entries) {
      final isSelected = entry.key == selectedIndex;
      canvas.drawCircle(
        entry.value,
        isSelected ? 7 : 5,
        Paint()..color = surfaceColor,
      );
      canvas.drawCircle(
        entry.value,
        isSelected ? 6 : 4,
        Paint()..color = lineColor,
      );
    }

    // Direct-label the endpoint — so the latest figure is readable without
    // tapping anything. Hidden while a tooltip is open over that area.
    final lastIndex = points.lastIndexWhere((p) => p.attendancePercent != null);
    if (lastIndex >= 0 && selectedIndex == null) {
      final last = coords.last;
      final value = points[lastIndex].attendancePercent!;
      _text(
        canvas,
        '${value.toStringAsFixed(0)}%',
        Offset(last.dx, last.dy - 22),
        endLabelStyle,
        align: last.dx > plotRight - 30 ? TextAlign.right : TextAlign.center,
      );
    }

    final selected = selectedIndex;
    if (selected != null && offsets.containsKey(selected)) {
      _drawTooltip(canvas, size, offsets[selected]!, points[selected]);
    }

    // X axis: first and last dates only, so labels never collide.
    final first = points.first.sessionDate;
    final last = points.last.sessionDate;
    _text(canvas, '${first.day}/${first.month}',
        Offset(plotLeft, plotBottom + 8), labelStyle);
    if (points.length > 1) {
      _text(canvas, '${last.day}/${last.month}',
          Offset(plotRight, plotBottom + 8), labelStyle,
          align: TextAlign.right);
    }
  }

  /// The tap-to-reveal box, sitting above its dot. Clamped to the canvas so
  /// it never runs off the left/right edge, and flipped below the dot if
  /// there isn't room above.
  void _drawTooltip(
    Canvas canvas,
    Size size,
    Offset anchor,
    AttendanceTrendPoint point,
  ) {
    final titleStyle = labelStyle.copyWith(
      color: tooltipTextColor,
      fontWeight: FontWeight.w800,
    );
    final bodyStyle = labelStyle.copyWith(color: tooltipTextColor);

    final date =
        '${point.sessionDate.day}/${point.sessionDate.month}/'
        '${point.sessionDate.year}';
    final title = point.sessionType == null
        ? date
        : '$date · ${point.sessionType}';
    final present = '${point.attendedCount} of ${point.enrolledCount} present';
    final rate = point.attendancePercent == null
        ? '—'
        : '${point.attendancePercent!.toStringAsFixed(0)}% attendance';

    TextPainter tp(String s, TextStyle style) => TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final lines = [tp(title, titleStyle), tp(present, bodyStyle), tp(rate, bodyStyle)];
    const padH = 10.0, padV = 8.0, gap = 3.0, arrow = 6.0;
    final boxWidth =
        lines.map((l) => l.width).reduce((a, b) => a > b ? a : b) + padH * 2;
    final boxHeight =
        lines.fold<double>(0, (sum, l) => sum + l.height) + gap * 2 + padV * 2;

    final above = anchor.dy - arrow - boxHeight >= 0;
    final top = above
        ? anchor.dy - arrow - boxHeight
        : anchor.dy + arrow + 4;
    var left = anchor.dx - boxWidth / 2;
    left = left.clamp(0.0, (size.width - boxWidth).clamp(0.0, size.width));

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, boxWidth, boxHeight),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = tooltipColor);

    // Small pointer toward the dot.
    final tail = Path();
    if (above) {
      tail
        ..moveTo(anchor.dx - 5, top + boxHeight)
        ..lineTo(anchor.dx + 5, top + boxHeight)
        ..lineTo(anchor.dx, top + boxHeight + arrow);
    } else {
      tail
        ..moveTo(anchor.dx - 5, top)
        ..lineTo(anchor.dx + 5, top)
        ..lineTo(anchor.dx, top - arrow);
    }
    canvas.drawPath(tail..close(), Paint()..color = tooltipColor);

    var y = top + padV;
    for (final line in lines) {
      line.paint(canvas, Offset(left + padH, y));
      y += line.height + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.points != points ||
      old.selectedIndex != selectedIndex ||
      old.lineColor != lineColor;
}

// ------------------------------------------------ standing pie + list

/// Pie of how many of this course's students currently meet the 80%
/// requirement, with an expandable list of every student and their actual
/// percentage underneath. Green/red is the status encoding the user asked
/// for — it only appears alongside counts and labels, and the same two
/// colours repeat as the dot on each student row so the list and the pie
/// read as one thing.
class _StandingSection extends ConsumerStatefulWidget {
  const _StandingSection({required this.courseId});

  final String courseId;

  @override
  ConsumerState<_StandingSection> createState() => _StandingSectionState();
}

class _StandingSectionState extends ConsumerState<_StandingSection> {
  bool _detailsOpen = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final async = ref.watch(courseStudentAttendanceProvider(widget.courseId));
    final meetingColor = AppTheme.success(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: async.when(
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => SizedBox(
          height: 120,
          child: Center(
            child: Text(
              'Could not load students',
              style: TextStyle(color: scheme.error),
            ),
          ),
        ),
        data: (students) {
          if (students.isEmpty) {
            return const SizedBox(
              height: 120,
              child: Center(child: Text('Nobody is enrolled in this course.')),
            );
          }
          final meeting = students.where((s) => s.meetsThreshold).length;
          final below = students.where((s) => s.isBelowThreshold).length;
          final rated = meeting + below;

          if (rated == 0) {
            return const SizedBox(
              height: 120,
              child: Center(
                child: Text('No scheduled hours for this course yet.'),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 190,
                child: Row(
                  children: [
                    Expanded(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _PiePainter(
                          meeting: meeting,
                          below: below,
                          meetingColor: meetingColor,
                          belowColor: scheme.error,
                          gapColor: scheme.surfaceContainerHigh,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PieLegendRow(
                            color: meetingColor,
                            icon: Icons.check_circle_outline,
                            label: 'Meeting 80%',
                            count: meeting,
                            total: rated,
                          ),
                          const SizedBox(height: 14),
                          _PieLegendRow(
                            color: scheme.error,
                            icon: Icons.warning_amber_rounded,
                            label: 'Below 80%',
                            count: below,
                            total: rated,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Students with no scheduled hours yet belong to neither
              // slice; say so, or the pie's total silently disagrees with
              // the head-count in "Student details (N)" below.
              if (students.length > rated) ...[
                const SizedBox(height: 4),
                Text(
                  '${students.length - rated} '
                  '${students.length - rated == 1 ? 'student isn\'t' : 'students aren\'t'} '
                  'counted yet — no scheduled hours so far.',
                  style: textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 6),
              // The detail dropdown: every student with their real figure,
              // so the pie's two slices are never the only reading of it.
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                onTap: () => setState(() => _detailsOpen = !_detailsOpen),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Text(
                        'Student details (${students.length})',
                        style: textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Icon(
                        _detailsOpen
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              if (_detailsOpen) ...[
                Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < students.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _StudentStandingRow(
                    student: students[i],
                    meetingColor: meetingColor,
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PieLegendRow extends StatelessWidget {
  const _PieLegendRow({
    required this.color,
    required this.icon,
    required this.label,
    required this.count,
    required this.total,
  });

  final Color color;
  final IconData icon;
  final String label;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final share = total == 0 ? 0.0 : (count / total) * 100;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: textTheme.titleLarge?.copyWith(color: color),
              ),
              Text(label, style: textTheme.bodySmall),
              // The base is spelled out: students with no scheduled hours
              // yet sit in neither slice, so "of students" alone would
              // disagree with the head-count in "Student details (N)".
              Text(
                '${share.toStringAsFixed(0)}% of $total '
                '${total == 1 ? 'student' : 'students'}',
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudentStandingRow extends StatelessWidget {
  const _StudentStandingRow({
    required this.student,
    required this.meetingColor,
  });

  final CourseStudentAttendance student;
  final Color meetingColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final percent = student.attendancePercent;
    final color = student.meetsThreshold
        ? meetingColor
        : (student.isBelowThreshold ? scheme.error : scheme.onSurfaceVariant);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                student.studentName.isEmpty
                    ? '(No name set)'
                    : student.studentName,
                style: textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
              // One decimal when the hours aren't whole, so "8.5 of 9 hours"
              // lines up with the 94.4% beside it instead of rounding to a
              // pair of integers that imply a different percentage.
              Text(
                '${student.attendedHours.toStringAsFixed(student.attendedHours % 1 == 0 ? 0 : 1)} of '
                '${student.totalHours.toStringAsFixed(student.totalHours % 1 == 0 ? 0 : 1)} hours',
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          percent == null ? '—' : '${percent.toStringAsFixed(1)}%',
          style: textTheme.titleMedium?.copyWith(
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter({
    required this.meeting,
    required this.below,
    required this.meetingColor,
    required this.belowColor,
    required this.gapColor,
  });

  final int meeting;
  final int below;
  final Color meetingColor;
  final Color belowColor;
  final Color gapColor;

  @override
  void paint(Canvas canvas, Size size) {
    final total = meeting + below;
    if (total == 0) return;

    final radius = (size.shortestSide / 2) - 4;
    if (radius <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Start at 12 o'clock so the "meeting" slice reads clockwise from the
    // top, which is where people expect a pie to begin.
    const start = -math.pi / 2;
    final meetingSweep = (meeting / total) * 2 * math.pi;
    final belowSweep = (below / total) * 2 * math.pi;

    // When one slice is the whole pie it's drawn as a plain circle: an arc
    // with a full 2π sweep has been unreliable on the Impeller renderer and
    // can come out blank — exactly the common "everyone passes / everyone
    // is below 80%" case.
    if (below == 0) {
      canvas.drawCircle(center, radius, Paint()..color = meetingColor);
    } else if (meeting == 0) {
      canvas.drawCircle(center, radius, Paint()..color = belowColor);
    } else {
      canvas.drawArc(
        rect,
        start,
        meetingSweep,
        true,
        Paint()..color = meetingColor,
      );
      canvas.drawArc(
        rect,
        start + meetingSweep,
        belowSweep,
        true,
        Paint()..color = belowColor,
      );
    }

    // A 2px surface gap between the two slices instead of an outline, so
    // they separate without a border being drawn around the marks.
    if (meeting > 0 && below > 0) {
      final divider = Paint()
        ..color = gapColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      for (final angle in [start, start + meetingSweep]) {
        canvas.drawLine(
          center,
          center + Offset(radius * math.cos(angle), radius * math.sin(angle)),
          divider,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) =>
      old.meeting != meeting ||
      old.below != below ||
      old.meetingColor != meetingColor;
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- shared

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          'Could not load insights.\n$message',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.error),
        ),
      ),
    );
  }
}
