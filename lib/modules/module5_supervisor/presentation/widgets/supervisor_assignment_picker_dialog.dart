import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/screens/supervisor_trip_map_screen.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_assignment_detail_sheet.dart';

class SupervisorAssignmentPickerDialog {
  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<SupervisorAssignment> assignments,
    String? subtitle,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierLabel: title,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) {
        return _AssignmentPickerDialog(
          title: title,
          subtitle: subtitle,
          assignments: assignments,
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _AssignmentPickerDialog extends StatelessWidget {
  const _AssignmentPickerDialog({
    required this.title,
    required this.assignments,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<SupervisorAssignment> assignments;

  @override
  Widget build(BuildContext context) {
    final helperText = subtitle?.trim().isNotEmpty == true
        ? subtitle!
        : '${assignments.length} trip${assignments.length == 1 ? '' : 's'} assigned';
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.05),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: SupervisorTheme.surface.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: SupervisorTheme.hairline.withValues(alpha: 0.45),
                    ),
                    boxShadow: SupervisorTheme.elevatedShadow,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: SupervisorTheme.hairline,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: SupervisorTheme.strongText,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          helperText,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: SupervisorTheme.mutedText,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.separated(
                            itemCount: assignments.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _AssignmentPickerCard(
                              assignment: assignments[i],
                              onTap: () {
                                Navigator.of(context).pop();
                                SupervisorAssignmentDetailSheet.show(
                                  context,
                                  assignments[i],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AssignmentPickerCard extends StatelessWidget {
  const _AssignmentPickerCard({
    required this.assignment,
    required this.onTap,
  });

  final SupervisorAssignment assignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _AssignmentPalette.of(assignment);
    final totalStops = assignment.stops.length;
    final collectedStops = assignment.stops.where((s) => s.isCollected).length;
    final dateText = assignment.tripDate == null
        ? 'No date'
        : DateFormat('EEE, d MMM').format(assignment.tripDate!);
    final subtitleParts = <Widget>[
      if (assignment.vehicleNo.isNotEmpty) ...[
        const Icon(
          Icons.local_shipping_rounded,
          size: 15,
          color: SupervisorTheme.info,
        ),
        const SizedBox(width: 4),
        Text(
          assignment.vehicleNo,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: SupervisorTheme.strongText,
          ),
        ),
      ],
      if (assignment.scheduledTime.isNotEmpty) ...[
        if (assignment.vehicleNo.isNotEmpty) const SizedBox(width: 12),
        const Icon(
          Icons.schedule_rounded,
          size: 15,
          color: SupervisorTheme.info,
        ),
        const SizedBox(width: 4),
        Text(
          assignment.scheduledTime,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: SupervisorTheme.strongText,
          ),
        ),
      ],
      if (assignment.wasteTypeName.isNotEmpty) ...[
        if (assignment.vehicleNo.isNotEmpty || assignment.scheduledTime.isNotEmpty)
          const SizedBox(width: 12),
        const Icon(
          Icons.recycling_rounded,
          size: 15,
          color: SupervisorTheme.info,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            assignment.wasteTypeName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: SupervisorTheme.strongText,
            ),
          ),
        ),
      ],
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: SupervisorTheme.cardRadius,
        child: Container(
          decoration: BoxDecoration(
            color: SupervisorTheme.surface,
            borderRadius: SupervisorTheme.cardRadius,
            border: Border.all(color: palette.border),
            boxShadow: SupervisorTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: palette.tint,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.86),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(palette.icon, size: 16, color: palette.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            assignment.collectionTypeLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: palette.color,
                            ),
                          ),
                          _pill(assignment.statusLabel, SupervisorTheme.info),
                        ],
                      ),
                    ),
                    Text(
                      dateText,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: SupervisorTheme.strongText,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assignment.areaName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: SupervisorTheme.strongText,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            assignment.tripCode,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: SupervisorTheme.mutedText,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(children: subtitleParts),
                          const SizedBox(height: 10),
                          Text(
                            assignment.driverName.isNotEmpty
                                ? assignment.driverName
                                : assignment.operatorName,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: SupervisorTheme.mutedText,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SupervisorTripMapScreen(
                                      assignmentId: assignment.uniqueId,
                                      title: assignment.areaName,
                                      driverName: assignment.driverName,
                                      vehicleNo: assignment.vehicleNo,
                                      tripDate: assignment.tripDate,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.map_outlined, size: 16),
                              label: const Text('View on map'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: SupervisorTheme.info,
                                side: BorderSide(
                                  color:
                                      SupervisorTheme.info.withValues(alpha: 0.32),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (totalStops > 0) ...[
                      const SizedBox(width: 12),
                      _tripProgress(collectedStops, totalStops),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _tripProgress(int done, int total) {
    final ratio = total == 0 ? 0.0 : done / total;
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 62,
            height: 62,
            child: CircularProgressIndicator(
              value: ratio,
              strokeWidth: 5,
              backgroundColor: SupervisorTheme.hairline.withValues(alpha: 0.28),
              valueColor: AlwaysStoppedAnimation<Color>(
                ratio >= 1 ? SupervisorTheme.success : SupervisorTheme.info,
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$done/$total',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: SupervisorTheme.strongText,
                ),
              ),
              const Text(
                'STOPS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: SupervisorTheme.mutedText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssignmentPalette {
  const _AssignmentPalette({
    required this.color,
    required this.tint,
    required this.border,
    required this.icon,
  });

  final Color color;
  final Color tint;
  final Color border;
  final IconData icon;

  static _AssignmentPalette of(SupervisorAssignment assignment) {
    if (assignment.hasHousehold) {
      return _AssignmentPalette(
        color: SupervisorTheme.success,
        tint: SupervisorTheme.success.withValues(alpha: 0.10),
        border: SupervisorTheme.success.withValues(alpha: 0.22),
        icon: Icons.home_work_rounded,
      );
    }
    if (assignment.hasBin) {
      return _AssignmentPalette(
        color: SupervisorTheme.info,
        tint: SupervisorTheme.info.withValues(alpha: 0.08),
        border: SupervisorTheme.info.withValues(alpha: 0.20),
        icon: Icons.delete_outline_rounded,
      );
    }
    return _AssignmentPalette(
      color: SupervisorTheme.warning,
      tint: SupervisorTheme.warning.withValues(alpha: 0.08),
      border: SupervisorTheme.warning.withValues(alpha: 0.20),
      icon: Icons.route_rounded,
    );
  }
}
