import 'package:flutter/material.dart';

import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_crew_detail_sheet.dart';
import 'package:iwms_private_app/shared/widgets/crew_avatar_stack.dart';

/// Card representing one daily trip assignment in the supervisor's zones.
/// Ports OperatorTripSummaryCard's layout: a tinted status header bar, area
/// name + waste chip, and a compact staff/vehicle row.
class SupervisorAssignmentCard extends StatelessWidget {
  const SupervisorAssignmentCard({
    super.key,
    required this.assignment,
    this.onTap,
    this.onNavigate,
    this.onActions,
  });

  final SupervisorAssignment assignment;
  final VoidCallback? onTap;

  /// When provided, renders a "Navigate" button that opens the driver's live
  /// route map (remaining collection points + ORS routing).
  final VoidCallback? onNavigate;

  /// When provided, renders an "Actions" button (substitute staff/vehicle)
  /// alongside "Navigate".
  final VoidCallback? onActions;

  @override
  Widget build(BuildContext context) {
    final s = _StatusPalette.of(assignment.status);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: SupervisorTheme.cardRadius,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: SupervisorTheme.surface,
            borderRadius: SupervisorTheme.cardRadius,
            border: Border.all(color: SupervisorTheme.hairline),
            boxShadow: SupervisorTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status header bar
              Container(
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Icon(s.icon, size: 16, color: s.color),
                    const SizedBox(width: 6),
                    Text(
                      assignment.statusLabel.toUpperCase(),
                      style: TextStyle(
                        color: s.color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const Spacer(),
                    _collectionTypePill(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            assignment.areaName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: SupervisorTheme.strongText,
                            ),
                          ),
                        ),
                        if (assignment.wasteTypeName.isNotEmpty)
                          _wasteChip(assignment.wasteTypeName),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      assignment.zoneName.isNotEmpty
                          ? '${assignment.zoneName} · ${assignment.tripCode}'
                          : assignment.tripCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SupervisorTheme.mutedText,
                        fontSize: 11.5,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _staffRow(context),
                    if (assignment.hasBin || assignment.hasHousehold) ...[
                      const SizedBox(height: 10),
                      _progressRow(),
                    ],
                    if (assignment.isCompleted) ...[
                      const SizedBox(height: 8),
                      _completedDetailRow(),
                    ],
                  ],
                ),
              ),
              if (onNavigate != null || onActions != null) _buttonRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buttonRow() {
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: SupervisorTheme.accent,
      side: BorderSide(color: SupervisorTheme.accent.withValues(alpha: 0.4)),
      padding: const EdgeInsets.symmetric(vertical: 11),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Row(
        children: [
          if (onNavigate != null)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Navigate'),
                style: buttonStyle,
              ),
            ),
          if (onNavigate != null && onActions != null)
            const SizedBox(width: 10),
          if (onActions != null)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onActions,
                icon: const Icon(Icons.more_horiz_rounded, size: 18),
                label: const Text('Actions'),
                style: buttonStyle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _collectionTypePill() {
    final label = assignment.collectionTypeLabel;
    final isHousehold = assignment.hasHousehold && !assignment.hasBin;
    final color = isHousehold ? const Color(0xFF7C3AED) : const Color(0xFF0EA5E9);
    final icon = isHousehold ? Icons.home_outlined : Icons.delete_outline_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _staffRow(BuildContext context) {
    final crew = assignment.crew;
    final children = <Widget>[];
    if (crew != null &&
        (crew.driver != null ||
            crew.operator != null ||
            crew.extraOperators.isNotEmpty)) {
      children.addAll([
        CrewAvatarStack(
          crew: crew,
          size: 34,
          overlap: 18,
          borderColor: SupervisorTheme.surface,
          onTap: () => SupervisorCrewDetailSheet.show(context, crew),
        ),
        const SizedBox(width: 8),
      ]);
    }
    if (assignment.vehicleNo.isNotEmpty) {
      children.addAll([
        const Icon(Icons.local_shipping_outlined,
            size: 14, color: SupervisorTheme.mutedText),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            assignment.vehicleNo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: SupervisorTheme.mutedText,
            ),
          ),
        ),
      ]);
    }
    final staffName = assignment.driverName.isNotEmpty
        ? assignment.driverName
        : assignment.operatorName;
    if (staffName.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 12));
      children.addAll([
        const Icon(Icons.person_outline,
            size: 14, color: SupervisorTheme.mutedText),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            staffName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: SupervisorTheme.mutedText,
            ),
          ),
        ),
      ]);
    }
    if (children.isEmpty) {
      children.add(const Text(
        'No staff assigned',
        style: TextStyle(fontSize: 12, color: SupervisorTheme.mutedText),
      ));
    }
    return Row(children: children);
  }

  Widget _progressRow() {
    final wasteKg = assignment.totalCollectedWeightKg;
    final wasteLabel = wasteKg >= 10
        ? wasteKg.toStringAsFixed(0)
        : wasteKg.toStringAsFixed(1);
    return Row(
      children: [
        Expanded(
          child: _progressPill(
            icon: Icons.shopping_bag_outlined,
            color: const Color(0xFF0EA5E9),
            label: 'Waste',
            value: '$wasteLabel kg',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: assignment.hasBin
              ? _progressPill(
                  icon: Icons.delete_outline_rounded,
                  color: const Color(0xFF16A34A),
                  label: 'Bins',
                  value: '${assignment.binsCollected}/${assignment.binsTotal}',
                )
              : _progressPill(
                  icon: Icons.location_on_outlined,
                  color: SupervisorTheme.warning,
                  label: 'Stops',
                  value:
                      '${assignment.stopsCollected}/${assignment.stopsTotal}',
                ),
        ),
      ],
    );
  }

  /// Shown only once a trip is completed: how long it actually took, plus
  /// (when this assignment is itself a Re-Trip continuation) which attempt
  /// this was — e.g. "Trip 2" for the continuation of an earlier trip that
  /// was closed early. Ported from the government app's identically-named
  /// `_completedDetailRow` on its assignment card.
  Widget _completedDetailRow() {
    return Row(
      children: [
        Expanded(
          child: _progressPill(
            icon: Icons.timer_outlined,
            color: SupervisorTheme.accent,
            label: 'Trip time',
            value: _formatDuration(assignment.totalTripTimeSeconds),
          ),
        ),
        if (assignment.tripCount > 1) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _progressPill(
              icon: Icons.replay_rounded,
              color: SupervisorTheme.warning,
              label: 'Attempt',
              value: 'Trip ${assignment.tripCount}',
            ),
          ),
        ],
      ],
    );
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '—';
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Widget _progressPill({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _wasteChip(String waste) {
    final isWet = waste.toLowerCase().contains('wet');
    final color = isWet ? const Color(0xFF0EA5E9) : SupervisorTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: SupervisorTheme.chipRadius,
      ),
      child: Text(
        waste,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _StatusPalette {
  const _StatusPalette({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  static _StatusPalette of(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETED':
        return const _StatusPalette(
          color: SupervisorTheme.success,
          icon: Icons.check_circle_rounded,
        );
      case 'IN_PROGRESS':
        return const _StatusPalette(
          color: Color(0xFF0EA5E9),
          icon: Icons.directions_run_rounded,
        );
      case 'CANCELLED':
        return const _StatusPalette(
          color: SupervisorTheme.danger,
          icon: Icons.cancel_rounded,
        );
      default:
        return const _StatusPalette(
          color: SupervisorTheme.warning,
          icon: Icons.schedule_rounded,
        );
    }
  }
}
