import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:iwms_private_app/core/env.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/logic/supervisor_bloc.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_point_location_map_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_cards.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_point_status_sheet.dart';

const int _kPageSize = 20;

class SupervisorCollectionPointsScreen extends StatefulWidget {
  const SupervisorCollectionPointsScreen({super.key});

  @override
  State<SupervisorCollectionPointsScreen> createState() =>
      _SupervisorCollectionPointsScreenState();
}

enum _PointFilter { all, assigned, unassigned, serviced }

class _SupervisorCollectionPointsScreenState
    extends State<SupervisorCollectionPointsScreen> {
  final SupervisorRepository _repo = SupervisorRepository();

  bool _loading = true;
  String? _error;
  List<SupervisorCollectionPoint> _items = const [];
  _PointFilter _filter = _PointFilter.all;
  int _page = 0;

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
      final items = await _repo.fetchCollectionPoints();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _page = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
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
        title: const Text('Collection Points'),
      ),
      body: BlocBuilder<SupervisorBloc, SupervisorState>(
        builder: (context, state) {
          final assignmentMap = _buildAssignmentMap(state.assignments);
          final filtered = _applyFilter(_items, assignmentMap);
          final summary = _buildSummary(_items, assignmentMap);
          final start = (_page * _kPageSize).clamp(0, filtered.length);
          final end = (start + _kPageSize).clamp(0, filtered.length);
          final pageItems = filtered.sublist(start, end);
          final pageCount =
              filtered.isEmpty ? 1 : ((filtered.length - 1) ~/ _kPageSize) + 1;
          if (_page >= pageCount) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _page = pageCount - 1);
            });
          }
          return RefreshIndicator(
            color: SupervisorTheme.accent,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _HeaderGrid(summary: summary),
                const SizedBox(height: 1),
                _FilterRow(
                  filter: _filter,
                  onChanged: (value) => setState(() {
                    _filter = value;
                    _page = 0;
                  }),
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: SupervisorTheme.accent,
                      ),
                    ),
                  )
                else if (_error != null)
                  _ErrorCard(message: _error!, onRetry: _load)
                else if (pageItems.isEmpty)
                  const _EmptyCard(message: 'No collection points found.')
                else
                  ...pageItems.map((item) {
                    final records = assignmentMap[item.uniqueId] ?? const [];
                    final status = _resolveStatus(records);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CollectionPointCard(
                        item: item,
                        onViewStatus: () => _showStatusDialog(
                          context,
                          item: item,
                          records: records,
                          status: status,
                        ),
                        onShowQr: item.binQrUrl.trim().isEmpty
                            ? null
                            : () => _showQrDialog(
                                  context,
                                  title: item.name,
                                  qrUrl: item.binQrUrl,
                                  details: [
                                    _DialogDetail(
                                      label: 'Collection point ID',
                                      value: item.uniqueId,
                                    ),
                                    _DialogDetail(
                                      label: 'Area',
                                      value: item.scopeLabel,
                                    ),
                                    _DialogDetail(
                                      label: 'Bins',
                                      value: '${item.binCount}',
                                    ),
                                  ],
                                ),
                      ),
                    );
                  }),
                if (!_loading && _error == null && filtered.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _PaginationRow(
                    start: start,
                    end: end,
                    total: filtered.length,
                    page: _page,
                    pageCount: pageCount,
                    onPrevious:
                        _page > 0 ? () => setState(() => _page -= 1) : null,
                    onNext: _page + 1 < pageCount
                        ? () => setState(() => _page += 1)
                        : null,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Map<String, List<_PointRecord>> _buildAssignmentMap(
    List<SupervisorAssignment> assignments,
  ) {
    final out = <String, List<_PointRecord>>{};
    for (final assignment in assignments) {
      for (final stop in assignment.stops) {
        if (stop.isHousehold || (stop.entityId ?? '').isEmpty) continue;
        out.putIfAbsent(stop.entityId!, () => []).add(
              _PointRecord(assignment: assignment, stop: stop),
            );
      }
    }
    return out;
  }

  List<SupervisorCollectionPoint> _applyFilter(
    List<SupervisorCollectionPoint> items,
    Map<String, List<_PointRecord>> assignmentMap,
  ) {
    return items.where((item) {
      final records = assignmentMap[item.uniqueId] ?? const [];
      switch (_filter) {
        case _PointFilter.all:
          return true;
        case _PointFilter.assigned:
          return records.isNotEmpty;
        case _PointFilter.unassigned:
          return records.isEmpty;
        case _PointFilter.serviced:
          return records.any((record) => record.stop.isCollected);
      }
    }).toList();
  }

  _HeaderSummary _buildSummary(
    List<SupervisorCollectionPoint> items,
    Map<String, List<_PointRecord>> assignmentMap,
  ) {
    final assigned = items
        .where((item) => (assignmentMap[item.uniqueId] ?? const []).isNotEmpty)
        .length;
    final serviced = items
        .where((item) => (assignmentMap[item.uniqueId] ?? const [])
            .any((record) => record.stop.isCollected))
        .length;
    return _HeaderSummary(
      total: items.length,
      assigned: assigned,
      unassigned: items.length - assigned,
      serviced: serviced,
    );
  }

  _StatusInfo _resolveStatus(List<_PointRecord> records) {
    if (records.isEmpty) {
      return const _StatusInfo('Unassigned', SupervisorTheme.mutedText);
    }
    if (records
        .any((record) => record.stop.status.toLowerCase() == 'collect later')) {
      return const _StatusInfo('Collect Later', SupervisorTheme.warning);
    }
    if (records.any((record) => _isFailure(record.stop.status))) {
      return const _StatusInfo('Not Available', SupervisorTheme.danger);
    }
    if (records.any((record) => record.stop.isCollected)) {
      return const _StatusInfo('Collected', SupervisorTheme.success);
    }
    return const _StatusInfo('Assigned', SupervisorTheme.info);
  }

  void _showStatusDialog(
    BuildContext context, {
    required SupervisorCollectionPoint item,
    required List<_PointRecord> records,
    required _StatusInfo status,
  }) {
    final lat = double.tryParse(item.latitude);
    final lng = double.tryParse(item.longitude);
    final hasLocation = lat != null && lng != null && lat != 0 && lng != 0;
    SupervisorPointStatusSheet.show(
      context,
      title: item.name,
      subtitle: item.scopeLabel,
      visits: records
          .map((record) => SupervisorPointVisit(
                stop: record.stop,
                tripCode: record.assignment.tripCode,
              ))
          .toList(),
      onViewMap: !hasLocation
          ? null
          : () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SupervisorPointLocationMapScreen(
                    title: item.name,
                    latitude: lat,
                    longitude: lng,
                    subtitle: item.scopeLabel,
                  ),
                ),
              );
            },
    );
  }

  void _showQrDialog(
    BuildContext context, {
    required String title,
    required String qrUrl,
    required List<_DialogDetail> details,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QrDialog(
        title: title,
        qrUrl: _resolveMediaUrl(qrUrl),
        details: details,
      ),
    );
  }
}

class _PointRecord {
  const _PointRecord({
    required this.assignment,
    required this.stop,
  });

  final SupervisorAssignment assignment;
  final SupervisorStop stop;
}

class _HeaderSummary {
  const _HeaderSummary({
    required this.total,
    required this.assigned,
    required this.unassigned,
    required this.serviced,
  });

  final int total;
  final int assigned;
  final int unassigned;
  final int serviced;
}

class _StatusInfo {
  const _StatusInfo(this.label, this.color);

  final String label;
  final Color color;
}

class _HeaderGrid extends StatelessWidget {
  const _HeaderGrid({required this.summary});

  final _HeaderSummary summary;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: [
        _MetricCard('Total', '${summary.total}', Icons.apps_rounded,
            SupervisorTheme.info),
        _MetricCard('Assigned', '${summary.assigned}',
            Icons.assignment_turned_in_outlined, SupervisorTheme.accent),
        _MetricCard('Unassigned', '${summary.unassigned}',
            Icons.hourglass_empty_rounded, SupervisorTheme.warning),
        _MetricCard('Service', '${summary.serviced}',
            Icons.check_circle_outline_rounded, SupervisorTheme.success),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SupervisorTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
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

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filter,
    required this.onChanged,
  });

  final _PointFilter filter;
  final ValueChanged<_PointFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _filterChip('All', _PointFilter.all),
        _filterChip('Assigned', _PointFilter.assigned),
        _filterChip('Unassigned', _PointFilter.unassigned),
        _filterChip('Serviced', _PointFilter.serviced),
      ],
    );
  }

  Widget _filterChip(String label, _PointFilter value) {
    final selected = filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onChanged(value),
      selectedColor: SupervisorTheme.accentSoft,
      labelStyle: TextStyle(
        color: selected ? SupervisorTheme.accent : SupervisorTheme.strongText,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: selected
            ? SupervisorTheme.accent.withValues(alpha: 0.3)
            : SupervisorTheme.cardBorder,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    );
  }
}

class _PaginationRow extends StatelessWidget {
  const _PaginationRow({
    required this.start,
    required this.end,
    required this.total,
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int start;
  final int end;
  final int total;
  final int page;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '${start + 1}-$end of $total',
          style: const TextStyle(
            color: SupervisorTheme.mutedText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          'Page ${page + 1} / $pageCount',
          style: const TextStyle(
            color: SupervisorTheme.mutedText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _CollectionPointCard extends StatelessWidget {
  const _CollectionPointCard({
    required this.item,
    required this.onViewStatus,
    this.onShowQr,
  });

  final SupervisorCollectionPoint item;
  final VoidCallback onViewStatus;
  final VoidCallback? onShowQr;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        item.isActive ? SupervisorTheme.success : SupervisorTheme.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SupervisorTheme.hairline),
        boxShadow: SupervisorTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText,
                  ),
                ),
              ),
              if (onShowQr != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onShowQr,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: SupervisorTheme.cardBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.qr_code_rounded,
                      size: 18,
                      color: SupervisorTheme.strongText,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.scopeLabel,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: SupervisorTheme.mutedText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${item.latitude}, ${item.longitude}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: SupervisorTheme.mutedText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Bins: ${item.binCount}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: SupervisorTheme.info,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: onViewStatus,
              style: OutlinedButton.styleFrom(
                foregroundColor: SupervisorTheme.strongText,
                side: const BorderSide(color: SupervisorTheme.cardBorder),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'View status',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrDialog extends StatelessWidget {
  const _QrDialog({
    required this.title,
    required this.qrUrl,
    required this.details,
  });

  final String title;
  final String qrUrl;
  final List<_DialogDetail> details;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.84,
      ),
      decoration: const BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: SupervisorTheme.strongText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'QR details',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: SupervisorTheme.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  20 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: Column(
                  children: [
                    Container(
                      width: 190,
                      height: 190,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: SupervisorTheme.cardBorder),
                      ),
                      child: Image.network(
                        qrUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.qr_code_rounded,
                            size: 72,
                            color: SupervisorTheme.mutedText,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final detail in details)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: SupervisorTheme.cardBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                detail.label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: SupervisorTheme.mutedText,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                detail.value,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: SupervisorTheme.strongText,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogDetail {
  const _DialogDetail({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SupervisorInfoCard(
      title: 'Could not load data',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(color: SupervisorTheme.mutedText),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: SupervisorTheme.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SupervisorInfoCard(
      title: 'Nothing here yet',
      child: Text(
        message,
        style: const TextStyle(color: SupervisorTheme.mutedText),
      ),
    );
  }
}

bool _isFailure(String status) {
  final normalized = status.trim().toLowerCase();
  return normalized == 'not available' ||
      normalized == 'skipped' ||
      normalized == 'missed' ||
      normalized == 'not collected';
}

String _resolveMediaUrl(String path) {
  final clean = path.replaceAll('\\', '/');
  if (clean.startsWith('http')) return clean;
  if (clean.startsWith('/')) return '$kOperatorProfileBaseUrl$clean';
  return '$kOperatorProfileBaseUrl/media/$clean';
}
