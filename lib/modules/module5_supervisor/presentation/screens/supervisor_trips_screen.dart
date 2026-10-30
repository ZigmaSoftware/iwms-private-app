import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../data/supervisor_models.dart';
import '../../data/supervisor_trip_workbench.dart';
import '../../logic/supervisor_bloc.dart';
import '../theme/supervisor_theme.dart';
import '../widgets/supervisor_assignment_card.dart';
import '../widgets/supervisor_assignment_detail_sheet.dart';
import '../widgets/supervisor_retrip_panel.dart';
import '../widgets/supervisor_state_views.dart';
import '../widgets/supervisor_trip_actions_sheet.dart';
import 'supervisor_breakdowns_screen.dart';
import 'supervisor_history_screen.dart';
import 'supervisor_retrip_review_screen.dart';
import 'supervisor_trip_map_screen.dart';

enum _TripFilter { all, running, scheduled, attention }

class SupervisorTripsScreen extends StatefulWidget {
  const SupervisorTripsScreen({super.key});
  @override
  State<SupervisorTripsScreen> createState() => _SupervisorTripsScreenState();
}

class _SupervisorTripsScreenState extends State<SupervisorTripsScreen> {
  _TripFilter _filter = _TripFilter.all;
  bool _history = false;
  bool _historyVisited = false;
  DateTime? _historyDate;
  int _historyRevision = 0;
  int _historyRefresh = 0;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openHistory({DateTime? date}) => setState(() {
        if (_history && date == null) return;
        _history = true;
        if (!_historyVisited || date != null) {
          _historyDate = date;
          _historyRevision++;
        }
        _historyVisited = true;
        _historyRefresh++;
      });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SupervisorTheme.background,
      child: SafeArea(
          bottom: false,
          child: BlocBuilder<SupervisorBloc, SupervisorState>(
            builder: (context, state) => Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Trips',
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: SupervisorTheme.strongText)),
                          if (!_history && state.updatedAt != null)
                            Text(
                                'Updated ${DateFormat('HH:mm').format(state.updatedAt!)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: SupervisorTheme.mutedText)),
                        ])),
                    IconButton(
                        tooltip: 'Refresh trips',
                        onPressed: state.refreshing
                            ? null
                            : () {
                                if (_history) {
                                  setState(() => _historyRefresh++);
                                } else {
                                  context.read<SupervisorBloc>().refresh();
                                }
                              },
                        icon: const Icon(Icons.refresh)),
                  ])),
              if (state.refreshing)
                const LinearProgressIndicator(
                    minHeight: 2, color: SupervisorTheme.accent),
              Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                  child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          color: SupervisorTheme.surfaceMuted,
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Expanded(
                            child: _tab(
                                'Active · ${state.activeTrips.length}',
                                !_history,
                                () => setState(() => _history = false))),
                        Expanded(
                            child: _tab(
                                'History', _history, () => _openHistory())),
                      ]))),
              Expanded(
                  child: IndexedStack(index: _history ? 1 : 0, children: [
                _active(context, state),
                if (_historyVisited)
                  SupervisorHistoryScreen(
                    key: ValueKey(_historyRevision),
                    embedded: true,
                    initialDate: _historyDate,
                    refreshRevision: _historyRefresh,
                    serviceDate: state.workbench?.serviceDate,
                  )
                else
                  const SizedBox.shrink(),
              ])),
            ]),
          )),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) => Semantics(
        selected: selected,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? SupervisorTheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: selected ? SupervisorTheme.softShadow : null,
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? SupervisorTheme.strongText
                        : SupervisorTheme.mutedText)),
          ),
        ),
      );

  Widget _active(BuildContext context, SupervisorState state) {
    if (state.workbench == null) {
      if (state.status == SupervisorStatus.failure) {
        return SupervisorErrorView(
            message: state.errorMessage ?? 'Could not load trips.',
            onRetry: () => context.read<SupervisorBloc>().refresh());
      }
      return const SupervisorLoadingView();
    }
    final board = state.workbench!;
    final active = state.activeTrips;
    final attention = active
        .where((a) => a.attentionLabels(board.serverNow).isNotEmpty)
        .toList();
    final query = _search.text.trim().toLowerCase();
    final visible = active.where((a) {
      final matches = switch (_filter) {
        _TripFilter.all => true,
        _TripFilter.running => a.isInProgress,
        _TripFilter.scheduled => a.isScheduled,
        _TripFilter.attention => attention.contains(a),
      };
      return matches &&
          (query.isEmpty ||
              '${a.uniqueId} ${a.tripCode} ${a.areaName} ${a.vehicleNo} ${a.driverName}'
                  .toLowerCase()
                  .contains(query));
    }).toList();
    final earlier = visible.where((a) => !board.isToday(a)).toList();
    final running =
        visible.where((a) => board.isToday(a) && a.isInProgress).toList();
    final scheduled =
        visible.where((a) => board.isToday(a) && !a.isInProgress).toList();
    int compare(SupervisorAssignment a, SupervisorAssignment b) {
      final priority = (a.attentionLabels(board.serverNow).isEmpty ? 1 : 0)
          .compareTo(b.attentionLabels(board.serverNow).isEmpty ? 1 : 0);
      if (priority != 0) return priority;
      final byDate = a.tripDate!.compareTo(b.tripDate!);
      if (byDate != 0) return byDate;
      final byTime = a.scheduledTime.compareTo(b.scheduledTime);
      return byTime != 0 ? byTime : a.uniqueId.compareTo(b.uniqueId);
    }

    earlier.sort(compare);
    running.sort(compare);
    scheduled.sort(compare);

    return RefreshIndicator(
      onRefresh: () => context.read<SupervisorBloc>().refresh(),
      color: SupervisorTheme.accent,
      child: ListView(
          key: const PageStorageKey('supervisor-active-trips'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 130),
          children: [
            if (state.errorMessage != null)
              _notice(state.errorMessage!, Icons.cloud_off),
            if (state.attentionError != null)
              _notice(state.attentionError!, Icons.warning_amber),
            if (state.pendingRetripRequests.isNotEmpty)
              SupervisorRetripRequestsPanel(
                requests: state.pendingRetripRequests,
                onReview: (request) async {
                  await SupervisorRetripReviewScreen.push(context, request);
                  if (context.mounted) {
                    await context.read<SupervisorBloc>().refresh();
                  }
                },
              ),
            if (state.pendingBreakdowns.isNotEmpty)
              Card(
                  child: ListTile(
                leading:
                    const Icon(Icons.car_repair, color: SupervisorTheme.danger),
                title: Text(
                    '${state.pendingBreakdowns.length} breakdown reports need review'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SupervisorBreakdownsScreen()));
                  if (context.mounted) {
                    await context.read<SupervisorBloc>().refresh();
                  }
                },
              )),
            _summary(board, state),
            if (active.length > _searchThreshold || query.isNotEmpty) ...[
              const SizedBox(height: 12),
              TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: SupervisorTheme.inputTextStyle,
                  decoration: SupervisorTheme.inputDecoration('Search trips',
                          hintText: 'Trip, vehicle, driver or area')
                      .copyWith(
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () =>
                                      setState(() => _search.clear()),
                                  icon: const Icon(Icons.close)))),
            ],
            if (active.length > 1)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final entry in <_TripFilter, String>{
                      _TripFilter.all: 'All · ${active.length}',
                      _TripFilter.running:
                          'Running · ${active.where((a) => a.isInProgress).length}',
                      _TripFilter.scheduled:
                          'Not started · ${active.where((a) => a.isScheduled).length}',
                      if (attention.isNotEmpty ||
                          _filter == _TripFilter.attention)
                        _TripFilter.attention:
                            'Needs attention · ${attention.length}',
                    }.entries)
                      SupervisorFilterChip(
                          label: entry.value,
                          selected: _filter == entry.key,
                          onTap: () => setState(() => _filter = entry.key)),
                  ])),
            if (active.isEmpty)
              _empty(state)
            else if (visible.isEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(children: [
                    Text(_filter == _TripFilter.running && query.isEmpty
                        ? 'No trips running right now.'
                        : 'No trips match these filters.'),
                    TextButton(
                        onPressed: () => setState(() {
                              _filter = _TripFilter.all;
                              _search.clear();
                            }),
                        child: const Text('Show all remaining trips')),
                  ])),
            ..._group(
                'From earlier days', earlier, state, SupervisorTheme.warning),
            ..._group('Running now', running, state, SupervisorTheme.info),
            ..._group(
                'Not started', scheduled, state, SupervisorTheme.mutedText),
          ]),
    );
  }

  /// Below this many active trips the search box is just clutter — the whole
  /// list fits on a screen or two.
  static const _searchThreshold = 5;

  Widget _summary(SupervisorTripWorkbench board, SupervisorState state) {
    final cancelled = board.today.where((a) => a.isCancelled).length;
    Widget stat(String label, int value, Color color) => Expanded(
          child: Column(children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: SupervisorTheme.mutedText)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: SupervisorTheme.cardRadius,
        border:
            Border.all(color: SupervisorTheme.hairline.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Today, ${DateFormat('EEE d MMM').format(board.serviceDate)}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: SupervisorTheme.mutedText)),
          const SizedBox(height: 12),
          Row(children: [
            stat('Planned', board.today.length, SupervisorTheme.strongText),
            stat('Done', state.completed.length, SupervisorTheme.success),
            stat('Remaining', board.today.where((a) => a.isRemaining).length,
                SupervisorTheme.accent),
            if (cancelled > 0)
              stat('Cancelled', cancelled, SupervisorTheme.danger),
          ]),
          if (state.carriedOver.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: SupervisorTheme.warning.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.history_rounded,
                    size: 16, color: Color(0xFF9A6A0E)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        state.carriedOver.length == 1
                            ? '1 trip from an earlier day is still open'
                            : '${state.carriedOver.length} trips from earlier days are still open',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF7A530A)))),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  // The screen's own outer `Container(color: SupervisorTheme.background)`
  // paints as a ColoredBox that sits between this ListTile and the nearest
  // Material ancestor (Scaffold's), which hides its tileColor/ink — Flutter
  // flags this as a debug assertion. Giving the tile its own transparent
  // Material fixes it without changing how it looks.
  Widget _notice(String message, IconData icon) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          tileColor: SupervisorTheme.warning.withValues(alpha: .1),
          leading: Icon(icon, color: SupervisorTheme.warning),
          title: Text(message),
        ),
      ));

  Widget _empty(SupervisorState state) {
    final today = state.assignments;
    final allCompleted = today.isNotEmpty && today.every((a) => a.isCompleted);
    final safeSuccess = allCompleted &&
        !state.hasOutstandingDecisions &&
        state.errorMessage == null;
    final title = state.hasOutstandingDecisions || state.errorMessage != null
        ? 'No active trips in the last update.'
        : allCompleted
            ? 'All today’s trips completed.'
            : today.isEmpty
                ? 'No trips scheduled today.'
                : 'No remaining trips.';
    return Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
            color: SupervisorTheme.surface,
            borderRadius: SupervisorTheme.cardRadius),
        child: Column(children: [
          Icon(safeSuccess ? Icons.task_alt : Icons.route_outlined,
              size: 48,
              color: safeSuccess
                  ? SupervisorTheme.success
                  : SupervisorTheme.accent),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
              state.hasOutstandingDecisions
                  ? 'Check the decisions and update notices above.'
                  : today.isEmpty
                      ? 'New assignments will appear here when they are scheduled.'
                      : '${state.completed.length} completed · ${today.where((a) => a.isCancelled).length} cancelled',
              textAlign: TextAlign.center,
              style: const TextStyle(color: SupervisorTheme.mutedText)),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: () => _openHistory(
                  date: today.isEmpty ? null : state.workbench!.serviceDate),
              child: Text(today.isEmpty
                  ? 'View trip history'
                  : 'View today’s history')),
        ]));
  }

  List<Widget> _group(String title, List<SupervisorAssignment> items,
          SupervisorState state, Color dot) =>
      items.isEmpty
          ? []
          : [
              Padding(
                  padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
                  child: Row(children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration:
                            BoxDecoration(color: dot, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: SupervisorTheme.strongText))),
                    const SizedBox(width: 6),
                    Text('${items.length}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: SupervisorTheme.mutedText)),
                  ])),
              for (final a in items)
                Padding(
                    key: ValueKey(a.uniqueId),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SupervisorAssignmentCard(
                      assignment: a,
                      serverNow: state.workbench!.serverNow,
                      onTap: () =>
                          SupervisorAssignmentDetailSheet.show(context, a),
                      onNavigate: a.isInProgress
                          ? () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => SupervisorTripMapScreen(
                                  assignmentId: a.uniqueId,
                                  title: a.areaName,
                                  driverName: a.driverName,
                                  vehicleNo: a.vehicleNo,
                                  tripDate: a.tripDate)))
                          : null,
                      onAlertHandled: () =>
                          context.read<SupervisorBloc>().refresh(),
                      onActions: () async {
                        await SupervisorTripActionsSheet.show(context,
                            assignmentId: a.uniqueId, assignment: a);
                        if (mounted) {
                          await context.read<SupervisorBloc>().refresh();
                        }
                      },
                    )),
            ];
}
