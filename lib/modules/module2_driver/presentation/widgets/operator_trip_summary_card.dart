import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/theme/captain_theme.dart';

class OperatorTripSummaryCard extends StatelessWidget {
  const OperatorTripSummaryCard({
    super.key,
    required this.trip,
    this.onTap,
  });

  final OperatorTripHistorySummary trip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = _StatusPalette.of(trip.status);
    final statusText = trip.status.trim();
    final assignmentTypeLabel = trip.assignmentTypeLabel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: CaptainTheme.cardRadius,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: CaptainTheme.surface,
            borderRadius: CaptainTheme.cardRadius,
            border: Border.all(color: CaptainTheme.hairline),
            boxShadow: CaptainTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    if (statusText.isNotEmpty) ...[
                      Icon(s.icon, size: 16, color: s.color),
                      const SizedBox(width: 6),
                      Text(
                        statusText.toUpperCase(),
                        style: TextStyle(
                          color: s.color,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 12,
                      color: CaptainTheme.mutedText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _dateLabel(trip.tripDate),
                      style: TextStyle(
                        color: CaptainTheme.mutedText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                            trip.areaName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: CaptainTheme.strongText,
                            ),
                          ),
                        ),
                        if (assignmentTypeLabel.isNotEmpty)
                          _assignmentTypeChip(assignmentTypeLabel),
                      ],
                    ),
                    if (trip.assignmentUniqueId.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        trip.assignmentUniqueId,
                        style: TextStyle(
                          color: CaptainTheme.mutedText,
                          fontSize: 11.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        if (trip.vehicle != null)
                          _metaItem(
                            icon: Icons.local_shipping_outlined,
                            text: trip.vehicle!.vehicleNo,
                          ),
                        if (trip.staff?.driver != null)
                          _metaItem(
                            icon: Icons.person_outline,
                            text: trip.staff!.driver!.displayName,
                          ),
                        if (trip.wasteType.name.trim().isNotEmpty)
                          _metaItem(
                            icon: Icons.recycling_rounded,
                            text: trip.wasteType.name,
                          ),
                        if ((trip.scheduledTime ?? '').trim().isNotEmpty)
                          _metaItem(
                            icon: Icons.schedule_rounded,
                            text: _formatTime(trip.scheduledTime!),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.task_alt_rounded,
                          size: 13,
                          color: CaptainTheme.mutedText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${trip.progress.collected}/${trip.progress.total} stops',
                          style: TextStyle(
                            color: CaptainTheme.mutedText,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${trip.totalWeightKg.toStringAsFixed(2)} kg',
                          style: TextStyle(
                            fontSize: 13,
                            color: CaptainTheme.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: trip.progress.fraction,
                        backgroundColor: CaptainTheme.hairline,
                        valueColor: AlwaysStoppedAnimation(s.color),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assignmentTypeChip(String label) {
    final color = _assignmentTypeColor(trip.collectionType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: CaptainTheme.chipRadius,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _metaItem({
    required IconData icon,
    required String text,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: CaptainTheme.mutedText),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: CaptainTheme.mutedText,
            ),
          ),
        ),
      ],
    );
  }

  Color _assignmentTypeColor(String? type) {
    switch (type) {
      case 'household_collection':
        return CaptainTheme.success;
      case 'bulk_waste_collection':
        return CaptainTheme.warning;
      case 'bin_collection':
      default:
        return CaptainTheme.primary;
    }
  }
}

class _StatusPalette {
  const _StatusPalette({
    required this.color,
    required this.icon,
  });

  final Color color;
  final IconData icon;

  static _StatusPalette of(String status) {
    final normalized = status.trim().toLowerCase();
    switch (normalized) {
      case 'completed':
        return _StatusPalette(
          color: CaptainTheme.success,
          icon: Icons.check_circle_rounded,
        );
      case 'in progress':
        return const _StatusPalette(
          color: Color(0xFF0EA5E9),
          icon: Icons.directions_run_rounded,
        );
      case 'cancelled':
        return _StatusPalette(
          color: CaptainTheme.danger,
          icon: Icons.cancel_rounded,
        );
      default:
        return _StatusPalette(
          color:
              normalized.isEmpty ? CaptainTheme.mutedText : CaptainTheme.info,
          icon: normalized.isEmpty
              ? Icons.help_outline_rounded
              : Icons.info_outline_rounded,
        );
    }
  }
}

String _dateLabel(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}

String _formatTime(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final parts = raw.split(':');
  if (parts.length < 2) return raw;
  final hh = int.tryParse(parts[0]);
  final mm = int.tryParse(parts[1]);
  if (hh == null || mm == null) return raw;
  final amPm = hh >= 12 ? 'PM' : 'AM';
  final h12 = ((hh + 11) % 12) + 1;
  return '$h12:${mm.toString().padLeft(2, '0')} $amPm';
}
