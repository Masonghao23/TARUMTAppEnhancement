import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';

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

  final bool allowTapWhenBlocked;

  static const double _cellW = 46;
  static const double _cellH = 78;
  static const double _rowGap = 46;
  static const double _margin = 56;
  static const double _topOffset = 48;

  /// Calculates the horizontal position of a parking slot.
  static double _left(num posX) => _margin + (posX - 1) * _cellW;
  /// Calculates the vertical position of a parking slot.
  static double _top(num posY) => _topOffset + (posY - 1) * (_cellH + _rowGap);

  /// Creates the mutable state for this widget.
  @override
  State<ParkingFloorMap> createState() => _ParkingFloorMapState();
}

class _ParkingFloorMapState extends State<ParkingFloorMap> {
  final _transformController = TransformationController();
  bool _didFitToView = false;

  /// Releases resources and subscriptions owned by this component.
  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  /// Scales and centers the floor plan to fit the viewport.
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

  /// Builds the parking floor map interface.
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

  /// Draws the floor outline on the canvas.
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

  /// Creates the floor outline around the parking slots.
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

    final rowMinX = <int, double>{};
    for (final s in slots) {
      final key = s.posY.round();
      final current = rowMinX[key];
      if (current == null || s.posX < current) rowMinX[key] = s.posX;
    }
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

  /// Checks whether changed painter inputs require repainting.
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

  /// Builds the slot tile interface.
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

  /// Builds the legend interface.
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

  /// Builds the legend item interface.
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
