import 'package:flutter/material.dart';

import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';

/// One row in the floating waste-breakdown window.
class WasteBreakdownRow {
  const WasteBreakdownRow({required this.wasteType, required this.weightKg});

  final String wasteType;
  final double weightKg;
}

/// The "eye" button's floating window — a compact centered card (not a
/// full-width bottom sheet, so it reads as a quick glance rather than another
/// screen to navigate) listing what was collected, split by waste type.
///
/// Used from both `_StopTile` (bin — always exactly one row, the bin's own
/// waste type) and `_HouseholdTile` (household — one row per waste type
/// actually captured, from `OperatorTripHouseholdStop.wasteBreakdown`).
Future<void> showWasteBreakdownWindow(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<WasteBreakdownRow> rows,
}) {
  final total = rows.fold<double>(0, (sum, r) => sum + r.weightKg);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: CaptainTheme.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: CaptainTheme.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_rounded,
                    size: 20, color: CaptainTheme.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: CaptainTheme.strongText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CaptainTheme.mutedText,
              ),
            ),
            const SizedBox(height: 14),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'No waste-type breakdown was recorded for this collection.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: CaptainTheme.mutedText,
                  ),
                ),
              )
            else ...[
              for (final row in rows) _WasteBreakdownTile(row: row),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: CaptainTheme.strongText,
                    ),
                  ),
                  Text(
                    '${total.toStringAsFixed(2)} kg',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: CaptainTheme.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WasteBreakdownTile extends StatelessWidget {
  const _WasteBreakdownTile({required this.row});

  final WasteBreakdownRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: CaptainTheme.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.wasteType,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: CaptainTheme.strongText,
              ),
            ),
          ),
          Text(
            '${row.weightKg.toStringAsFixed(2)} kg',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: CaptainTheme.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}
