import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/waste_type_visuals.dart';

/// The waste streams saved against a customer in Customer Creation, shown as
/// colour-coded chips so the driver can eyeball the expected segregation before
/// choosing an action.
///
/// Shared by every place a driver confirms a household customer — the
/// centralised scan button and the household list tap both open a "Confirm
/// customer" sheet, and both must show the same information.
///
/// Loads its own data: the sheet must open instantly on a QR scan, so this
/// starts as a slim skeleton row and swaps in the chips when the lookup lands.
/// A failed or empty lookup collapses the section entirely rather than showing
/// an error — it is supporting information, not a blocker.
class CustomerWasteTypesPanel extends StatefulWidget {
  const CustomerWasteTypesPanel({super.key, required this.customerId});

  final String customerId;

  @override
  State<CustomerWasteTypesPanel> createState() =>
      _CustomerWasteTypesPanelState();
}

class _CustomerWasteTypesPanelState extends State<CustomerWasteTypesPanel> {
  late final Future<List<CustomerWasteType>> _future;

  @override
  void initState() {
    super.initState();
    _future = GetIt.instance<OperatorTripRepository>()
        .fetchCustomerWasteTypes(widget.customerId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CustomerWasteType>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _shell(
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CaptainTheme.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading waste types…',
                  style: TextStyle(
                    color: CaptainTheme.mutedText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          );
        }

        final types = snapshot.data ?? const <CustomerWasteType>[];
        if (types.isEmpty) return const SizedBox.shrink();

        return _shell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 15,
                    color: CaptainTheme.mutedText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Registered waste types',
                    style: TextStyle(
                      color: CaptainTheme.mutedText,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${types.length}',
                    style: TextStyle(
                      color: CaptainTheme.mutedText,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in types) WasteTypeChip(name: type.name),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CaptainTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CaptainTheme.hairline),
      ),
      child: child,
    );
  }
}
