import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers.dart';
import 'add_vehicle_dialog.dart';

class VehicleManagementSection extends ConsumerWidget {
  const VehicleManagementSection({super.key});

  /// Builds the vehicle management section interface.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(myVehiclesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        vehiclesAsync.when(
          data: (vehicles) {
            if (vehicles.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No vehicles registered yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            return Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < vehicles.length; i++) ...[
                      if (i > 0) const Divider(indent: 56, height: 1),
                      ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                          ),
                          child: Icon(
                            Icons.directions_car_outlined,
                            size: 18,
                            color: scheme.primary,
                          ),
                        ),
                        title: Text(vehicles[i].plateNum),
                        subtitle: vehicles[i].vehicleModel?.isNotEmpty == true
                            ? Text(vehicles[i].vehicleModel!)
                            : null,
                        trailing: IconButton(
                          tooltip: 'Remove vehicle',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ref
                                .read(parkingRepositoryProvider)
                                .removeVehicle(vehicles[i].plateNum);
                            ref.invalidate(myVehiclesProvider);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('Could not load vehicles: $error'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => showAddVehicleDialog(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add vehicle'),
        ),
      ],
    );
  }
}
