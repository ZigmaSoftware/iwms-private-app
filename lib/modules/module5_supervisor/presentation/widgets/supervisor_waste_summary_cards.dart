import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/core/env.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_waste_vehicle_sheet.dart';

enum _WasteRange { day, week, month, custom }

class SupervisorWasteSummaryCards extends StatefulWidget {
  const SupervisorWasteSummaryCards({super.key});

  @override
  State<SupervisorWasteSummaryCards> createState() =>
      _SupervisorWasteSummaryCardsState();
}

class _SupervisorWasteSummaryCardsState
    extends State<SupervisorWasteSummaryCards> {
  final SupervisorRepository _repo = getIt<SupervisorRepository>();

  bool _loading = true;
  String? _error;
  List<SupervisorWasteEvent> _events = const [];

  _WasteRange _range = _WasteRange.day;
  DateTime _anchorDate = DateTime.now();
  DateTimeRange? _customRange;

  /// "Others" is collapsed by default: Wet and Dry are the two streams a
  /// supervisor reads at a glance, and everything else is long-tail detail.
  bool _othersExpanded = false;

  /// Tapping the Total card reveals every waste type collected in the window,
  /// bin and household alike — the full breakdown behind the headline number.
  bool _totalExpanded = false;

  static const double _placeholderTargetKg = 10000;

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
      final data = await _repo.fetchWasteEvents();

      if (!mounted) return;

      setState(() {
        _events = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not load waste data';
        _loading = false;
      });
    }
  }

  DateTime _startOfWeek(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day - (date.weekday - 1),
    );
  }

  (DateTime, DateTime) _window() {
    switch (_range) {
      case _WasteRange.day:
        final start = DateTime(
          _anchorDate.year,
          _anchorDate.month,
          _anchorDate.day,
        );

        return (
          start,
          start.add(const Duration(days: 1)),
        );

      case _WasteRange.week:
        final start = _startOfWeek(_anchorDate);

        return (
          start,
          start.add(const Duration(days: 7)),
        );

      case _WasteRange.month:
        final start = DateTime(
          _anchorDate.year,
          _anchorDate.month,
        );

        final end = DateTime(
          _anchorDate.year,
          _anchorDate.month + 1,
        );

        return (start, end);

      case _WasteRange.custom:
        final range = _customRange;

        if (range == null) {
          final start = DateTime(
            _anchorDate.year,
            _anchorDate.month,
            _anchorDate.day,
          );

          return (
            start,
            start.add(const Duration(days: 1)),
          );
        }

        return (
          DateTime(
            range.start.year,
            range.start.month,
            range.start.day,
          ),
          DateTime(
            range.end.year,
            range.end.month,
            range.end.day,
          ).add(const Duration(days: 1)),
        );
    }
  }

  List<SupervisorWasteEvent> _eventsInWindow() {
    final (start, end) = _window();

    return _events.where((event) {
      return !event.date.isBefore(start) && event.date.isBefore(end);
    }).toList();
  }

  /// kg below 1000, tonnes (2dp) at/above — so a normal day/week's real
  /// weight reads as a legible whole-ish kg number instead of "0.32 t".
  String _fmt(double kg) {
    if (kg < 1000) {
      return '${kg.toStringAsFixed(kg == kg.roundToDouble() ? 0 : 1)} kg';
    }
    final tonnes = kg / 1000;
    return '${tonnes.toStringAsFixed(2)} t';
  }

  String _headerLabel() {
    switch (_range) {
      case _WasteRange.day:
        return DateFormat('d MMM yyyy').format(_anchorDate);

      case _WasteRange.week:
        final start = _startOfWeek(_anchorDate);
        final end = start.add(const Duration(days: 6));

        return '${DateFormat('d MMM').format(start)} – '
            '${DateFormat('d MMM').format(end)}';

      case _WasteRange.month:
        return DateFormat('MMMM yyyy').format(_anchorDate);

      case _WasteRange.custom:
        final range = _customRange;

        if (range == null) {
          return DateFormat('d MMM yyyy').format(_anchorDate);
        }

        return '${DateFormat('d MMM').format(range.start)} – '
            '${DateFormat('d MMM').format(range.end)}';
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 6)),
            end: now,
          ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _customRange = picked;
      _range = _WasteRange.custom;
      _anchorDate = picked.end;
    });
  }

  @override
  Widget build(BuildContext context) {
    final events = _eventsInWindow();

    final totalKg = events.fold<double>(0, (sum, e) => sum + e.weightKg);
    final wetKg = events
        .where((e) => e.isWet)
        .fold<double>(0, (sum, e) => sum + e.weightKg);
    final dryKg = events
        .where((e) => e.isDry)
        .fold<double>(0, (sum, e) => sum + e.weightKg);

    final binKg = events
        .where((e) => e.isBin)
        .fold<double>(0, (sum, e) => sum + e.weightKg);
    final householdKg = events
        .where((e) => e.isHousehold)
        .fold<double>(0, (sum, e) => sum + e.weightKg);

    final binPct = totalKg > 0 ? binKg / totalKg : 0.0;
    final householdPct = totalKg > 0 ? householdKg / totalKg : 0.0;

    // Every waste type collected in this window, whatever its source — this
    // is what the Total card expands to show, so nothing that contributed to
    // the headline number is hidden.
    final allTotals = <String, double>{};
    for (final e in events) {
      allTotals[e.displayTypeName] =
          (allTotals[e.displayTypeName] ?? 0) + e.weightKg;
    }
    final allRows = allTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Every stream that is neither Wet nor Dry — Mixed, Sanitary, E-Waste,
    // whatever the project has configured. These are summed into the total
    // but had no card of their own, so their weight was invisible. Rather
    // than adding a third/fourth fixed card (which breaks the 2-up grid as
    // soon as a project adds another type), they collapse into one
    // expandable "Others" row that scales to any number of streams.
    final otherEvents =
        events.where((e) => !e.isWet && !e.isDry).toList(growable: false);

    final otherTotals = <String, double>{};
    for (final e in otherEvents) {
      final label = e.wasteTypeName.trim().isEmpty
          ? 'Unspecified'
          : e.wasteTypeName.trim();
      otherTotals[label] = (otherTotals[label] ?? 0) + e.weightKg;
    }
    final otherRows = otherTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final othersKg = otherTotals.values.fold<double>(0, (sum, v) => sum + v);

    final wetPct = totalKg > 0 ? wetKg / totalKg : 0.0;

    final dryPct = totalKg > 0 ? dryKg / totalKg : 0.0;

    final targetPct =
        (totalKg / _placeholderTargetKg).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dateRangeHeader(),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: CircularProgressIndicator(
                color: SupervisorTheme.accent,
              ),
            ),
          )
        else if (_error != null)
          _errorState()
        else ...[
          _totalCard(
            totalKg,
            targetPct,
          ),
          // Full per-type breakdown behind the headline number, revealed by
          // tapping the Total card above.
          _totalBreakdown(rows: allRows, totalKg: totalKg, events: events),
          const SizedBox(height: 10),
          // Collection-STREAM split (where the waste came from), sitting above
          // the waste-TYPE split below so the two rows read as one grid.
          if (kShowBinHouseholdKpiCards) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _breakdownCard(
                    title: 'Bin Collection',
                    valueKg: binKg,
                    pct: binPct,
                    iconAsset: 'assets/icons/bin2.png',
                    backgroundAsset: 'assets/cards/bin_card2.png',
                    valueColor: const Color(0xFF7C3AED),
                    onTap: () => showSupervisorWasteVehicleSheet(
                      context,
                      title: 'Bin collections',
                      accentColor: const Color(0xFF7C3AED),
                      events: events,
                      matches: (e) => e.isBin,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _breakdownCard(
                    title: 'Households',
                    valueKg: householdKg,
                    pct: householdPct,
                    iconAsset: 'assets/icons/household2.png',
                    backgroundAsset: 'assets/cards/household_card2.png',
                    valueColor: const Color(0xFFF97316),
                    onTap: () => showSupervisorWasteVehicleSheet(
                      context,
                      title: 'Household collections',
                      accentColor: const Color(0xFFF97316),
                      events: events,
                      matches: (e) => e.isHousehold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (kShowWetDryKpiCards)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _breakdownCard(
                    title: 'Wet Waste',
                    valueKg: wetKg,
                    pct: wetPct,
                    iconAsset: 'assets/icons/bin.png',
                    backgroundAsset: 'assets/cards/bin_card.png',
                    // Was purple (0xFF7C3AED) — unrelated to this card's own
                    // mint/teal-green artwork (bin_card.png). Deep teal instead,
                    // pulled from that same background's hue family so the
                    // label reads as part of the card rather than a clashing
                    // accent color.
                    valueColor: const Color(0xFF0F7A5C),
                    onTap: () => showSupervisorWasteVehicleSheet(
                      context,
                      title: 'Wet Waste collections',
                      accentColor: const Color(0xFF0F7A5C),
                      events: events,
                      matches: (e) => e.isWet,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _breakdownCard(
                    title: 'Dry Waste',
                    valueKg: dryKg,
                    pct: dryPct,
                    iconAsset: 'assets/icons/household.png',
                    backgroundAsset: 'assets/cards/household_card.png',
                    // Was orange (0xFFF97316), then blue — reverted to this
                    // card's own peach/amber hue family (household_card.png)
                    // per request, but deeper/more saturated than the original
                    // orange so it actually contrasts against the pale peach
                    // background instead of blending into it.
                    valueColor: const Color(0xFFB45309),
                    onTap: () => showSupervisorWasteVehicleSheet(
                      context,
                      title: 'Dry Waste collections',
                      accentColor: const Color(0xFFB45309),
                      events: events,
                      matches: (e) => e.isDry,
                    ),
                  ),
                ),
              ],
            ),
          if (otherRows.isNotEmpty) ...[
            const SizedBox(height: 10),
            _othersSection(
              rows: otherRows,
              othersKg: othersKg,
              totalKg: totalKg,
              events: events,
            ),
          ],
        ],
      ],
    );
  }

  /// Collapsible summary of every non-Wet/Dry stream.
  ///
  /// Header always shows the combined weight so the number is visible without
  /// expanding; tapping reveals one row per waste type, each of which opens
  /// the same vehicle sheet the Wet/Dry cards use.
  Widget _othersSection({
    required List<MapEntry<String, double>> rows,
    required double othersKg,
    required double totalKg,
    required List<SupervisorWasteEvent> events,
  }) {
    const accent = Color(0xFF5B6472);
    final pct = totalKg > 0 ? othersKg / totalKg : 0.0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: SupervisorTheme.hairline.withValues(alpha: 0.5),
        ),
        boxShadow: SupervisorTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _othersExpanded = !_othersExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.category_rounded,
                      size: 18,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Others (${rows.length})',
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_fmt(othersKg)}  ·  ${(pct * 100).round()}% of total',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            color: SupervisorTheme.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _othersExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: SupervisorTheme.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _othersExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              children: [
                for (final row in rows)
                  _otherRow(
                    label: row.key,
                    valueKg: row.value,
                    totalKg: totalKg,
                    accent: accent,
                    events: events,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One waste-type row. Shared by the Total card's full breakdown and the
  /// "Others" section — [matches] is what differs: the former selects every
  /// event of that type, the latter only the non-Wet/Dry ones.
  Widget _otherRow({
    required String label,
    required double valueKg,
    required double totalKg,
    required Color accent,
    required List<SupervisorWasteEvent> events,
    bool Function(SupervisorWasteEvent)? matches,
  }) {
    final pct = totalKg > 0 ? valueKg / totalKg : 0.0;
    final key = label.toLowerCase();

    return InkWell(
      onTap: () => showSupervisorWasteVehicleSheet(
        context,
        title: '$label collections',
        accentColor: accent,
        events: events,
        matches: matches ??
            (e) {
              if (e.isWet || e.isDry) return false;
              final name = e.wasteTypeName.trim();
              return (name.isEmpty ? 'unspecified' : name.toLowerCase()) == key;
            },
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0x11000000)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: SupervisorTheme.strongText,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _fmt(valueKg),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                color: SupervisorTheme.strongText,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 42,
              child: Text(
                '${(pct * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: SupervisorTheme.mutedText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Text(
              _error!,
              style: const TextStyle(
                color: SupervisorTheme.mutedText,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateRangeHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: SupervisorTheme.hairline.withValues(alpha: 0.5),
        ),
        boxShadow: SupervisorTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: SupervisorTheme.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: SupervisorTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _headerLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: SupervisorTheme.strongText,
                      ),
                    ),
                    if (_range == _WasteRange.day)
                      Text(
                        DateFormat('EEEE').format(_anchorDate),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: SupervisorTheme.mutedText,
                        ),
                      ),
                  ],
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickCustomRange,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: SupervisorTheme.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.edit_calendar_rounded,
                    color: SupervisorTheme.accent,
                    size: 19,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _rangePill(
                'Day',
                _WasteRange.day,
              ),
              const SizedBox(width: 8),
              _rangePill(
                'Week',
                _WasteRange.week,
              ),
              const SizedBox(width: 8),
              _rangePill(
                'Month',
                _WasteRange.month,
              ),
              const SizedBox(width: 8),
              _rangePill(
                'Custom',
                _WasteRange.custom,
                onCustomTap: _pickCustomRange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rangePill(
    String label,
    _WasteRange range, {
    VoidCallback? onCustomTap,
  }) {
    final selected = _range == range;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          if (range == _WasteRange.custom) {
            onCustomTap?.call();
            return;
          }

          setState(() {
            _range = range;
            _anchorDate = DateTime.now();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? SupervisorTheme.primary
                : SupervisorTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : SupervisorTheme.strongText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _totalCard(
    double totalKg,
    double targetPct,
  ) {
    // Matches the empty background colour inside total_waste.png.
    const cardBackground = Color(0xFFEBF0FE);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _totalExpanded = !_totalExpanded),
        child: Container(
          height: 112,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cardBackground,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFD9E4FB),
            ),
            boxShadow: SupervisorTheme.softShadow,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  /*
               * Illustration
               *
               * The image background and card background use the same
               * #EBF0FE colour, so the image edges are camouflaged.
               *
               * BoxFit.contain prevents cropping.
               * Transform.scale enlarges it slightly without creating a
               * smaller invisible clipping container.
               */
                  Positioned(
                    left: constraints.maxWidth * 0.20,
                    right: 82,
                    top: 13,
                    bottom: 0,
                    child: ColoredBox(
                      color: cardBackground,
                      child: Transform.scale(
                        scale: 1.20,
                        alignment: Alignment.bottomCenter,
                        child: Image.asset(
                          'assets/cards/total_waste.png',
                          fit: BoxFit.contain,
                          alignment: Alignment.bottomCenter,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 15,
                    top: 14,
                    right: 78,
                    child: Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Total Waste Collected',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              color: SupervisorTheme.strongText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        _liveBadge(),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 15,
                    top: 58,
                    child: Text(
                      _fmt(totalKg),
                      style: const TextStyle(
                        fontSize: 30,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: SupervisorTheme.info,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: 21,
                    child: _targetRing(targetPct),
                  ),
                  // Disclosure affordance for the per-type breakdown — a bare
                  // chevron, no label: the whole card is the tap target.
                  Positioned(
                    left: 15,
                    bottom: 8,
                    child: AnimatedRotation(
                      turns: _totalExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: SupervisorTheme.info,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Per-waste-type breakdown revealed by tapping the Total card.
  ///
  /// Covers BOTH streams, so the rows always add up to the headline total —
  /// bin-side types come through dynamically from the API, household-side
  /// ones from its fixed wet/dry/mixed/sanitary buckets.
  Widget _totalBreakdown({
    required List<MapEntry<String, double>> rows,
    required double totalKg,
    required List<SupervisorWasteEvent> events,
  }) {
    const accent = SupervisorTheme.info;

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 180),
      crossFadeState:
          _totalExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      firstChild: const SizedBox(width: double.infinity),
      secondChild: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: SupervisorTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: SupervisorTheme.hairline.withValues(alpha: 0.5),
            ),
            boxShadow: SupervisorTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 2),
                child: Text(
                  'Collected by waste type',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 14),
                  child: Text(
                    'Nothing collected in this period.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: SupervisorTheme.mutedText,
                    ),
                  ),
                )
              else
                for (final row in rows)
                  _otherRow(
                    label: row.key,
                    valueKg: row.value,
                    totalKg: totalKg,
                    accent: accent,
                    events: events,
                    matches: (e) => e.displayTypeName == row.key,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: SupervisorTheme.info,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'Live',
            style: TextStyle(
              fontSize: 10.5,
              height: 1,
              fontWeight: FontWeight.w800,
              color: SupervisorTheme.info,
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetRing(double targetPct) {
    return SizedBox(
      width: 68,
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 68,
            height: 68,
            child: CircularProgressIndicator(
              value: targetPct,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: SupervisorTheme.info.withValues(alpha: 0.14),
              valueColor: const AlwaysStoppedAnimation<Color>(
                SupervisorTheme.info,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(targetPct * 100).round()}%',
                style: const TextStyle(
                  fontSize: 14,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: SupervisorTheme.strongText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'of ${(_placeholderTargetKg / 1000).toStringAsFixed(0)} t',
                style: const TextStyle(
                  fontSize: 8.5,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: SupervisorTheme.mutedText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _breakdownCard({
    required String title,
    required double valueKg,
    required double pct,
    required String iconAsset,
    required String backgroundAsset,
    required Color valueColor,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 122,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: valueColor.withValues(alpha: 0.10),
            ),
            boxShadow: SupervisorTheme.softShadow,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                backgroundAsset,
                fit: BoxFit.cover,
                alignment: Alignment.bottomRight,
                filterQuality: FilterQuality.high,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [
                      0.0,
                      0.48,
                      0.76,
                      1.0,
                    ],
                    colors: [
                      Colors.white.withValues(alpha: 0.28),
                      Colors.white.withValues(alpha: 0.10),
                      Colors.transparent,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  11,
                  10,
                  8,
                  9,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          iconAsset,
                          width: 30,
                          height: 30,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              color: valueColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _fmt(valueKg),
                      style: const TextStyle(
                        fontSize: 25,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        color: SupervisorTheme.strongText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(pct * 100).round()}% of total',
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: SupervisorTheme.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
