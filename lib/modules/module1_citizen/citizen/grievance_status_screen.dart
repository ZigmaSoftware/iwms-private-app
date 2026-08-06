import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/modules/module1_citizen/citizen/theme/citizen_pattern_background.dart';
import 'package:iwms_private_app/modules/module1_citizen/citizen/theme/citizen_theme.dart';
import 'package:iwms_private_app/data/models/grievance_ticket_model.dart';
import 'package:iwms_private_app/data/repositories/citizen_grievance_repository.dart';
import 'package:iwms_private_app/modules/module1_citizen/citizen/dashboard/notifications/controllers/notification_controller.dart';
import 'package:iwms_private_app/modules/module1_citizen/citizen/dashboard/notifications/models/citizen_alert.dart';

/// Lists the grievances the citizen has raised and shows the live status +
/// progress timeline for each.
class GrievanceStatusScreen extends StatefulWidget {
  final String? initialTicketId;
  const GrievanceStatusScreen({super.key, this.initialTicketId});

  @override
  State<GrievanceStatusScreen> createState() => _GrievanceStatusScreenState();
}

Color _statusColor(String? code) {
  switch (code) {
    case 'SUBMITTED':
    case 'DRAFT':
      return const Color(0xFF0288D1);
    case 'ASSIGNED':
      return const Color(0xFF3949AB);
    case 'IN_PROGRESS':
      return const Color(0xFFB7791F);
    case 'ESCALATED':
      return const Color(0xFFD32F2F);
    case 'RESOLVED':
      return const Color(0xFF2E7D32);
    case 'CLOSED':
      return const Color(0xFF616161);
    case 'REOPENED':
      return const Color(0xFFE65100);
    default:
      return const Color(0xFF757575);
  }
}

String _fmt(DateTime? d) =>
    d == null ? '—' : DateFormat('dd MMM, hh:mm a').format(d.toLocal());

class _GrievanceStatusScreenState extends State<GrievanceStatusScreen> {
  final _repo = CitizenGrievanceRepository();
  List<GrievanceTicket> _tickets = [];
  bool _loading = true;
  String? _error;
  Timer? _poll;
  final Map<String, String> _lastStatus = {};

  @override
  void initState() {
    super.initState();
    _load();
    // Live updates while the screen is open: poll and notify on status change.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _pollUpdates());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _pollUpdates() async {
    try {
      final list = await _repo.fetchMyTickets();
      if (!mounted) return;
      for (final t in list) {
        final prev = _lastStatus[t.uniqueId];
        if (prev != null && prev != t.statusCode) {
          // Reuse the citizen notification centre: adds to the bell list AND
          // fires a local notification.
          getIt<NotificationController>().addAlert(
            CitizenAlert(
              title: 'Update on ${t.ticketNo}',
              message: 'Status changed to ${t.statusName ?? t.statusCode}.',
              timestamp: DateTime.now(),
            ),
          );
        }
        _lastStatus[t.uniqueId] = t.statusCode ?? '';
      }
      setState(() => _tickets = list);
    } catch (_) {/* ignore poll errors */}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.fetchMyTickets();
      if (!mounted) return;
      for (final t in list) {
        _lastStatus[t.uniqueId] = t.statusCode ?? '';
      }
      setState(() {
        _tickets = list;
        _loading = false;
      });
      final id = widget.initialTicketId;
      if (id != null && id.isNotEmpty) {
        final match = list.where((t) => t.uniqueId == id).toList();
        if (match.isNotEmpty) _openDetail(match.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your tickets. Pull to refresh.';
        _loading = false;
      });
    }
  }

  Future<void> _openDetail(GrievanceTicket summary) async {
    GrievanceTicket ticket = summary;
    try {
      ticket = await _repo.fetchTicket(summary.uniqueId);
    } catch (_) {/* fall back to summary */}
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DetailSheet(ticket: ticket),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: CitizenColors.primary,
        foregroundColor: Colors.white,
        title: const Text('My Grievances'),
      ),
      body: CitizenPatternBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _tickets.isEmpty
                  ? _empty()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _tickets.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _card(_tickets[i]),
                    ),
        ),
      ),
    );
  }

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _error ?? 'You haven\'t raised any grievances yet.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  Widget _card(GrievanceTicket t) {
    final sc = _statusColor(t.statusCode);
    return InkWell(
      onTap: () => _openDetail(t),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: sc, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.ticketNo,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sc.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    t.statusName ?? t.statusCode ?? '-',
                    style: TextStyle(
                        color: sc, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
            if ((t.title ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(t.title!, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            _row(Icons.folder_outlined,
                '${t.categoryName ?? '-'}${t.subcategoryName != null ? ' › ${t.subcategoryName}' : ''}'),
            _row(Icons.groups_outlined,
                '${t.assignedTeamName ?? 'Grievance Desk'}${t.assignedStaffName != null ? ' · ${t.assignedStaffName}' : ''}'),
            _row(Icons.schedule, _fmt(t.createdAt)),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }
}

class _DetailSheet extends StatefulWidget {
  final GrievanceTicket ticket;
  const _DetailSheet({required this.ticket});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  final _repo = CitizenGrievanceRepository();
  final _feedbackController = TextEditingController();
  int _rating = 0;
  bool _issueSolved = true;
  bool _submitting = false;
  bool _submitted = false;

  GrievanceTicket get ticket => widget.ticket;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick a star rating first.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await _repo.submitFeedback(
        uniqueId: ticket.uniqueId,
        rating: _rating,
        feedbackText: _feedbackController.text.trim(),
        isIssueSolved: _issueSolved,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your feedback!')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit feedback. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = _statusColor(ticket.statusCode);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(ticket.ticketNo,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: sc.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(ticket.statusName ?? ticket.statusCode ?? '-',
                    style: TextStyle(color: sc, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _kv('Category',
              '${ticket.categoryName ?? '-'}${ticket.subcategoryName != null ? ' › ${ticket.subcategoryName}' : ''}'),
          _kv('Priority', ticket.priorityCode ?? '-'),
          _kv('Assigned team', ticket.assignedTeamName ?? 'Grievance Desk'),
          if (ticket.assignedStaffName != null)
            _kv('Responsible', ticket.assignedStaffName!),
          if ((ticket.locationText ?? '').isNotEmpty)
            _kv('Location', ticket.locationText!),
          _kv('Raised on', _fmt(ticket.createdAt)),
          if ((ticket.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Description',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text(ticket.description!),
          ],
          const SizedBox(height: 20),
          Text('Progress timeline',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          if (ticket.timeline.isEmpty)
            Text('No updates yet.', style: TextStyle(color: Colors.grey.shade500))
          else
            ...ticket.timeline.map((e) => _timelineTile(e)),
          if (ticket.isFinal) ...[
            const SizedBox(height: 20),
            _feedbackSection(),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _feedbackSection() {
    if (_submitted) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700),
            const SizedBox(width: 10),
            const Expanded(child: Text('Thanks — your feedback was recorded.')),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rate this resolution',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: Colors.amber.shade700,
                    size: 32,
                  ),
                  onPressed: () => setState(() => _rating = i),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _issueSolved,
            onChanged: (v) => setState(() => _issueSolved = v),
            title: const Text('Was the issue actually resolved?',
                style: TextStyle(fontSize: 13.5)),
          ),
          TextField(
            controller: _feedbackController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Anything else you\'d like to add? (optional)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submitFeedback,
              style: FilledButton.styleFrom(backgroundColor: CitizenColors.primary),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit feedback'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
        ],
      ),
    );
  }

  Widget _timelineTile(GrievanceTimelineEvent e) {
    final sc = _statusColor(e.statusCode);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: sc, shape: BoxShape.circle),
              ),
              Expanded(child: Container(width: 2, color: Colors.grey.shade200)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.statusName.isNotEmpty ? e.statusName : e.statusCode,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: sc)),
                  Text(_fmt(e.at),
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey.shade500)),
                  if ((e.remarks ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(e.remarks!,
                          style: TextStyle(
                              fontSize: 12.5, color: Colors.grey.shade700)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
