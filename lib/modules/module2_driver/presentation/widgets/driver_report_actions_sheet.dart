import 'package:flutter/material.dart';

import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/widgets/driver_report_delay_sheet.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/widgets/driver_vehicle_breakdown_flow.dart';

/// The driver header's danger button opens this — a grid of report actions.
/// "Vehicle breakdown" and "Report delay" are wired; the rest are placeholders.
class DriverReportActionsSheet extends StatelessWidget {
  const DriverReportActionsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DriverReportActionsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CaptainTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                  color: CaptainTheme.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(
                'Report an issue',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: CaptainTheme.strongText,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _ActionCard(
                    icon: Icons.car_repair_rounded,
                    label: 'Vehicle breakdown',
                    color: CaptainTheme.danger,
                    onTap: () {
                      Navigator.of(context).pop();
                      DriverAssignmentPickerSheet.show(context);
                    },
                  ),
                  // Ranked second on purpose: a puncture or a hold-up happens
                  // far more often than a dead vehicle, and sitting beside
                  // "Vehicle breakdown" makes clear which to pick.
                  _ActionCard(
                    icon: Icons.timer_outlined,
                    label: 'Report delay',
                    color: CaptainTheme.warning,
                    onTap: () {
                      Navigator.of(context).pop();
                      DriverReportDelaySheet.show(context);
                    },
                  ),
                  _ActionCard(
                    icon: Icons.groups_2_rounded,
                    label: 'Extra staff',
                    color: CaptainTheme.info,
                    onTap: () => _comingSoon(context),
                  ),
                  _ActionCard(
                    icon: Icons.emergency_share_rounded,
                    label: 'Emergency',
                    color: CaptainTheme.danger,
                    onTap: () => _comingSoon(context),
                  ),
                  _ActionCard(
                    icon: Icons.more_horiz_rounded,
                    label: 'Others',
                    color: CaptainTheme.mutedText,
                    onTap: () => _comingSoon(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _comingSoon(BuildContext context) {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon.')),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CaptainTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CaptainTheme.hairline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: CaptainTheme.strongText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
