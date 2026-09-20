import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Shows the vehicle form and saves the vehicle when confirmed.
Future<bool> showAddVehicleDialog(BuildContext context, WidgetRef ref) async {
  final plateController = TextEditingController();
  final modelController = TextEditingController();

  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add vehicle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: plateController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Plate number'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelController,
              decoration: const InputDecoration(labelText: 'Model (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed != true || plateController.text.trim().isEmpty) return false;

    try {
      await ref
          .read(parkingRepositoryProvider)
          .addVehicle(
            plateNum: plateController.text,
            vehicleModel: modelController.text,
          );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not add vehicle. Please try again.'),
          ),
        );
      }
      return false;
    }

    ref.invalidate(myVehiclesProvider);
    return true;
  } finally {
    plateController.dispose();
    modelController.dispose();
  }
}
