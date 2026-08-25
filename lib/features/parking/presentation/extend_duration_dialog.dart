import 'package:flutter/material.dart';

import '../data/parking_repository.dart';

/// Shared +1/+2/+3 hour picker for extending a reservation — used by both
/// the active-session screen and the upcoming-reservation screen. This only
/// offers the choices and their preview cost; extend_parking_reservation on
/// the server is the actual authority on whether an extension is allowed
/// (no overlap with another booking, stays before midnight).
Future<int?> showExtendHoursDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Extend parking'),
      children: [1, 2, 3].map((hours) {
        final fee = ParkingRepository.previewFee(Duration(hours: hours));
        final label = hours == 1 ? '1 hour' : '$hours hours';
        return SimpleDialogOption(
          onPressed: () => Navigator.of(dialogContext).pop(hours),
          child: Text('+$label — RM${fee.toStringAsFixed(2)}'),
        );
      }).toList(),
    ),
  );
}
