import 'package:flutter/material.dart';

import 'package:iwms_private_app/core/ui/app_flash.dart';
import 'package:iwms_private_app/data/models/trip_retrip_models.dart';
import 'package:iwms_private_app/data/repositories/trip_retrip_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// Full-screen approve/reject decision flow for one Re-Trip request. Ported
/// from the government app's identically-purposed
/// `SupervisorRetripReviewScreen` (`module5_supervisor/presentation/screens/
/// supervisor_retrip_review_screen.dart`) — a bin trip lets the supervisor
/// tick which pending stops carry over to the continuation trip; a household
/// trip carries everything over wholesale (nothing to pick).
class SupervisorRetripReviewScreen extends StatefulWidget {
  const SupervisorRetripReviewScreen({super.key, required this.request});

  final TripRetripRequest request;

  /// Pushes the screen, returning `true` only when a decision (approve or
  /// reject) was actually recorded — callers use this to trigger a refresh.
  static Future<bool?> push(BuildContext context, TripRetripRequest request) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SupervisorRetripReviewScreen(request: request),
      ),
    );
  }

  @override
  State<SupervisorRetripReviewScreen> createState() =>
      _SupervisorRetripReviewScreenState();
}

class _SupervisorRetripReviewScreenState
    extends State<SupervisorRetripReviewScreen> {
  final TripRetripRepository _repo = TripRetripRepository();
  late final Set<String> _selected;
  final _remarksController = TextEditingController();
  bool _busy = false;

  TripRetripRequest get _request => widget.request;

  @override
  void initState() {
    super.initState();
    // Default to carrying over everything outstanding — the supervisor
    // un-ticks what should be dropped for the day instead of building the
    // list from nothing.
    _selected = _request.liveStops.map((s) => s.uniqueId).toSet();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _setAll(bool all) {
    setState(() {
      _selected
        ..clear()
        ..addAll(all ? _request.liveStops.map((s) => s.uniqueId) : const []);
    });
  }

  Future<void> _approve() async {
    if (_busy) return;
    final isHousehold = _request.isHousehold;

    if (!isHousehold && _selected.isEmpty) {
      final confirmed = await _confirmDropAll();
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      final newId = await _repo.approve(
        _request.uniqueId,
        collectionPointIds: isHousehold ? null : _selected.toList(),
        remarks: _remarksController.text,
      );
      if (!mounted) return;
      AppFlash.success(
        context,
        newId != null
            ? 'New trip $newId assigned to the driver'
            : 'Re-Trip approved',
      );
      Navigator.of(context).pop(true);
    } on TripRetripException catch (e) {
      if (mounted) AppFlash.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final remarks = await _askRejectReason();
    if (remarks == null) return;

    setState(() => _busy = true);
    try {
      await _repo.reject(_request.uniqueId, remarks: remarks);
      if (!mounted) return;
      AppFlash.success(context, 'Request declined — driver notified');
      Navigator.of(context).pop(true);
    } on TripRetripException catch (e) {
      if (mounted) AppFlash.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmDropAll() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Carry nothing over?'),
        content: const Text(
          'No collection points are selected, so the trip will be closed '
          'and the remaining stops dropped for today. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SupervisorTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Close trip'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askRejectReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Decline request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The trip stays In Progress and the driver is asked to '
              'continue the remaining stops.',
              style: TextStyle(
                  fontSize: 12.5, color: SupervisorTheme.mutedText),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              style: SupervisorTheme.inputTextStyle,
              decoration: SupervisorTheme.inputDecoration(
                'Message to the driver (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: SupervisorTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SupervisorTheme.background,
      appBar: AppBar(
        backgroundColor: SupervisorTheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Review Re-Trip request'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryCard(),
                  const SizedBox(height: 14),
                  _outcomeNotice(),
                  const SizedBox(height: 16),
                  _stopsHeader(),
                  const SizedBox(height: 6),
                  _stopsList(),
                  const SizedBox(height: 16),
                  _remarksField(),
                ],
              ),
            ),
          ),
          _actionBar(),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final r = _request;
    final rows = <MapEntry<String, String>>[
      MapEntry('Trip', r.assignmentUniqueId),
      MapEntry('Area', r.areaName.isEmpty ? '—' : r.areaName),
      if (r.vehicleNo.isNotEmpty) MapEntry('Vehicle', r.vehicleNo),
      if (r.requestedByName.isNotEmpty)
        MapEntry('Requested by', r.requestedByName),
      if (r.tripDate.isNotEmpty) MapEntry('Trip date', r.tripDate),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SupervisorTheme.hairline),
        boxShadow: SupervisorTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      row.key,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: SupervisorTheme.mutedText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: SupervisorTheme.strongText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (r.reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SupervisorTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: SupervisorTheme.warning.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Driver's reason",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: SupervisorTheme.warning,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.reason,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: SupervisorTheme.strongText,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _outcomeNotice() {
    final r = _request;
    final total = r.liveStops.length;
    final message = r.isHousehold
        ? 'All $total remaining household(s) will move to a new trip on the '
            'same trip plan. This trip will be closed with its actual end '
            'time.'
        : '${_selected.length} of $total collection point(s) will move to a '
            'new trip. Unticked stops are dropped for today, and this trip '
            'is closed.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SupervisorTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: SupervisorTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: SupervisorTheme.strongText,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopsHeader() {
    final r = _request;
    final total = r.liveStops.length;
    if (r.isHousehold) {
      return Text(
        'Remaining households ($total)',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: SupervisorTheme.strongText,
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            'Select collection points (${_selected.length}/$total)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: SupervisorTheme.strongText,
            ),
          ),
        ),
        if (total > 0)
          TextButton(
            onPressed: _busy
                ? null
                : () => _setAll(_selected.length != total),
            child: Text(_selected.length == total ? 'Clear all' : 'Select all'),
          ),
      ],
    );
  }

  Widget _stopsList() {
    final stops = _request.liveStops;
    if (stops.isEmpty) return _emptyStops();
    return Column(
      children: [for (final stop in stops) _stopRow(stop)],
    );
  }

  Widget _emptyStops() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.check_circle_rounded, size: 36, color: SupervisorTheme.success),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Nothing is outstanding any more — the crew resolved the '
              'remaining stops after raising this request. Approving will '
              'simply close the trip.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: SupervisorTheme.mutedText,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopRow(RetripPendingStop stop) {
    final isHousehold = _request.isHousehold;
    final statusLabel = stop.status.isNotEmpty ? stop.status : 'Pending';

    if (isHousehold) {
      // Households have no choice to make, so render them as a plain
      // read-only list rather than a disabled checkbox (which reads as
      // "blocked").
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.home_outlined, size: 16, color: SupervisorTheme.mutedText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                stop.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: SupervisorTheme.strongText,
                ),
              ),
            ),
            Text(
              statusLabel,
              style: const TextStyle(fontSize: 11.5, color: SupervisorTheme.mutedText),
            ),
          ],
        ),
      );
    }

    final selected = _selected.contains(stop.uniqueId);
    return InkWell(
      onTap: _busy ? null : () => _toggle(stop.uniqueId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              activeColor: SupervisorTheme.accent,
              onChanged: _busy ? null : (_) => _toggle(stop.uniqueId),
            ),
            Expanded(
              child: Text(
                stop.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: SupervisorTheme.strongText,
                ),
              ),
            ),
            Text(
              statusLabel,
              style: const TextStyle(fontSize: 11.5, color: SupervisorTheme.mutedText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _remarksField() {
    return TextField(
      controller: _remarksController,
      maxLines: 2,
      enabled: !_busy,
      style: SupervisorTheme.inputTextStyle,
      decoration: SupervisorTheme.inputDecoration(
        'Remarks (optional)',
        hintText: 'Note for the record…',
      ),
    );
  }

  Widget _actionBar() {
    final isHousehold = _request.isHousehold;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.viewPaddingOf(context).bottom),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        border: Border(top: BorderSide(color: SupervisorTheme.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : _reject,
              style: OutlinedButton.styleFrom(
                foregroundColor: SupervisorTheme.danger,
                side: BorderSide(color: SupervisorTheme.danger.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _busy ? null : _approve,
              style: ElevatedButton.styleFrom(
                backgroundColor: SupervisorTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isHousehold ? 'Assign new trip' : 'Re-Trip'),
            ),
          ),
        ],
      ),
    );
  }
}
