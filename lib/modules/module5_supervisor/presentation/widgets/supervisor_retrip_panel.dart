import 'package:flutter/material.dart';

import 'package:iwms_private_app/data/models/trip_retrip_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// Pinned above the Trips screen's filter chips — a driver is parked waiting
/// on this decision, so a pending Re-Trip request must be visible regardless
/// of which status filter is active, not buried behind a separate tile.
/// Ported from the government app's identically-purposed
/// `SupervisorRetripRequestsPanel` (`module5_supervisor/presentation/widgets/
/// supervisor_retrip_card.dart`).
class SupervisorRetripRequestsPanel extends StatelessWidget {
  const SupervisorRetripRequestsPanel({
    super.key,
    required this.requests,
    required this.onReview,
  });

  final List<TripRetripRequest> requests;
  final ValueChanged<TripRetripRequest> onReview;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 10, 18, 4),
      decoration: BoxDecoration(
        color: SupervisorTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SupervisorTheme.warning.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: SupervisorTheme.warning.withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          for (final r in requests) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            _RetripRow(request: r, onReview: () => onReview(r)),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    final count = requests.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Icon(Icons.hourglass_top_rounded,
              size: 18, color: SupervisorTheme.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 1
                  ? 'Re-Trip request needs your approval'
                  : '$count Re-Trip requests need your approval',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: SupervisorTheme.strongText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetripRow extends StatelessWidget {
  const _RetripRow({required this.request, required this.onReview});

  final TripRetripRequest request;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final pending = request.livePendingBins.isNotEmpty ||
            request.livePendingHouseholds.isNotEmpty
        ? request.livePendingBins.length + request.livePendingHouseholds.length
        : request.pendingTotal;

    return InkWell(
      onTap: onReview,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.areaName.isEmpty
                        ? request.assignmentUniqueId
                        : request.areaName,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: SupervisorTheme.strongText,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: SupervisorTheme.warning.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$pending left',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: SupervisorTheme.warning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                request.assignmentUniqueId,
                request.isHousehold ? 'Households' : 'Collection points',
                if (request.vehicleNo.isNotEmpty) request.vehicleNo,
              ].join(' · '),
              style: const TextStyle(
                fontSize: 11.5,
                color: SupervisorTheme.mutedText,
              ),
            ),
            if (request.reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SupervisorTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.format_quote_rounded,
                        size: 14, color: SupervisorTheme.mutedText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        request.reason,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: SupervisorTheme.strongText,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (request.requestedByName.isNotEmpty) ...[
                  Icon(Icons.person_outline_rounded,
                      size: 14, color: SupervisorTheme.mutedText),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      request.requestedByName,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: SupervisorTheme.mutedText,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                _ReviewButton(onTap: onReview),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: SupervisorTheme.warning,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Review',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
