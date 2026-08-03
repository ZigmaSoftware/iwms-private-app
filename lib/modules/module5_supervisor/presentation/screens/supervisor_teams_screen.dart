import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:iwms_citizen_app/core/di.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/logic/supervisor_bloc.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_add_team_form.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_alt_staff_template_form.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_assignment_picker_dialog.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_no_staff_dialog.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_state_views.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_visuals.dart';
import 'package:iwms_citizen_app/shared/widgets/crew_avatar_stack.dart';

/// Teams — the staff template list (driver + operator + extra operators).
class SupervisorTeamsScreen extends StatefulWidget {
  const SupervisorTeamsScreen({super.key});

  @override
  State<SupervisorTeamsScreen> createState() => _SupervisorTeamsScreenState();
}

class _SupervisorTeamsScreenState extends State<SupervisorTeamsScreen> {
  final SupervisorRepository _repo = getIt<SupervisorRepository>();

  bool _loading = true;
  String? _error;
  List<SupervisorTeam> _teams = [];
  bool _fabOpen = false;
  bool _checkingAvailability = false;

  bool _loadingAlternates = true;
  String? _alternatesError;
  List<SupervisorAltStaffTemplate> _alternates = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadAlternates();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final teams = await _repo.fetchTeams();
      if (!mounted) return;
      setState(() {
        _teams = teams;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load teams';
        _loading = false;
      });
    }
  }

  Future<void> _loadAlternates() async {
    setState(() {
      _loadingAlternates = true;
      _alternatesError = null;
    });
    try {
      final alternates = await _repo.fetchAlternativeStaffTemplates();
      if (!mounted) return;
      setState(() {
        _alternates = alternates;
        _loadingAlternates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _alternatesError = 'Failed to load alternates';
        _loadingAlternates = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SupervisorTheme.background,
      appBar: AppBar(
        backgroundColor: SupervisorTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Teams'),
      ),
      body: SupervisorPatternBackground(child: _body()),
      floatingActionButton: _buildSpeedDialFab(),
    );
  }

  Widget _buildSpeedDialFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _fabOpen
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _speedDialAction(
                      label: 'Alternate',
                      icon: Icons.swap_horiz_rounded,
                      onTap: _onAddAlternateTap,
                    ),
                    const SizedBox(height: 10),
                    _speedDialAction(
                      label: 'Team',
                      icon: Icons.groups_2_rounded,
                      onTap: _onAddTeamTap,
                    ),
                    const SizedBox(height: 10),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        FloatingActionButton(
          backgroundColor: SupervisorTheme.accent,
          foregroundColor: Colors.white,
          onPressed: _checkingAvailability
              ? null
              : () => setState(() => _fabOpen = !_fabOpen),
          child: _checkingAvailability
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(_fabOpen ? Icons.close_rounded : Icons.add_rounded),
        ),
      ],
    );
  }

  Widget _speedDialAction({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: SupervisorTheme.surface,
            borderRadius: BorderRadius.circular(10),
            boxShadow: SupervisorTheme.softShadow,
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: SupervisorTheme.strongText,
            ),
          ),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.small(
          heroTag: label,
          backgroundColor: SupervisorTheme.surface,
          foregroundColor: SupervisorTheme.accent,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }

  Future<void> _onAddAlternateTap() async {
    setState(() => _fabOpen = false);
    final created = await SupervisorAltStaffTemplateForm.show(context);
    if (created == true) await _loadAlternates();
  }

  Future<void> _onAddTeamTap() async {
    setState(() => _fabOpen = false);
    setState(() => _checkingAvailability = true);
    bool hasAvailableStaff;
    try {
      final results = await Future.wait([
        _repo.fetchAvailableDrivers(),
        _repo.fetchAvailableOperators(),
      ]);
      hasAvailableStaff = results[0].isNotEmpty && results[1].isNotEmpty;
    } catch (_) {
      // If the availability check fails, fall back to letting the form's
      // own load/error handling surface the problem.
      hasAvailableStaff = true;
    }
    if (!mounted) return;
    setState(() => _checkingAvailability = false);

    if (!hasAvailableStaff) {
      final wantsAlternate = await SupervisorNoStaffDialog.show(context);
      if (!mounted || !wantsAlternate) return;
      final created = await SupervisorAltStaffTemplateForm.show(context);
      if (created == true) await _loadAlternates();
      return;
    }

    final created = await SupervisorAddTeamForm.show(context);
    if (created == true) await _load();
  }

  Widget _body() {
    if (_loading) return const SupervisorLoadingView();
    if (_error != null) {
      return SupervisorErrorView(message: _error!, onRetry: _load);
    }
    if (_teams.isEmpty) {
      return SupervisorEmptyView(
        message: 'No staff templates found.',
        icon: Icons.groups_2_rounded,
        onRefresh: _load,
      );
    }

    // Today's assignments (shared SupervisorBloc), so each team card can show
    // whether it's on a trip right now, its attendance, and a "View trip"
    // action — without a second network round trip.
    return BlocBuilder<SupervisorBloc, SupervisorState>(
      builder: (context, state) {
        final indexed = _teams.asMap().entries.toList();
        final assigned = indexed
            .where((e) => _assignmentsFor(e.value, state.assignments).isNotEmpty)
            .toList();
        final unassigned = indexed
            .where((e) => _assignmentsFor(e.value, state.assignments).isEmpty)
            .toList();

        Future<void> refresh() async {
          await Future.wait([
            _load(),
            () async {
              context
                  .read<SupervisorBloc>()
                  .add(const SupervisorRefreshRequested());
            }(),
          ]);
        }

        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'Assigned',
                        value: assigned.length,
                        color: SupervisorTheme.success,
                        icon: Icons.assignment_turned_in_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Unassigned',
                        value: unassigned.length,
                        color: SupervisorTheme.warning,
                        icon: Icons.hourglass_empty_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TabBar(
                  labelColor: SupervisorTheme.accent,
                  unselectedLabelColor: SupervisorTheme.mutedText,
                  indicatorColor: SupervisorTheme.accent,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Assigned (${assigned.length})'),
                    Tab(text: 'Unassigned (${unassigned.length})'),
                    Tab(text: 'Alternates (${_alternates.length})'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _teamList(assigned, state.assignments, refresh,
                        'No teams assigned to a trip today.'),
                    _teamList(unassigned, state.assignments, refresh,
                        'Every team is assigned to a trip today.'),
                    _alternateList(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _teamList(
    List<MapEntry<int, SupervisorTeam>> entries,
    List<SupervisorAssignment> assignments,
    Future<void> Function() onRefresh,
    String emptyMessage,
  ) {
    if (entries.isEmpty) {
      return SupervisorEmptyView(
        message: emptyMessage,
        icon: Icons.groups_2_rounded,
        onRefresh: onRefresh,
      );
    }
    return RefreshIndicator(
      color: SupervisorTheme.accent,
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final team = entries[i].value;
          final teamAssignments = _assignmentsFor(team, assignments);
          final assignment = _primaryAssignment(teamAssignments);
          return _TeamCard(
            team: team,
            index: entries[i].key,
            assignment: assignment,
            assignments: teamAssignments,
            onEdit: () => _onEditTeam(team),
          );
        },
      ),
    );
  }

  Widget _alternateList() {
    if (_loadingAlternates) return const SupervisorLoadingView();
    if (_alternatesError != null) {
      return SupervisorErrorView(
        message: _alternatesError!,
        onRetry: _loadAlternates,
      );
    }
    if (_alternates.isEmpty) {
      return SupervisorEmptyView(
        message: 'No alternative staff templates found.',
        icon: Icons.swap_horiz_rounded,
        onRefresh: _loadAlternates,
      );
    }
    return RefreshIndicator(
      color: SupervisorTheme.accent,
      onRefresh: _loadAlternates,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
        itemCount: _alternates.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _AlternateCard(alt: _alternates[i]),
      ),
    );
  }

  List<SupervisorAssignment> _assignmentsFor(
    SupervisorTeam team,
    List<SupervisorAssignment> assignments,
  ) {
    final matches = assignments
        .where((a) => a.staffTemplateId == team.uniqueId)
        .toList()
      ..sort((a, b) {
        final rankA = _assignmentSortRank(a);
        final rankB = _assignmentSortRank(b);
        if (rankA != rankB) return rankA.compareTo(rankB);
        final dateA = a.tripDate;
        final dateB = b.tripDate;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.compareTo(dateB);
      });
    return matches;
  }

  SupervisorAssignment? _primaryAssignment(List<SupervisorAssignment> matches) {
    if (matches.isEmpty) return null;
    for (final a in matches) {
      if (a.isInProgress) return a;
    }
    return matches.first;
  }

  int _assignmentSortRank(SupervisorAssignment assignment) {
    if (assignment.isInProgress) return 0;
    if (assignment.isScheduled) return 1;
    if (assignment.isCompleted) return 2;
    if (assignment.isCancelled) return 3;
    return 4;
  }

  Future<void> _onEditTeam(SupervisorTeam team) async {
    final onTrip = _assignmentsFor(team, context.read<SupervisorBloc>().state.assignments)
        .any((a) => a.isInProgress);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SupervisorTheme.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Edit team?',
          style: TextStyle(
            color: SupervisorTheme.strongText,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          onTrip
              ? 'This team is on a trip right now. If you change the driver '
                  'or operator, the trip will immediately reflect the new '
                  'crew, and both the outgoing and incoming staff will be '
                  'notified. Continue?'
              : 'If you change the driver or operator, both the outgoing '
                  'and incoming staff will be notified. Continue?',
          style: const TextStyle(color: SupervisorTheme.mutedText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: SupervisorTheme.mutedText,
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SupervisorTheme.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final saved = await SupervisorAddTeamForm.show(context, existingTeam: team);
    if (saved == true) {
      await _load();
      if (!mounted) return;
      context.read<SupervisorBloc>().add(const SupervisorRefreshRequested());
    }
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.index,
    required this.assignment,
    required this.assignments,
    this.onEdit,
  });

  final SupervisorTeam team;
  final int index;
  final SupervisorAssignment? assignment;
  final List<SupervisorAssignment> assignments;
  final VoidCallback? onEdit;

  bool get _onTrip => assignment?.isInProgress ?? false;

  Color get _statusColor {
    if (_onTrip) return SupervisorTheme.success;
    switch (team.status.toUpperCase()) {
      case 'ACTIVE':
        return SupervisorTheme.success;
      case 'INACTIVE':
        return SupervisorTheme.mutedText;
      default:
        return SupervisorTheme.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final crew = assignment?.crew;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _onTrip
            ? SupervisorTheme.success.withValues(alpha: 0.10)
            : SupervisorTheme.surface,
        borderRadius: SupervisorTheme.cardRadius,
        border: Border.all(
          color: _onTrip
              ? SupervisorTheme.success.withValues(alpha: 0.45)
              : SupervisorTheme.hairline.withValues(alpha: 0.6),
        ),
        boxShadow: SupervisorTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (crew != null &&
                  (crew.driver != null ||
                      crew.operator != null ||
                      crew.extraOperators.isNotEmpty)) ...[
                CrewAvatarStack(
                  crew: crew,
                  size: 24,
                  overlap: 13,
                  borderColor: SupervisorTheme.surface,
                ),
                const SizedBox(width: 10),
              ] else ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: SupervisorTheme.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: SupervisorTheme.accent,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  'Team ${index + 1}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _onTrip ? 'ON TRIP' : team.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: _statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _memberRow(
            icon: Icons.local_shipping_rounded,
            label: 'Driver',
            value: team.driverName.isNotEmpty ? team.driverName : 'Unassigned',
            attendanceStatus: crew?.driver?.attendanceStatus,
          ),
          const SizedBox(height: 8),
          _memberRow(
            icon: Icons.engineering_rounded,
            label: 'Operator',
            value:
                team.operatorName.isNotEmpty ? team.operatorName : 'Unassigned',
            attendanceStatus: crew?.operator?.attendanceStatus,
          ),
          if (team.extraCount > 0) ...[
            const SizedBox(height: 8),
            _memberRow(
              icon: Icons.group_add_rounded,
              label: 'Extra operators',
              value: '${team.extraCount}',
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (assignment != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAssignmentsDialog(context),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('View trips'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SupervisorTheme.accent,
                      side: BorderSide(
                        color: SupervisorTheme.accent.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: SupervisorTheme.chipRadius,
                      ),
                    ),
                  ),
                ),
              if (assignment != null && onEdit != null)
                const SizedBox(width: 10),
              if (onEdit != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SupervisorTheme.mutedText,
                      side: BorderSide(
                        color: SupervisorTheme.hairline.withValues(alpha: 0.8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: SupervisorTheme.chipRadius,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _memberRow({
    required IconData icon,
    required String label,
    required String value,
    String? attendanceStatus,
  }) {
    final isPresent = attendanceStatus == 'Present';
    return Row(
      children: [
        Icon(icon, size: 15, color: SupervisorTheme.mutedText),
        const SizedBox(width: 8),
        Text(
          '$label:  ',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: SupervisorTheme.mutedText,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: SupervisorTheme.strongText,
            ),
          ),
        ),
        if (attendanceStatus != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: (isPresent ? SupervisorTheme.success : SupervisorTheme.danger)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              attendanceStatus,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color:
                    isPresent ? SupervisorTheme.success : SupervisorTheme.danger,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showAssignmentsDialog(BuildContext context) {
    SupervisorAssignmentPickerDialog.show(
      context,
      title: 'Team ${index + 1}',
      assignments: assignments,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SupervisorTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: SupervisorTheme.mutedText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlternateCard extends StatelessWidget {
  const _AlternateCard({required this.alt});

  final SupervisorAltStaffTemplate alt;

  Color get _statusColor {
    switch (alt.approvalStatus.toUpperCase()) {
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: SupervisorTheme.cardRadius,
        border: Border.all(color: SupervisorTheme.hairline.withValues(alpha: 0.6)),
        boxShadow: SupervisorTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  alt.displayCode.isNotEmpty ? alt.displayCode : alt.uniqueId,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  alt.approvalStatus.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: _statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _row(Icons.local_shipping_rounded, 'Driver',
              alt.driverName.isNotEmpty ? alt.driverName : 'Unassigned'),
          const SizedBox(height: 8),
          _row(Icons.engineering_rounded, 'Operator',
              alt.operatorName.isNotEmpty ? alt.operatorName : 'Unassigned'),
          const SizedBox(height: 8),
          _row(
            Icons.date_range_rounded,
            'Dates',
            [alt.fromDate, alt.toDate].where((v) => v.isNotEmpty).join(' → '),
          ),
          if (alt.changeReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            _row(Icons.notes_rounded, 'Reason', alt.changeReason),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 15, color: SupervisorTheme.mutedText),
        const SizedBox(width: 8),
        Text(
          '$label:  ',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: SupervisorTheme.mutedText,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: SupervisorTheme.strongText,
            ),
          ),
        ),
      ],
    );
  }
}
