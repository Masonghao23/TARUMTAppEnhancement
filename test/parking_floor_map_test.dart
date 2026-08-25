import 'package:app_enhancement/features/parking/data/models.dart';
import 'package:app_enhancement/features/parking/presentation/parking_floor_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the row layout seeded in supabase/parking_schema.sql (main hall
/// rows A-G tapering near the curve, wing rows H/J past the corridor gap)
/// so this test exercises the exact same shape the outline painter has to
/// trace in production — without needing a live Supabase connection.
List<ParkingSlot> _seedLayout() {
  const rows = [
    ('A', 1, 6, 6),
    ('B', 2, 4, 8),
    ('C', 3, 2, 10),
    ('D', 4, 1, 11),
    ('E', 5, 1, 11),
    ('F', 6, 2, 10),
    ('G', 7, 2, 10),
    ('H', 5, 16, 9),
    ('J', 6, 16, 9),
  ];

  final slots = <ParkingSlot>[];
  var seed = 0;
  for (final (label, y, xStart, count) in rows) {
    for (var i = 0; i < count; i++) {
      seed++;
      final number = '$label${(i + 1).toString().padLeft(2, '0')}';
      slots.add(
        ParkingSlot(
          id: number,
          slotNumber: number,
          posX: (xStart + i).toDouble(),
          posY: y.toDouble(),
          // A mix of statuses, so the painter/tile both exercise every
          // colour branch (available/occupied/disabled), not just the
          // default case.
          isReservable: seed % 11 != 0,
          isOccupied: seed % 7 == 0,
        ),
      );
    }
  }
  return slots;
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(height: 600, child: child)));

void main() {
  testWidgets('renders the full 84-slot floor plan without throwing', (
    tester,
  ) async {
    final slots = _seedLayout();
    expect(slots, hasLength(84));

    await tester.pumpWidget(
      _wrap(ParkingFloorMap(slots: slots, onTapSlot: (_) {})),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('A01'), findsOneWidget);
    expect(find.text('J09'), findsOneWidget);
  });

  testWidgets('tapping an available slot fires onTapSlot', (tester) async {
    final slots = _seedLayout();
    ParkingSlot? tapped;

    await tester.pumpWidget(
      _wrap(ParkingFloorMap(slots: slots, onTapSlot: (s) => tapped = s)),
    );
    await tester.pump();

    // A01 is reservable and unoccupied by construction (seed 1: 1 % 11 !=
    // 0, 1 % 7 != 0).
    await tester.tap(find.text('A01'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tapped?.slotNumber, 'A01');
  });

  testWidgets('tapping a blocked slot does not fire onTapSlot', (
    tester,
  ) async {
    final slots = _seedLayout();
    // Seed 7 (G01, the 7th slot generated) is occupied by construction.
    final occupied = slots.firstWhere((s) => s.isOccupied);
    ParkingSlot? tapped;

    await tester.pumpWidget(
      _wrap(ParkingFloorMap(slots: slots, onTapSlot: (s) => tapped = s)),
    );
    await tester.pump();

    await tester.tap(find.text(occupied.slotNumber));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tapped, isNull);
  });

  testWidgets('renders a main-hall-only layout (no wing) without throwing', (
    tester,
  ) async {
    final slots = _seedLayout().where((s) => s.posX < 13).toList();

    await tester.pumpWidget(
      _wrap(ParkingFloorMap(slots: slots, onTapSlot: (_) {})),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a placeholder for an empty slot list', (tester) async {
    await tester.pumpWidget(
      _wrap(const ParkingFloorMap(slots: [], onTapSlot: null)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('No parking slots configured yet.'), findsOneWidget);
  });
}
