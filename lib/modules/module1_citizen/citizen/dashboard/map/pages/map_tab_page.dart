import 'package:flutter/material.dart';

import 'package:iwms_private_app/modules/module1_citizen/citizen/alloted_vehicle_map.dart';

/// Wrapper for the map tab to keep existing logic intact.
class MapTabPage extends StatelessWidget {
  const MapTabPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: CitizenAllotedVehicleMapScreen(onBack: onBack),
    );
  }
}
