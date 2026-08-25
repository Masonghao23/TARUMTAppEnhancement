import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';

/// Zoomable/pannable single-floor layout (pinch-zoom, drag to pan, like a
/// map) — grid positions come from parking_slots.pos_x/pos_y, laid out as
/// touching, line-marked bays (no gap within a row) inside a single building
/// outline traced from wherever the slots actually are, rather than a fixed
/// floor shape. Swap the slot positions in the DB for a different real
/// floor plan and the outline follows automatically. Opens zoomed out to
/// show the whole map, centered.
class ParkingFloorMap extends StatefulWidget {
  const ParkingFloorMap({
    super.key,
    required this.slots,
    this.selectedSlotId,
    this.onTapSlot,
    this.allowTapWhenBlocked = false,
  });

  final List<ParkingSlot> slots;
  final String? selectedSlotId;
  final ValueChanged<ParkingSlot>? onTapSlot;

  /// Staff "manage slots" mode needs to tap occupied/disabled slots too
  /// (to re-enable a disabled one, or inspect an occupied one) — normal
  /// booking mode keeps those blocked from tapping.
  final bool allowTapWhenBlocked;

  static const double _cellW = 46;
  static const double _cellH = 78;
  // Aisle gap between rows — slots within a row touch (no horizontal gap),
  // matching how the real bays are painted; only the drive aisle separates
  // one row from the next.
  static const double _rowGap = 46;
  static const double _margin = 56;
  static const double _topOffset = 48;

  static double _left(num posX) => _margin + (posX - 1) * _cellW;
  static double _top(num posY) => _topOffset + (posY - 1) * (_cellH + _rowGap);

  @override
  State<ParkingFloorMap> createState() => _ParkingFloorMapState();
}

class _ParkingFloorMapState extends State<ParkingFloorMap> {
  final _transformController = TransformationController();
  bool _didFitToView = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  /// Scales and centers the map so the whole floor plan is visible on
  /// first layout, instead of opening zoomed to the top-left corner.
  void _fitToView(Size viewport, double canvasWidth, double canvasHeight) {
    final scale = math.min(
      viewport.width / canvasWidth,
      viewport.height / canvasHeight,
    );
    final dx = (viewport.width - canvasWidth * scale) / 2;
    final dy = (viewport.height - canvasHeight * scale) / 2;
    _transformController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slots.isEmpty) {
      return const Center(child: Text('No parking slots configured yet.'));
    }

    final slots = widget.slots;
    final maxX = slots.map((s) => s.posX).reduce((a, b) => a > b ? a : b);
    final maxY = slots.map((s) => s.posY).reduce((a, b) => a > b ? a : b);
    final canvasWidth =
        ParkingFloorMap._margin * 2 + maxX * ParkingFloorMap._cellW;
    final canvasHeight =
        ParkingFloorMap._top(maxY) + ParkingFloorMap._cellH + 40;

    final scheme = Theme.of(context).colorScheme;

    // One label per row (pos_y), taken from the leading letter of any slot
    // number in that row (e.g. "A05" -> "A"), placed just left of the
    // row's leftmost slot. pos_y is stored as a double but always a whole
    // number, so it's rounded to use as a row key.
    final rowLabels = <int, String>{};
    final rowLeftmostX = <int, double>{};
    for (final slot in slots) {
      final rowKey = slot.posY.round();
      rowLabels.putIfAbsent(
        rowKey,
        () => slot.slotNumber.isNotEmpty ? slot.slotNumber[0] : '',
      );
      final current = rowLeftmostX[rowKey];
      if (current == null || slot.posX < current) {
        rowLeftmostX[rowKey] = slot.posX;
      }
    }

    return Column(
      children: [
        const _Legend(),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              if (!_didFitToView && viewport.width > 0 && viewport.height > 0) {
                _didFitToView = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _fitToView(viewport, canvasWidth, canvasHeight);
                  }
                });
              }
              return InteractiveViewer(
                transformationController: _transformController,
                constrained: false,
                minScale: 0.15,
                maxScale: 3,
                boundaryMargin: const EdgeInsets.all(120),
                child: SizedBox(
                  width: canvasWidth,
                  height: canvasHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _FloorOutlinePainter(
                            slots: slots,
                            fillColor: scheme.surfaceContainerHigh,
                            lineColor: scheme.outline,
                          ),
                        ),
                      ),
                      Positioned(
                        left: ParkingFloorMap._margin,
                        top: 8,
                        child: Text(
                          'GROUND FLOOR — ENTRY ▾',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      for (final entry in rowLabels.entries)
                        Positioned(
                          left:
                              ParkingFloorMap._left(rowLeftmostX[entry.key]!) -
                              22,
                          top:
                              ParkingFloorMap._top(entry.key) +
                              ParkingFloorMap._cellH / 2 -
                              8,
                          child: Text(
                            entry.value,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      for (final slot in slots)
                        Positioned(
                          left: ParkingFloorMap._left(slot.posX),
                          top: ParkingFloorMap._top(slot.posY),
                          width: ParkingFloorMap._cellW,
                          height: ParkingFloorMap._cellH,
                          child: _SlotTile(
                            slot: slot,
                            selected: slot.id == widget.selectedSlotId,
                            allowTapWhenBlocked: widget.allowTapWhenBlocked,
                            onTap: widget.onTapSlot == null
                                ? null
                                : () => widget.onTapSlot!(slot),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Traces a single building outline around whatever slots are actually
/// there — a wall that's narrower/tapered near the top-left corner (where
/// rows have fewer slots) and full width everywhere else, wide enough to
/// enclose every slot including any set off to the side. Those show up as
/// open floor space within the same outline, separated from the rest only
/// by the empty aisle between them — not a walled-off second room.
class _FloorOutlinePainter extends CustomPainter {
  _FloorOutlinePainter({
    required this.slots,
    required this.fillColor,
    required this.lineColor,
  });

  final List<ParkingSlot> slots;
  final Color fillColor;
  final Color lineColor;

  static const double _pad = 22;

  @override
  void paint(Canvas canvas, Size size) {
    if (slots.isEmpty) return;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final path = _outlinePath();
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  Path _outlinePath() {
    final minX = slots.map((s) => s.posX).reduce((a, b) => a < b ? a : b);
    final maxX = slots.map((s) => s.posX).reduce((a, b) => a > b ? a : b);
    final minY = slots
        .map((s) => s.posY)
        .reduce((a, b) => a < b ? a : b)
        .round();
    final maxY = slots
        .map((s) => s.posY)
        .reduce((a, b) => a > b ? a : b)
        .round();

    final left = ParkingFloorMap._left(minX) - _pad;
    final right = ParkingFloorMap._left(maxX) + ParkingFloorMap._cellW + _pad;
    final top = ParkingFloorMap._top(minY) - _pad;
    final bottom = ParkingFloorMap._top(maxY) + ParkingFloorMap._cellH + _pad;

    // Per-row leftmost column, to trace where the wall tapers inward near
    // the top — rows that only hold the main block stay narrow; any row
    // that also reaches a set-off block (e.g. a wing) is covered by the
    // shared right edge below, so the whole thing reads as one building.
    final rowMinX = <int, double>{};
    for (final s in slots) {
      final key = s.posY.round();
      final current = rowMinX[key];
      if (current == null || s.posX < current) rowMinX[key] = s.posX;
    }
    // First row (from the top) that reaches the overall left edge — above
    // it, the wall curves inward; from here down, it's straight.
    var taperEndY = maxY;
    for (var y = minY; y <= maxY; y++) {
      if (rowMinX[y] == minX) {
        taperEndY = y;
        break;
      }
    }

    final topLeft = Offset(ParkingFloorMap._left(rowMinX[minY]!) - _pad, top);
    final taperEnd = Offset(left, ParkingFloorMap._top(taperEndY) - _pad);
    final topRight = Offset(right, top);
    final bottomRight = Offset(right, bottom);
    final bottomLeft = Offset(left, bottom);

    final path = Path()..moveTo(topLeft.dx, topLeft.dy);
    if (taperEndY > minY) {
      path.cubicTo(
        topLeft.dx - 60,
        topLeft.dy + 20,
        taperEnd.dx - 10,
        taperEnd.dy - 40,
        taperEnd.dx,
        taperEnd.dy,
      );
    } else {
      path.lineTo(taperEnd.dx, taperEnd.dy);
    }
    path.lineTo(bottomLeft.dx, bottomLeft.dy);
    path.lineTo(bottomRight.dx, bottomRight.dy);
    path.lineTo(topRight.dx, topRight.dy);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _FloorOutlinePainter oldDelegate) =>
      oldDelegate.slots != slots ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.lineColor != lineColor;
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.slot,
    required this.selected,
    this.allowTapWhenBlocked = false,
    this.onTap,
  });

  final ParkingSlot slot;
  final bool selected;
  final bool allowTapWhenBlocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool disabled = !slot.isReservable;
    final bool blocked = disabled || slot.isOccupied;

    Color bg;
    Color fg;
    if (selected) {
      bg = scheme.primary;
      fg = scheme.onPrimary;
    } else if (disabled) {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant.withValues(alpha: 0.5);
    } else if (slot.isOccupied) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    } else {
      bg = AppTheme.successContainer(context);
      fg = AppTheme.success(context);
    }

    // Sharp-cornered and bordered, like an adjoining painted bay, rather
    // than a separated rounded icon card — tiles sit flush against each
    // other within a row, so each tile's own border reads as the shared
    // line between bays.
    return Material(
      color: bg,
      child: InkWell(
        onTap: blocked && !selected && !allowTapWhenBlocked ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                disabled ? Icons.block_outlined : Icons.directions_car_filled,
                color: fg,
                size: 16,
              ),
              const SizedBox(height: 2),
              Text(
                slot.slotNumber,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _LegendItem(
          color: AppTheme.successContainer(context),
          label: 'Available',
        ),
        _LegendItem(color: scheme.errorContainer, label: 'Occupied'),
        _LegendItem(color: scheme.surfaceContainerHighest, label: 'Disabled'),
        _LegendItem(color: scheme.primary, label: 'Selected'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
