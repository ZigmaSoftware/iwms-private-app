import 'package:flutter/material.dart';

import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_trip_map_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

enum _StopTone { collected, current, deferred, pending }

/// Bottom sheet showing the full detail of a single assignment: a compact
/// identity/progress header, then an Amazon-delivery-style vertical stop
/// timeline (bin collection points + households, merged in route order).
class SupervisorAssignmentDetailSheet extends StatelessWidget {
  const SupervisorAssignmentDetailSheet({super.key, required this.assignment});

  final SupervisorAssignment assignment;

  static Future<void> show(
    BuildContext context,
    SupervisorAssignment assignment,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupervisorAssignmentDetailSheet(assignment: assignment),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stops = assignment.stops;
    final collectedCount = stops.where((s) => s.isCollected).length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
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
            child: _header(context, stops, collectedCount),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _crewRow(),
                  const SizedBox(height: 16),
                  if (assignment.remarks.isNotEmpty) ...[
                    _row(Icons.notes_rounded, 'Remarks', assignment.remarks),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Route',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: SupervisorTheme.strongText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (stops.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'No stops recorded for this trip yet.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: SupervisorTheme.mutedText,
                        ),
                      ),
                    )
                  else
                    _StopTimeline(stops: stops),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          SizedBox(height: 16 + MediaQuery.viewPaddingOf(context).bottom),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, List<SupervisorStop> stops, int collectedCount) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assignment.areaName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: SupervisorTheme.strongText,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                assignment.tripCode,
                style: const TextStyle(
                  fontSize: 12,
                  color: SupervisorTheme.mutedText,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _badge(assignment.statusLabel, SupervisorTheme.info),
                  if (assignment.wasteTypeName.isNotEmpty)
                    _badge(assignment.wasteTypeName, SupervisorTheme.mutedText),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          tooltip: 'View on map',
          onPressed: () {
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
          icon: const Icon(
            Icons.map_outlined,
            color: SupervisorTheme.accent,
          ),
        ),
        if (stops.isNotEmpty) _progressRing(collectedCount, stops.length),
      ],
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _progressRing(int done, int total) {
    final ratio = total == 0 ? 0.0 : done / total;
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              value: ratio,
              strokeWidth: 5,
              backgroundColor: SupervisorTheme.hairline.withValues(alpha: 0.35),
              valueColor: AlwaysStoppedAnimation<Color>(
                ratio >= 1.0 ? SupervisorTheme.success : SupervisorTheme.accent,
              ),
            ),
          ),
          Text(
            '$done/$total',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: SupervisorTheme.strongText,
            ),
          ),
        ],
      ),
    );
  }

  /// Condensed identity row — driver, operator, vehicle — replacing three
  /// separate spec rows with one compact line of chips.
  Widget _crewRow() {
    final chips = <Widget>[
      if (assignment.driverName.isNotEmpty)
        _crewChip(Icons.drive_eta_rounded, assignment.driverName),
      if (assignment.operatorName.isNotEmpty)
        _crewChip(Icons.engineering_rounded, assignment.operatorName),
      if (assignment.vehicleNo.isNotEmpty)
        _crewChip(Icons.local_shipping_outlined, assignment.vehicleNo),
      if (assignment.scheduledTime.isNotEmpty)
        _crewChip(Icons.schedule_rounded, assignment.scheduledTime),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 14, runSpacing: 8, children: chips);
  }

  Widget _crewChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: SupervisorTheme.mutedText),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: SupervisorTheme.strongText,
          ),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: SupervisorTheme.mutedText),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: SupervisorTheme.mutedText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: SupervisorTheme.strongText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical Amazon-delivery-style stop timeline: one tile per stop, in route
/// order, with a connecting line and a status dot coloured by tone.
class _StopTimeline extends StatelessWidget {
  const _StopTimeline({required this.stops});

  final List<SupervisorStop> stops;

  @override
  Widget build(BuildContext context) {
    // The "current" stop is the first not-yet-collected stop that also isn't
    // deferred (skipped / not-available / collect-later); if every remaining
    // stop is deferred, fall back to the first not-yet-collected one so there
    // is still a "next" highlight.
    var currentIndex =
        stops.indexWhere((s) => !s.isCollected && !s.isSkippedOrDeferred);
    if (currentIndex == -1) {
      currentIndex = stops.indexWhere((s) => !s.isCollected);
    }

    return Column(
      children: [
        for (var i = 0; i < stops.length; i++)
          _StopTile(
            stop: stops[i],
            tone: _toneFor(stops[i], i, currentIndex),
            isLast: i == stops.length - 1,
          ),
      ],
    );
  }

  _StopTone _toneFor(SupervisorStop stop, int index, int currentIndex) {
    if (stop.isCollected) return _StopTone.collected;
    if (stop.isSkippedOrDeferred) return _StopTone.deferred;
    if (index == currentIndex) return _StopTone.current;
    return _StopTone.pending;
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.stop,
    required this.tone,
    required this.isLast,
  });

  final SupervisorStop stop;
  final _StopTone tone;
  final bool isLast;

  Color get _toneColor {
    switch (tone) {
      case _StopTone.collected:
        return SupervisorTheme.success;
      case _StopTone.current:
        return SupervisorTheme.info;
      case _StopTone.deferred:
        return stop.status.trim().toLowerCase() == 'not available'
            ? SupervisorTheme.danger
            : SupervisorTheme.warning;
      case _StopTone.pending:
        return SupervisorTheme.hairline;
    }
  }

  /// Photos are only meaningful once a stop has been attempted (collected or
  /// deferred) — a pending stop hasn't been reached yet, so no photo slot is
  /// shown for it at all.
  bool get _showsPhotoSlot =>
      tone == _StopTone.collected || tone == _StopTone.deferred;

  @override
  Widget build(BuildContext context) {
    final color = _toneColor;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              _dot(color),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: tone == _StopTone.pending
                        ? SupervisorTheme.hairline.withValues(alpha: 0.4)
                        : color.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        stop.isHousehold
                            ? Icons.home_work_outlined
                            : Icons.delete_outline_rounded,
                        size: 13,
                        color: SupervisorTheme.mutedText,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Stop ${stop.sequence}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: SupervisorTheme.mutedText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stop.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: SupervisorTheme.strongText,
                    ),
                  ),
                  if (stop.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      stop.subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SupervisorTheme.mutedText,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  _statusLine(),
                  if (_showsPhotoSlot) ...[
                    const SizedBox(height: 8),
                    _photoSlot(context),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) {
    switch (tone) {
      case _StopTone.collected:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
        );
      case _StopTone.current:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: SupervisorTheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
          ),
        );
      case _StopTone.deferred:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const Icon(Icons.priority_high_rounded,
              size: 14, color: Colors.white),
        );
      case _StopTone.pending:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: SupervisorTheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
        );
    }
  }

  Widget _statusLine() {
    String text;
    if (stop.isCollected) {
      final parts = <String>['Collected'];
      if (stop.collectedWeightKg != null) {
        parts.add('${stop.collectedWeightKg!.toStringAsFixed(1)} kg');
      }
      if (stop.collectedAt != null) {
        parts.add(_formatTime(stop.collectedAt!));
      }
      text = parts.join(' • ');
    } else if (stop.isSkippedOrDeferred) {
      text = stop.status;
      if (stop.statusReason != null && stop.statusReason!.trim().isNotEmpty) {
        text += ' • "${stop.statusReason}"';
      }
    } else {
      text = tone == _StopTone.current ? 'Next up' : 'Pending';
    }
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _toneColor,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Proof-photo thumbnail if one was captured, otherwise a calm, explicit
  /// "not available" placeholder — never a broken-image icon or error.
  Widget _photoSlot(BuildContext context) {
    final url = stop.imageUrl;
    if (url == null || url.trim().isEmpty) {
      return Row(
        children: [
          const Icon(Icons.image_not_supported_outlined,
              size: 14, color: SupervisorTheme.mutedText),
          const SizedBox(width: 6),
          Text(
            stop.isHousehold
                ? 'No photo for this stop'
                : 'Captured image not available',
            style: const TextStyle(
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: SupervisorTheme.mutedText,
            ),
          ),
        ],
      );
    }
    return GestureDetector(
      onTap: () => _showFullImage(context, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 64,
            height: 64,
            color: SupervisorTheme.surfaceMuted,
            child: const Icon(Icons.broken_image_outlined,
                size: 20, color: SupervisorTheme.mutedText),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 64,
              height: 64,
              color: SupervisorTheme.surfaceMuted,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    size: 48,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
