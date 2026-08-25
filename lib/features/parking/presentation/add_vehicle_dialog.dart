import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Shows the add-vehicle dialog and, if confirmed, saves it and invalidates
/// [myVehiclesProvider]. Returns true if a vehicle was added.
Future<bool> showAddVehicleDialog(BuildContext context, WidgetRef ref) async {
  final plateController = TextEditingController();
  final modelController = TextEditingController();

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

  await ref
      .read(parkingRepositoryProvider)
      .addVehicle(
        plateNum: plateController.text,
        vehicleModel: modelController.text,
      );
  ref.invalidate(myVehiclesProvider);
  return true;
}
