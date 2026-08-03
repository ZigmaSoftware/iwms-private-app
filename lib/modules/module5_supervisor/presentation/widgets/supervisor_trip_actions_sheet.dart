import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_substitute_staff_sheet.dart';

/// Trip card "Actions" — substitute staff or vehicle on [assignmentId].
/// Returns `true` if a substitution was applied, so the caller can refresh
/// its assignment list.
class SupervisorTripActionsSheet extends StatelessWidget {
  const SupervisorTripActionsSheet({super.key, required this.assignmentId});

  final String assignmentId;

  static Future<bool?> show(BuildContext context, {required String assignmentId}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupervisorTripActionsSheet(assignmentId: assignmentId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: SupervisorTheme.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: SupervisorTheme.strongText,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: _actionTile(
                icon: Icons.swap_horiz_rounded,
                label: 'Substitute staff',
                subtitle: 'Replace the driver/operator on this trip.',
                onTap: () async {
                  Navigator.of(context).pop();
                  final applied = await SupervisorSubstituteStaffSheet.show(
                    context,
                    assignmentId: assignmentId,
                  );
                  if (applied == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Staff substitution applied.'),
                      ),
                    );
                  }
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                16 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: _actionTile(
                icon: Icons.local_shipping_outlined,
                label: 'Substitute vehicle',
                subtitle: 'Replace the vehicle on this trip.',
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Vehicle substitution — coming soon.'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: SupervisorTheme.cardBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SupervisorTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: SupervisorTheme.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: SupervisorTheme.strongText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SupervisorTheme.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: SupervisorTheme.mutedText),
            ],
          ),
        ),
      ),
    );
  }
}
