import 'package:flutter/material.dart';

import 'package:iwms_private_app/data/models/trip_retrip_models.dart';
import 'package:iwms_private_app/data/repositories/trip_retrip_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_retrip_review_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_state_views.dart';

/// Re-Trip requests awaiting (or already given) this supervisor's decision —
/// raised when a driver ends a trip early with stops still pending (see
/// `trip_lifecycle_control.dart` on the driver side and
/// `app/services/retrip_service.py` on the backend). Reachable from the
/// Dashboard's "Re-Trips" quick-action tile; tapping a card pushes
/// [SupervisorRetripReviewScreen], the same decision flow the Trips screen's
/// pinned panel opens.
///
/// Deliberately separate from [SupervisorBreakdownsScreen] — a Re-Trip
/// request and a vehicle breakdown report are different features that just
/// happen to share the same approve/reject shape.
class SupervisorRetripRequestsScreen extends StatefulWidget {
  const SupervisorRetripRequestsScreen({super.key});

  @override
  State<SupervisorRetripRequestsScreen> createState() =>
      _SupervisorRetripRequestsScreenState();
}

class _SupervisorRetripRequestsScreenState
    extends State<SupervisorRetripRequestsScreen> {
  final TripRetripRepository _repo = TripRetripRepository();

  bool _loading = true;
  String? _error;
  List<TripRetripRequest> _requests = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await _repo.fetchRequests(status: '');
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openReview(TripRetripRequest r) async {
    final result = await SupervisorRetripReviewScreen.push(context, r);
    if (result == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SupervisorTheme.background,
      appBar: AppBar(
        backgroundColor: SupervisorTheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Re-Trip requests'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const SupervisorLoadingView();
    if (_error != null) {
      return SupervisorErrorView(message: _error!, onRetry: _load);
    }
    if (_requests.isEmpty) {
      return SupervisorEmptyView(
        message: 'No Re-Trip requests.',
        icon: Icons.published_with_changes_rounded,
        onRefresh: _load,
      );
    }
    return RefreshIndicator(
      color: SupervisorTheme.accent,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        itemCount: _requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _RetripCard(
          request: _requests[i],
          onTap: () => _openReview(_requests[i]),
        ),
      ),
    );
  }
}

class _RetripCard extends StatelessWidget {
  const _RetripCard({required this.request, required this.onTap});

  final TripRetripRequest request;
  final VoidCallback onTap;

  Color get _statusColor {
    switch (request.status.toUpperCase()) {
      case 'APPROVED':
        return SupervisorTheme.success;
      case 'REJECTED':
        return SupervisorTheme.danger;
      default:
        return SupervisorTheme.warning;
    }
  }

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
            color: SupervisorTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SupervisorTheme.hairline),
            boxShadow: SupervisorTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.published_with_changes_rounded,
                      color: SupervisorTheme.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      request.vehicleNo.isEmpty
                          ? request.assignmentUniqueId
                          : request.vehicleNo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: SupervisorTheme.strongText,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: _statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      request.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Reason: ${request.reason}',
                style: const TextStyle(
                    fontSize: 12.5, color: SupervisorTheme.mutedText),
              ),
              const SizedBox(height: 4),
              Text(
                '${request.areaName} — ${request.pendingTotal} stop(s) left',
                style: const TextStyle(
                    fontSize: 12.5, color: SupervisorTheme.mutedText),
              ),
              if (request.requestedByName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Requested by: ${request.requestedByName}',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: SupervisorTheme.strongText),
                ),
              ],
              if (!request.isPending && request.reviewRemarks.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Remarks: ${request.reviewRemarks}',
                  style: const TextStyle(
                      fontSize: 12, color: SupervisorTheme.danger),
                ),
              ],
              if (request.isPending) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.arrow_forward_rounded,
                        size: 14, color: SupervisorTheme.accent),
                    const SizedBox(width: 4),
                    Text(
                      'Tap to review',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SupervisorTheme.accent,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
