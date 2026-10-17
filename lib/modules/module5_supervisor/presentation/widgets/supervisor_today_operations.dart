import 'package:flutter/material.dart';

import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_trip_map_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_assignment_card.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_assignment_detail_sheet.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_trip_actions_sheet.dart';

class SupervisorTodayOperations extends StatefulWidget {
  const SupervisorTodayOperations({
    super.key,
    required this.updatedAt,
    required this.onChanged,
    required this.assignments,
    this.onOpenTrips,
    this.repository,
  });

  final DateTime? updatedAt;
  final Future<void> Function() onChanged;
  final List<SupervisorAssignment> assignments;
  final VoidCallback? onOpenTrips;
  final SupervisorRepository? repository;

  @override
  State<SupervisorTodayOperations> createState() =>
      _SupervisorTodayOperationsState();
}

class _SupervisorTodayOperationsState extends State<SupervisorTodayOperations> {
  late final SupervisorRepository _repository;
  List<SupervisorPlanOption> _plans = const [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SupervisorRepository();
    _load();
  }

  @override
  void didUpdateWidget(covariant SupervisorTodayOperations oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.updatedAt != oldWidget.updatedAt) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final plans = await _repository.fetchTodayPlanOptions();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is SupervisorException
            ? error.message
            : 'Could not load today\'s Trip Plans.';
        _loading = false;
      });
    }
  }

  Future<void> _assignPlans() async {
    final eligible = _plans.where((plan) => plan.needsAssignment).toList();
    if (eligible.isEmpty) return;
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SupervisorTheme.surface,
      showDragHandle: true,
      builder: (_) => _AssignPlansSheet(plans: eligible),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _submit(
      () => _repository.assignSelectedPlans(selected),
      'Today\'s trips are ready for the assigned teams.',
    );
  }

  Future<void> _declareNoCollection(SupervisorPlanOption plan) async {
    final decision = await showModalBottomSheet<_NoCollectionDecision>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SupervisorTheme.surface,
      showDragHandle: true,
      builder: (_) => _NoCollectionSheet(plan: plan),
    );
    if (decision == null || !mounted) return;
    await _submit(
      () => _repository.declareNoCollection(
        tripPlanIds: [plan.tripPlanId],
        reasonCode: decision.reasonCode,
        reasonText: decision.note,
      ),
      'Staff and affected customers have been informed.',
    );
  }

  Future<void> _restoreService(SupervisorPlanOption plan) async {
    final noticeId = plan.notice?.uniqueId;
    if (noticeId == null || noticeId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore today\'s collection?'),
        content: Text(
            '${plan.areaName} will return to Scheduled. Staff and affected customers will receive a correction.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep suspended')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore service')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _submit(
      () => _repository.revokeNoCollection(noticeId,
          reason: 'Restored by supervisor'),
      'Collection was restored and affected users were informed.',
    );
  }

  Future<void> _submit(Future<void> Function() action, String success) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await action();
      await _load(silent: true);
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      if (!mounted) return;
      final message = error is SupervisorException
          ? error.message
          : 'The operation could not be completed.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 148,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return _InlineMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Today\'s operations unavailable',
        message: _error!,
        action: () => _load(),
      );
    }
    if (_plans.isEmpty) {
      return const _InlineMessage(
        icon: Icons.event_busy_outlined,
        title: 'No Trip Plans under your supervision',
        message: 'Approved Trip Plans assigned to you will appear here.',
      );
    }

    final needs = _plans.where((plan) => plan.needsAssignment).length;
    final now = DateTime.now();
    final rows = [
      for (final plan in _plans) (plan: plan, assignment: _assignmentFor(plan)),
    ];
    // Finished and suspended routes sink to the bottom; everything that may
    // still need the supervisor stays on top in the server's order.
    int rank(
            ({
              SupervisorPlanOption plan,
              SupervisorAssignment? assignment
            }) r) =>
        r.plan.noCollection
            ? 2
            : r.assignment?.isCompleted == true
                ? 1
                : 0;
    final ordered = [...rows]..sort((a, b) => rank(a).compareTo(rank(b)));
    final attention = rows.where((r) {
      if (r.plan.noCollection) return false;
      final a = r.assignment;
      if (a == null) return r.plan.needsAssignment || r.plan.state == 'BLOCKED';
      return a
          .alerts(now)
          .any((alert) => alert.severity != TripAlertSeverity.info);
    }).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_plans.length > 1) ...[
          SupervisorRoutesSummary(
              routes: _plans.length, needsAttention: attention),
          const SizedBox(height: 10),
        ],
        if (needs > 1) ...[
          FilledButton.icon(
            onPressed: _submitting ? null : _assignPlans,
            icon: const Icon(Icons.playlist_add_check_rounded, size: 19),
            label: Text('Assign today\'s trips ($needs)'),
            style: FilledButton.styleFrom(
              backgroundColor: SupervisorTheme.accent,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (final (i, r) in ordered.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          _card(r.plan, r.assignment, now),
        ],
      ],
    );
  }

  /// Today's live trip for [plan]. A plan can hold several trips in a day (a
  /// cancelled run, a Re-Trip continuation), so prefer the one in progress,
  /// then scheduled, then completed — newest first — over whichever single
  /// id the plan list happened to report.
  SupervisorAssignment? _assignmentFor(SupervisorPlanOption plan) {
    if (plan.noCollection) return null;
    final now = DateTime.now();
    bool today(SupervisorAssignment a) =>
        a.tripDate != null &&
        a.tripDate!.year == now.year &&
        a.tripDate!.month == now.month &&
        a.tripDate!.day == now.day;
    int rank(SupervisorAssignment a) => a.isInProgress
        ? 0
        : a.isScheduled
            ? 1
            : a.isCompleted
                ? 2
                : 3;
    final candidates = widget.assignments
        .where((a) =>
            plan.tripPlanId.isNotEmpty &&
            a.tripPlanId == plan.tripPlanId &&
            today(a) &&
            !a.isCancelled)
        .toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : b.tripCount.compareTo(a.tripCount);
      });
    if (candidates.isNotEmpty) return candidates.first;
    for (final a in widget.assignments) {
      if (a.uniqueId == plan.assignmentId) return a;
    }
    return null;
  }

  Widget _card(SupervisorPlanOption plan, SupervisorAssignment? assignment,
      DateTime now) {
    if (assignment == null) {
      return SupervisorPlanCard(
        plan: plan,
        enabled: !_submitting,
        onAssign: () => _assignSinglePlan(plan),
        onNoCollection: () => _declareNoCollection(plan),
        onRestoreService: () => _restoreService(plan),
      );
    }
    final a = assignment;
    return SupervisorAssignmentCard(
      assignment: a,
      serverNow: now,
      onTap: () => SupervisorAssignmentDetailSheet.show(context, a),
      onNavigate: a.isInProgress
          ? () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SupervisorTripMapScreen(
                  assignmentId: a.uniqueId,
                  title: a.areaName,
                  driverName: a.driverName,
                  vehicleNo: a.vehicleNo,
                  tripDate: a.tripDate)))
          : null,
      onActions: () async {
        final changed = await SupervisorTripActionsSheet.show(context,
            assignmentId: a.uniqueId, assignment: a);
        if (changed == true && mounted) await widget.onChanged();
      },
      onAlertHandled: () => widget.onChanged(),
      onNoCollection: plan.canDeclareNoCollection && !_submitting
          ? () => _declareNoCollection(plan)
          : null,
    );
  }

  Future<void> _assignSinglePlan(SupervisorPlanOption plan) => _submit(
        () => _repository.assignSelectedPlans([plan.tripPlanId]),
        'Today\'s trip is ready for the assigned team.',
      );
}

class _AssignPlansSheet extends StatefulWidget {
  const _AssignPlansSheet({required this.plans});
  final List<SupervisorPlanOption> plans;

  @override
  State<_AssignPlansSheet> createState() => _AssignPlansSheetState();
}

class _AssignPlansSheetState extends State<_AssignPlansSheet> {
  late final Set<String> _selected =
      widget.plans.map((plan) => plan.tripPlanId).toSet();

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Assign today\'s trips',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Only approved routes scheduled for today are shown.',
                  style: TextStyle(color: SupervisorTheme.mutedText)),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .45),
                child: ListView(
                  shrinkWrap: true,
                  children: widget.plans
                      .map((plan) => CheckboxListTile(
                            value: _selected.contains(plan.tripPlanId),
                            onChanged: (value) => setState(() => value == true
                                ? _selected.add(plan.tripPlanId)
                                : _selected.remove(plan.tripPlanId)),
                            title: Text(plan.areaName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(
                                '${plan.collectionLabel} · ${plan.scheduledTime} · ${plan.vehicleNo}'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: SupervisorTheme.accent,
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, _selected.toList()),
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: Text(
                    'Assign ${_selected.length} ${_selected.length == 1 ? 'trip' : 'trips'}'),
                style: FilledButton.styleFrom(
                    backgroundColor: SupervisorTheme.accent,
                    minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
      );
}

class _NoCollectionDecision {
  const _NoCollectionDecision(this.reasonCode, this.note);
  final String reasonCode;
  final String note;
}

class _NoCollectionSheet extends StatefulWidget {
  const _NoCollectionSheet({required this.plan});
  final SupervisorPlanOption plan;

  @override
  State<_NoCollectionSheet> createState() => _NoCollectionSheetState();
}

class _NoCollectionSheetState extends State<_NoCollectionSheet> {
  static const _reasons = <String, String>{
    'WEATHER': 'Severe weather',
    'FLOOD': 'Flooding',
    'HOLIDAY': 'Public holiday',
    'STAFF_UNAVAILABLE': 'Staff unavailable',
    'VEHICLE_TECHNICAL': 'Vehicle or technical issue',
    'SAFETY': 'Safety issue',
    'OTHER': 'Other',
  };
  String? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [
                Icon(Icons.event_busy_outlined, color: SupervisorTheme.danger),
                SizedBox(width: 9),
                Text('No collection today',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Text('${widget.plan.areaName} · ${widget.plan.collectionLabel}',
                  style: const TextStyle(color: SupervisorTheme.mutedText)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _reason,
                items: _reasons.entries
                    .map((item) => DropdownMenuItem(
                        value: item.key, child: Text(item.value)))
                    .toList(),
                onChanged: (value) => setState(() => _reason = value),
                decoration: SupervisorTheme.inputDecoration('Reason'),
                style: SupervisorTheme.inputTextStyle,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                onChanged: (_) => setState(() {}),
                maxLength: 500,
                maxLines: 3,
                style: SupervisorTheme.inputTextStyle,
                decoration: SupervisorTheme.inputDecoration(_reason == 'OTHER'
                    ? 'Explanation'
                    : 'Additional note (optional)'),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SupervisorTheme.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notifications_active_outlined,
                          size: 19, color: SupervisorTheme.accentDeep),
                      SizedBox(width: 9),
                      Expanded(
                          child: Text(
                        'The assigned team and affected customers will be notified. This route cannot be started today unless the notice is revoked.',
                        style: TextStyle(fontSize: 12.5, height: 1.35),
                      )),
                    ]),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _reason == null ||
                        (_reason == 'OTHER' && _note.text.trim().isEmpty)
                    ? null
                    : () => Navigator.pop(context,
                        _NoCollectionDecision(_reason!, _note.text.trim())),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Confirm and notify'),
                style: FilledButton.styleFrom(
                    backgroundColor: SupervisorTheme.danger,
                    minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
      );
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function()? action;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: SupervisorTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: SupervisorTheme.hairline.withValues(alpha: .5))),
        child: Row(children: [
          Icon(icon, color: SupervisorTheme.mutedText),
          const SizedBox(width: 11),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(message,
                  style: const TextStyle(
                      fontSize: 12.5, color: SupervisorTheme.mutedText)),
            ],
          )),
          if (action != null)
            IconButton(
              tooltip: 'Retry',
              onPressed: () => action!(),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ]),
      );
}
