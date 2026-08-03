import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// One trip's servicing of a point/household: the stop plus which trip it
/// belongs to.
class SupervisorPointVisit {
  const SupervisorPointVisit({required this.stop, required this.tripCode});

  final SupervisorStop stop;
  final String tripCode;
}

/// A clean bottom sheet showing the collection status of a single collection
/// point or household across today's trip(s). Replaces the older
/// _ActionDialog + _WasteDialog center-popups: one drawer, correct copy
/// (pluralization, "Pending" vs "0.00 kg"), labelled trip codes, real status
/// tone/icon (not a checkbox-looking hollow circle), an honest empty state for
/// unassigned points, and an optional "View on map" that is simply absent
/// (never a dead greyed button) when there is nothing to map.
class SupervisorPointStatusSheet extends StatelessWidget {
  const SupervisorPointStatusSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.visits,
    this.onViewMap,
  });

  final String title;
  final String subtitle;
  final List<SupervisorPointVisit> visits;

  /// Provided only when a mappable trip exists for this point. When null, the
  /// map button is not rendered at all.
  final VoidCallback? onViewMap;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<SupervisorPointVisit> visits,
    VoidCallback? onViewMap,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupervisorPointStatusSheet(
        title: title,
        subtitle: subtitle,
        visits: visits,
        onViewMap: onViewMap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final collectedTotal = visits
        .where((v) => v.stop.isCollected)
        .fold<double>(0, (sum, v) => sum + (v.stop.collectedWeightKg ?? 0));
    final servicedCount = visits.where((v) => v.stop.isCollected).length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: SupervisorTheme.mutedText,
                  ),
                ),
                if (visits.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _summaryLine(servicedCount, visits.length, collectedTotal),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: SupervisorTheme.strongText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: visits.isEmpty
                ? _emptyState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shrinkWrap: true,
                    itemCount: visits.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _VisitRow(visit: visits[i]),
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              16 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: onViewMap == null
                ? const SizedBox.shrink()
                : SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onViewMap,
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('View on map'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SupervisorTheme.accent,
                        side: BorderSide(
                          color: SupervisorTheme.accent.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: SupervisorTheme.chipRadius,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _summaryLine(int serviced, int total, double kg) {
    final trips = total == 1 ? '1 trip' : '$total trips';
    if (serviced == 0) {
      return 'On $trips today · not yet collected';
    }
    return 'Collected on $serviced of $trips · ${kg.toStringAsFixed(2)} kg';
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          const Icon(Icons.event_busy_outlined,
              size: 18, color: SupervisorTheme.mutedText),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Not assigned to any trip today.',
              style: TextStyle(
                fontSize: 13,
                color: SupervisorTheme.mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.visit});

  final SupervisorPointVisit visit;

  @override
  Widget build(BuildContext context) {
    final stop = visit.stop;
    final tone = _StopTone.of(stop);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(tone.icon, color: tone.color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tone.label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: tone.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      stop.isCollected
                          ? '${(stop.collectedWeightKg ?? 0).toStringAsFixed(2)} kg'
                          : '—',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: stop.isCollected
                            ? SupervisorTheme.strongText
                            : SupervisorTheme.mutedText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Trip: ${visit.tripCode}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: SupervisorTheme.mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (stop.isCollected && stop.collectedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Collected at ${_formatTime(stop.collectedAt!)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: SupervisorTheme.mutedText,
                    ),
                  ),
                ],
                if ((stop.statusReason ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '"${stop.statusReason!.trim()}"',
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: SupervisorTheme.mutedText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _StopTone {
  const _StopTone(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;

  static _StopTone of(SupervisorStop stop) {
    if (stop.isCollected) {
      return const _StopTone(
        'Collected',
        SupervisorTheme.success,
        Icons.check_circle_rounded,
      );
    }
    final s = stop.status.trim().toLowerCase();
    if (s == 'collect later') {
      return const _StopTone(
        'Collect Later',
        SupervisorTheme.warning,
        Icons.schedule_rounded,
      );
    }
    if (s == 'not available' ||
        s == 'skipped' ||
        s == 'missed' ||
        s == 'not collected') {
      return const _StopTone(
        'Not Available',
        SupervisorTheme.danger,
        Icons.cancel_rounded,
      );
    }
    return const _StopTone(
      'Pending',
      SupervisorTheme.info,
      Icons.pending_outlined,
    );
  }
}
