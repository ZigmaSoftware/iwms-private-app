import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:iwms_private_app/core/di.dart';
import '../../data/supervisor_models.dart';
import '../../data/supervisor_repository.dart';
import '../theme/supervisor_theme.dart';
import '../widgets/supervisor_assignment_card.dart';
import '../widgets/supervisor_assignment_detail_sheet.dart';

/// Assignment-based history includes completed/cancelled trips with no log.
/// Query filters and pagination run on the server across the whole result set.
class SupervisorHistoryScreen extends StatefulWidget {
  const SupervisorHistoryScreen(
      {super.key,
      this.embedded = false,
      this.initialDate,
      this.serviceDate,
      this.repository,
      this.refreshRevision = 0});
  final bool embedded;
  final DateTime? initialDate;
  final DateTime? serviceDate;
  final SupervisorRepository? repository;
  final int refreshRevision;
  @override
  State<SupervisorHistoryScreen> createState() =>
      _SupervisorHistoryScreenState();
}

class _SupervisorHistoryScreenState extends State<SupervisorHistoryScreen>
    with WidgetsBindingObserver {
  late final SupervisorRepository _repo =
      widget.repository ?? getIt<SupervisorRepository>();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  int _generation = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _failedMore = false;
  String? _error;
  List<SupervisorAssignment> _items = [];
  int _count = 0;
  int _offset = 0;
  DateTime? _serviceDate;
  DateTime? _from;
  DateTime? _to;
  String? _status;
  bool _retripOnly = false;
  bool _exceptionsOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serviceDate = widget.serviceDate;
    _from =
        widget.initialDate ?? _serviceDate?.subtract(const Duration(days: 6));
    _to = widget.initialDate ?? _serviceDate;
    _load();
  }

  @override
  void didUpdateWidget(covariant SupervisorHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRevision != widget.refreshRevision) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.embedded) _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || _loadingMore || !_hasMore)) return;
    final generation = more ? _generation : ++_generation;
    setState(() {
      _error = null;
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _loadingMore = false;
      }
    });
    try {
      final page = await _repo.fetchTripHistoryPage(
          from: _from,
          to: _to,
          status: _status,
          search: _search.text,
          retripOnly: _retripOnly,
          exceptionsOnly: _exceptionsOnly,
          offset: more ? _offset : 0);
      if (!mounted || generation != _generation) return;
      setState(() {
        _serviceDate = page.serviceDate;
        _from ??= page.serviceDate.subtract(const Duration(days: 6));
        _to ??= page.serviceDate;
        final merged = <String, SupervisorAssignment>{
          if (more)
            for (final a in _items) a.uniqueId: a,
          for (final a in page.items) a.uniqueId: a,
        };
        _items = merged.values.toList();
        _count = page.count;
        _offset = (more ? _offset : 0) + page.items.length;
        _hasMore = page.hasMore && page.items.isNotEmpty;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _failedMore = more;
        _error = e is SupervisorException && e.code == 'FORBIDDEN'
            ? 'You do not have access to trip history.'
            : 'Could not load trip history. Please retry.';
        if (e is SupervisorException && e.code == 'FORBIDDEN') _items = [];
      });
    }
  }

  void _filterChanged() {
    _debounce?.cancel();
    // Immediately invalidate responses for the previous filters.
    _generation++;
    setState(() {
      _items = [];
      _offset = 0;
      _count = 0;
      _hasMore = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
  }

  Future<void> _dateRange() async {
    if (_serviceDate == null) return;
    final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: _serviceDate!,
        initialDateRange: DateTimeRange(start: _from!, end: _to!));
    if (picked == null || !mounted) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
    });
    _filterChanged();
  }

  void _range(int days, {bool yesterday = false}) {
    if (_serviceDate == null) return;
    setState(() {
      _to = _serviceDate!.subtract(Duration(days: yesterday ? 1 : 0));
      _from = _to!.subtract(Duration(days: days - 1));
    });
    _filterChanged();
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
        color: SupervisorTheme.accent,
        onRefresh: _load,
        child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                                controller: _search,
                                style: SupervisorTheme.inputTextStyle,
                                decoration: SupervisorTheme.inputDecoration(
                                        'Search history',
                                        hintText:
                                            'Trip, vehicle, driver or area')
                                    .copyWith(
                                        prefixIcon: const Icon(Icons.search)),
                                onChanged: (_) {
                                  _debounce?.cancel();
                                  _generation++;
                                  setState(() {
                                    _items = [];
                                    _count = 0;
                                    _loading = true;
                                  });
                                  _debounce = Timer(
                                      const Duration(milliseconds: 350),
                                      _filterChanged);
                                }),
                            Wrap(spacing: 8, children: [
                              TextButton(
                                  onPressed: _serviceDate == null
                                      ? null
                                      : () => _range(1),
                                  child: const Text('Today')),
                              TextButton(
                                  onPressed: _serviceDate == null
                                      ? null
                                      : () => _range(1, yesterday: true),
                                  child: const Text('Yesterday')),
                              TextButton(
                                  onPressed: _serviceDate == null
                                      ? null
                                      : () => _range(7),
                                  child: const Text('Last 7 days')),
                              TextButton.icon(
                                  onPressed:
                                      _serviceDate == null ? null : _dateRange,
                                  icon: const Icon(Icons.date_range, size: 18),
                                  label: const Text('Custom')),
                            ]),
                            if (_from != null && _to != null)
                              Text(
                                  '${DateFormat('d MMM yyyy').format(_from!)} – ${DateFormat('d MMM yyyy').format(_to!)}',
                                  style: const TextStyle(
                                      color: SupervisorTheme.mutedText,
                                      fontSize: 12)),
                            Wrap(spacing: 8, children: [
                              for (final entry in <String?, String>{
                                null: 'All outcomes',
                                'Completed': 'Completed',
                                'Cancelled': 'Cancelled'
                              }.entries)
                                ChoiceChip(
                                    label: Text(entry.value),
                                    selected: _status == entry.key,
                                    onSelected: (_) {
                                      setState(() => _status = entry.key);
                                      _filterChanged();
                                    }),
                              FilterChip(
                                  label: const Text('Re-Trips'),
                                  selected: _retripOnly,
                                  onSelected: (v) {
                                    setState(() => _retripOnly = v);
                                    _filterChanged();
                                  }),
                              FilterChip(
                                  label: const Text('With exceptions'),
                                  selected: _exceptionsOnly,
                                  onSelected: (v) {
                                    setState(() => _exceptionsOnly = v);
                                    _filterChanged();
                                  }),
                            ]),
                            if (!_loading)
                              Text('$_count trips',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                          ]))),
              if (_loading)
                const SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator())))
              else ...[
                if (_error != null)
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(children: [
                            Text(_error!),
                            if (_items.isNotEmpty)
                              const Text('Showing previously loaded trips.',
                                  style: TextStyle(
                                      color: SupervisorTheme.mutedText)),
                            TextButton(
                                onPressed: () => _load(more: _failedMore),
                                child: const Text('Retry')),
                          ]))),
                if (_items.isEmpty && _error == null)
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 36, horizontal: 20),
                          child: Column(children: [
                            const Icon(Icons.history,
                                size: 44, color: SupervisorTheme.accent),
                            const SizedBox(height: 12),
                            const Text(
                                'No trips match this date range and filters.',
                                textAlign: TextAlign.center),
                            TextButton(
                                onPressed: () {
                                  setState(() {
                                    _status = null;
                                    _retripOnly = false;
                                    _exceptionsOnly = false;
                                    _search.clear();
                                  });
                                  _range(7);
                                },
                                child: const Text('Reset filters')),
                          ]))),
                SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                      final a = _items[index];
                      final date = a.tripDate == null
                          ? 'Date unavailable'
                          : DateFormat('EEE, d MMM yyyy').format(a.tripDate!);
                      final showDate = index == 0 ||
                          _items[index - 1].tripDate != a.tripDate;
                      return Padding(
                          key: ValueKey(a.uniqueId),
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showDate)
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      child: Text(date,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color:
                                                  SupervisorTheme.mutedText))),
                                SupervisorAssignmentCard(
                                    assignment: a,
                                    historical: true,
                                    onTap: () =>
                                        SupervisorAssignmentDetailSheet.show(
                                            context, a)),
                              ]));
                    }, childCount: _items.length))),
                if (_hasMore)
                  SliverToBoxAdapter(
                      child: Center(
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: _loadingMore
                                  ? const CircularProgressIndicator()
                                  : OutlinedButton(
                                      onPressed: () => _load(more: true),
                                      child: const Text('Load more trips'))))),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 130)),
            ]));
    if (widget.embedded) return body;
    return Scaffold(
        backgroundColor: SupervisorTheme.background,
        appBar: AppBar(
            title: const Text('Trip history'),
            backgroundColor: SupervisorTheme.primary,
            foregroundColor: Colors.white),
        body: body);
  }
}
