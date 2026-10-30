import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:iwms_private_app/data/repositories/trip_delay_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_photo_viewer.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_state_views.dart';

/// One driver-reported delay: the evidence photo, what happened, and the
/// supervisor's response — Acknowledge (seen, trip carries on) and Resolve
/// (the delay is over). Opened from a trip card's alerts sheet.
///
/// Pops `true` when the report's status changed.
class SupervisorDelayReviewScreen extends StatefulWidget {
  const SupervisorDelayReviewScreen({
    super.key,
    required this.reportId,
    this.repository,
  });

  final String reportId;
  final TripDelayRepository? repository;

  static Future<bool?> push(BuildContext context, String reportId) =>
      Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => SupervisorDelayReviewScreen(reportId: reportId)));

  @override
  State<SupervisorDelayReviewScreen> createState() =>
      _SupervisorDelayReviewScreenState();
}

class _SupervisorDelayReviewScreenState
    extends State<SupervisorDelayReviewScreen> {
  late final TripDelayRepository _repo =
      widget.repository ?? TripDelayRepository();
  final _remarks = TextEditingController();
  TripDelayReport? _report;
  String? _error;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final report = await _repo.fetchReport(widget.reportId);
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _act(bool resolve) async {
    setState(() => _busy = true);
    try {
      final report = resolve
          ? await _repo.resolve(widget.reportId, remarks: _remarks.text)
          : await _repo.acknowledge(widget.reportId, remarks: _remarks.text);
      if (!mounted) return;
      _changed = true;
      _remarks.clear();
      setState(() => _report = report);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(resolve ? 'Delay resolved.' : 'Delay acknowledged.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: SupervisorTheme.background,
        appBar: AppBar(
          backgroundColor: SupervisorTheme.primary,
          foregroundColor: Colors.white,
          title: const Text('Driver delay'),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return SupervisorErrorView(message: _error!, onRetry: _load);
    }
    final r = _report;
    if (r == null) return const SupervisorLoadingView();
    final (statusColor, statusText) = r.isResolved
        ? (SupervisorTheme.success, 'Resolved')
        : r.isReported
            ? (SupervisorTheme.warning, 'Awaiting your response')
            : (SupervisorTheme.info, 'Acknowledged');
    final when = r.reportedAt == null
        ? ''
        : DateFormat('d MMM, HH:mm').format(r.reportedAt!);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (r.imageUrl != null)
          Semantics(
            button: true,
            label: 'View evidence photo',
            child: GestureDetector(
              onTap: () => showSupervisorPhoto(context, r.imageUrl!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.network(
                    r.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: SupervisorTheme.surfaceMuted,
                      child: const Icon(Icons.broken_image_outlined,
                          color: SupervisorTheme.mutedText),
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Text(r.reason,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(statusText,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            if (r.reportedBy.isNotEmpty) r.reportedBy,
            if (when.isNotEmpty) when,
          ].join(' · '),
          style:
              const TextStyle(fontSize: 13, color: SupervisorTheme.mutedText),
        ),
        const SizedBox(height: 16),
        if (r.remarks.isNotEmpty)
          _Fact(icon: Icons.chat_bubble_outline_rounded, text: r.remarks),
        if (r.estimatedMinutes != null)
          _Fact(
              icon: Icons.timer_outlined,
              text: 'About ${r.estimatedMinutes} min delay'),
        if (r.vehicleNo.isNotEmpty)
          _Fact(icon: Icons.local_shipping_outlined, text: r.vehicleNo),
        if (r.location.isNotEmpty)
          _Fact(icon: Icons.place_outlined, text: r.location),
        if (r.supervisorRemarks.isNotEmpty)
          _Fact(
              icon: Icons.reply_rounded,
              text: 'Your note: ${r.supervisorRemarks}'),
        if (!r.isResolved) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _remarks,
            maxLines: 2,
            maxLength: 500,
            style: SupervisorTheme.inputTextStyle,
            decoration: SupervisorTheme.inputDecoration(
                'Note for the driver (optional)'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (r.isReported) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _act(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Acknowledge'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : () => _act(true),
                style: FilledButton.styleFrom(
                  backgroundColor: SupervisorTheme.success,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Mark resolved'),
              ),
            ),
          ]),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: SupervisorTheme.mutedText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 14, color: SupervisorTheme.strongText)),
          ),
        ]),
      );
}
