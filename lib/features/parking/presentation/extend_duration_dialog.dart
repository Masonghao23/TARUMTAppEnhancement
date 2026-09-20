import 'package:flutter/material.dart';

import '../data/parking_repository.dart';

/// Shows the reservation extension picker and returns the selected hours.
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
