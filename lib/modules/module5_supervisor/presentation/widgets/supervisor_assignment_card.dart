import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:iwms_private_app/data/models/operator_trip_models.dart'
    show OperatorTripCrew, OperatorTripCrewMember;
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_crew_detail_sheet.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_trip_alerts_sheet.dart';

/// Card representing one daily trip assignment in the supervisor's zones.
///
/// "Midnight Stack" (variant 01 in the trip-card variants artifact): status
/// and time, route, one big progress figure with a bar, a quiet crew line,
/// one primary action plus a ⋯ menu, and a single alerts row along the
/// bottom that opens [SupervisorTripAlertsSheet]. A completed trip collapses
/// to one row unless [historical].
class SupervisorAssignmentCard extends StatelessWidget {
  const SupervisorAssignmentCard({
    super.key,
    required this.assignment,
    this.onTap,
    this.onNavigate,
    this.onActions,
    this.serverNow,
    this.historical = false,
    this.onNoCollection,
    this.onAlertHandled,
  });

  final SupervisorAssignment assignment;

  /// Opens the trip details; also the "View trip" primary action.
  final VoidCallback? onTap;

  /// When provided for a running trip, the primary action becomes
  /// "Track vehicle" (the driver's live route map).
  final VoidCallback? onNavigate;

  /// Opens the trip actions sheet (substitute staff, approve, cancel…),
  /// listed in the ⋯ menu and used by "Assign" / "Resolve" alerts.
  final VoidCallback? onActions;

  /// Server wall clock; alerts are only shown when this is provided.
  final DateTime? serverNow;
  final bool historical;
  final VoidCallback? onNoCollection;

  /// Refreshes the host after a review screen opened from the alerts sheet
  /// (breakdown, delay, Re-Trip) returns.
  final VoidCallback? onAlertHandled;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final status = _status();
    if (a.isCompleted && !historical) {
      return _CompletedRow(
        title: _title,
        waste: _waste,
        summary: [
          if (a.stops.isNotEmpty) '${a.collectedCount}/${a.stops.length}',
          if (a.totalCollectedWeightKg > 0) _kg(a.totalCollectedWeightKg),
          if ((a.totalTripTimeSeconds ?? 0) > 0)
            _duration(a.totalTripTimeSeconds!),
        ].join(' · '),
        onTap: onTap,
      );
    }
    final alerts = serverNow == null || historical
        ? const <SupervisorTripAlert>[]
        : a.alerts(serverNow!);
    final primary = _primary();
    final menu = _menu();
    return _MidnightShell(
      onTap: onTap,
      footer: alerts.isEmpty
          ? null
          : _AlertsFooter(
              alerts: alerts,
              onTap: () => SupervisorTripAlertsSheet.show(
                context,
                title: _title,
                subtitle: '$_waste · ${status.label}',
                alerts: alerts,
                onOpenTrip: onTap,
                onTripActions: a.isRemaining ? onActions : null,
                onChanged: onAlertHandled,
              ),
            ),
      children: [
        _StatusRow(status: status, time: _timeText(), timeIcon: _timeIcon),
        _RouteTitle(title: _title, waste: _waste),
        if (a.stops.isNotEmpty) _progress(status.tone),
        _crewRow(context),
        if (historical)
          _MetaLine(
            icon: Icons.receipt_long_rounded,
            text: a.tripLogSummary.isEmpty
                ? 'No collection log recorded'
                : 'Collection log: ${a.tripLogSummary['status'] ?? 'Unverified'}',
          ),
        if (primary != null || menu.isNotEmpty)
          _ActionsRow(primary: primary, menu: menu),
      ],
    );
  }

  // ── Content ──────────────────────────────────────────────────────────

  /// "Ward B" when the trip has a ward; otherwise the area name as is.
  String get _title {
    final name = assignment.areaName.trim();
    if (!assignment.areaIsWard || name.toLowerCase().startsWith('ward')) {
      return name;
    }
    return 'Ward $name';
  }

  String get _waste => assignment.wasteTypeName.isNotEmpty
      ? _sentenceCase(assignment.wasteTypeName)
      : _sentenceCase(assignment.collectionTypeLabel);

  _RouteStatus _status() {
    final a = assignment;
    if (a.isCancelled) {
      return const _RouteStatus(
          'Cancelled', Icons.cancel_rounded, _Tone.danger);
    }
    if (a.isCompleted) {
      return const _RouteStatus(
          'Completed', Icons.check_circle_rounded, _Tone.ok);
    }
    if (a.awaitingClosure) {
      return const _RouteStatus(
          'Awaiting closure', Icons.pending_actions_rounded, _Tone.ok);
    }
    if (a.isInProgress) {
      return const _RouteStatus(
          'In progress', Icons.route_rounded, _Tone.accent);
    }
    if (a.isScheduled) {
      return const _RouteStatus(
          'Scheduled', Icons.schedule_rounded, _Tone.info);
    }
    return _RouteStatus(a.statusLabel, Icons.info_rounded, _Tone.neutral);
  }

  IconData get _timeIcon => assignment.isScheduled
      ? Icons.hourglass_top_rounded
      : Icons.schedule_rounded;

  /// One time fact for the state, prefixed with the date only when the trip
  /// is not today's and with "Trip 2" for a Re-Trip continuation.
  String _timeText() {
    final a = assignment;
    final scheduled = _hhmm(a.scheduledTime);
    final started = a.actualStartTime.isNotEmpty
        ? _hhmm(a.actualStartTime)
        : a.actualStartAt == null
            ? ''
            : DateFormat('HH:mm').format(a.actualStartAt!.toLocal());
    final String core;
    if (a.isCancelled) {
      core = scheduled.isEmpty ? '' : 'Was due $scheduled';
    } else if (a.isCompleted) {
      final secs = a.totalTripTimeSeconds ?? 0;
      core = secs > 0 ? 'Completed in ${_duration(secs)}' : '';
    } else if (a.isInProgress) {
      core = started.isEmpty ? '' : 'Started $started';
    } else if (a.isScheduled) {
      core = scheduled.isEmpty
          ? 'Waiting for driver to start'
          : 'Waiting for driver to start · $scheduled';
    } else {
      core = scheduled;
    }
    final now = serverNow ?? DateTime.now();
    final date = a.tripDate;
    final notToday = !historical &&
        date != null &&
        (date.year != now.year ||
            date.month != now.month ||
            date.day != now.day);
    return [
      if (notToday) DateFormat('d MMM').format(date),
      if (a.tripCount > 1) 'Trip ${a.tripCount}',
      if (core.isNotEmpty) core,
    ].join(' · ');
  }

  Widget _progress(_Tone tone) {
    final a = assignment;
    final total = a.stops.length;
    final closing = a.awaitingClosure;
    final done = closing ? total - a.unresolvedCount : a.collectedCount;
    final noun = closing
        ? 'resolved'
        : a.hasHousehold && !a.hasBin
            ? 'households'
            : a.hasBin && !a.hasHousehold
                ? 'bins'
                : 'stops';
    final kg = a.totalCollectedWeightKg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '$done',
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w700, height: 1.1),
                  ),
                  TextSpan(
                    text: ' of $total $noun',
                    style: const TextStyle(fontSize: 14, color: _Palette.muted),
                  ),
                ]),
                style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
            if (kg > 0) ...[
              const SizedBox(width: 10),
              const Icon(Icons.scale_rounded, size: 16, color: _Palette.muted),
              const SizedBox(width: 4),
              Text(
                _kg(kg),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        _Bar(fraction: total == 0 ? 0 : done / total, color: tone.solid),
      ],
    );
  }

  Widget _crewRow(BuildContext context) {
    final a = assignment;
    final staffName = a.driverName.isNotEmpty ? a.driverName : a.operatorName;
    final crew = a.crew;
    final hasCrew = !historical &&
        crew != null &&
        (crew.driver != null ||
            crew.operator != null ||
            crew.extraOperators.isNotEmpty);
    final missed = a.unavailableCount;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: hasCrew
                ? () => SupervisorCrewDetailSheet.show(context, crew)
                : null,
            child: _CrewLine(
              icon: Icons.person_rounded,
              lead: staffName.isEmpty
                  ? 'No driver assigned'
                  : _titleCase(staffName),
              vehicleNo: a.vehicleNo,
            ),
          ),
        ),
        if (missed > 0) ...[
          const SizedBox(width: 10),
          const Icon(Icons.person_off_rounded,
              size: 16, color: _Palette.warnInk),
          const SizedBox(width: 4),
          Text('$missed unavailable',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _Palette.warnInk)),
        ],
      ],
    );
  }

  _Action? _primary() {
    final a = assignment;
    if (historical) {
      return onTap == null
          ? null
          : _Action(Icons.receipt_long_rounded, 'View trip summary', onTap!);
    }
    if (a.isInProgress && !a.awaitingClosure && onNavigate != null) {
      return _Action(Icons.my_location_rounded, 'Track vehicle', onNavigate!);
    }
    if (onTap == null) return null;
    return _Action(
        a.awaitingClosure
            ? Icons.arrow_forward_rounded
            : Icons.visibility_rounded,
        'View trip',
        onTap!);
  }

  List<_Action> _menu() {
    if (historical) return const [];
    final primaryIsDetails = _primary()?.label == 'View trip';
    return [
      if (onTap != null && !primaryIsDetails)
        _Action(Icons.info_outline_rounded, 'Trip details', onTap!),
      if (onActions != null && assignment.isRemaining)
        _Action(Icons.tune_rounded, 'Trip actions', onActions!),
      if (onNoCollection != null)
        _Action(
            Icons.event_busy_rounded, 'No collection today', onNoCollection!),
    ];
  }
}

/// Card for a Trip Plan that has no assignment yet today, or that cannot run:
/// needs assignment, blocked, not scheduled, or no collection today.
class SupervisorPlanCard extends StatelessWidget {
  const SupervisorPlanCard({
    super.key,
    required this.plan,
    this.enabled = true,
    this.onAssign,
    this.onNoCollection,
    this.onRestoreService,
  });

  final SupervisorPlanOption plan;
  final bool enabled;
  final VoidCallback? onAssign;
  final VoidCallback? onNoCollection;
  final VoidCallback? onRestoreService;

  @override
  Widget build(BuildContext context) {
    if (plan.noCollection) {
      final notice = plan.notice;
      return _SuspendedCard(
        title: plan.areaName,
        waste: plan.collectionLabel,
        reason: notice?.explanation ?? 'Service is suspended today',
        reasonIcon: _reasonIcon(notice?.reasonCode ?? ''),
        notified: notice == null
            ? null
            : '${notice.staffRecipientCount} staff · '
                '${notice.customerRecipientCount} households notified',
        menu: [
          if (onRestoreService != null && enabled)
            _Action(Icons.restart_alt_rounded, 'Restore service',
                onRestoreService!),
        ],
      );
    }
    final status = plan.needsAssignment
        ? const _RouteStatus(
            'Needs assignment', Icons.person_add_rounded, _Tone.warn)
        : plan.state == 'NOT_SCHEDULED'
            ? const _RouteStatus(
                'Not scheduled today', Icons.event_busy_rounded, _Tone.neutral)
            : plan.state == 'BLOCKED'
                ? const _RouteStatus(
                    'Needs setup', Icons.build_rounded, _Tone.warn)
                : _RouteStatus(_sentenceCase(plan.state.replaceAll('_', ' ')),
                    Icons.info_rounded, _Tone.neutral);
    final time = _hhmm(plan.scheduledTime);
    final menu = [
      if (plan.canDeclareNoCollection && onNoCollection != null && enabled)
        _Action(
            Icons.event_busy_rounded, 'No collection today', onNoCollection!),
    ];
    final primary = plan.needsAssignment && onAssign != null
        ? _Action(Icons.person_add_rounded, 'Assign trip', onAssign!,
            enabled: enabled)
        : null;
    return _MidnightShell(
      children: [
        _StatusRow(
          status: status,
          time: time.isEmpty ? '' : 'Starts $time',
          timeIcon: Icons.schedule_rounded,
        ),
        _RouteTitle(title: plan.areaName, waste: plan.collectionLabel),
        _TeamLine(plan: plan),
        if (plan.blocked && (plan.blockingReason ?? '').isNotEmpty)
          _MetaLine(
            icon: Icons.error_rounded,
            text: plan.blockingReason!,
            color: _Palette.warnInk,
          ),
        if (primary != null || menu.isNotEmpty)
          _ActionsRow(primary: primary, menu: menu),
      ],
    );
  }

  static IconData _reasonIcon(String code) => switch (code) {
        'WEATHER' => Icons.thunderstorm_rounded,
        'FLOOD' => Icons.flood_rounded,
        'HOLIDAY' => Icons.celebration_rounded,
        'STAFF_UNAVAILABLE' => Icons.person_off_rounded,
        'VEHICLE_TECHNICAL' => Icons.build_rounded,
        'SAFETY' => Icons.health_and_safety_rounded,
        _ => Icons.info_rounded,
      };
}

/// "Today · 4 routes            ⓘ 1 needs attention" above the stacked cards.
class SupervisorRoutesSummary extends StatelessWidget {
  const SupervisorRoutesSummary({
    super.key,
    required this.routes,
    required this.needsAttention,
  });

  final int routes;
  final int needsAttention;

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFF63615C);
    const danger = Color(0xFFB42323);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.today_rounded, size: 18, color: muted),
            const SizedBox(width: 6),
            Text.rich(
              TextSpan(children: [
                const TextSpan(
                    text: 'Today',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' · $routes routes'),
              ]),
              style: const TextStyle(fontSize: 14, color: Color(0xFF070707)),
            ),
          ]),
          if (needsAttention > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_rounded, size: 16, color: danger),
              const SizedBox(width: 4),
              Text('$needsAttention needs attention',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: danger)),
            ]),
        ],
      ),
    );
  }
}

// ── Palette ────────────────────────────────────────────────────────────

class _Palette {
  static const fg = Colors.white;
  static const muted = Color(0xFFBCBEDC);
  static const line = Color(0x21FFFFFF); // white 13%
  static const track = Color(0x29FFFFFF); // white 16%
  static const chip = Color(0x1AFFFFFF); // white 10%
  static const warnInk = Color(0xFFF6D089);
  static const onWhite = Color(0xFF2722B9);
  static const radius = BorderRadius.all(Radius.circular(20));
  static const shadow = [
    BoxShadow(color: Color(0x470E1023), blurRadius: 10, offset: Offset(0, 2)),
  ];
}

/// Status colours on the dark card: [ink] for text, [solid] for bars and
/// dots, [soft] for pill and badge fills.
enum _Tone {
  accent(Color(0xFFCBC8FF), Color(0xFF8F8AFF), Color(0x388F8AFF)),
  ok(Color(0xFF86E3BE), Color(0xFF3CC48F), Color(0x2E3CC48F)),
  warn(Color(0xFFF6D089), Color(0xFFE8AE3C), Color(0x2EE8AE3C)),
  info(Color(0xFFB3CAFF), Color(0xFF6E9BFF), Color(0x336E9BFF)),
  danger(Color(0xFFFFB0B0), Color(0xFFF06363), Color(0x38F06363)),
  neutral(Color(0xFFD5D6EA), Color(0xFF9C9EBC), Color(0x1AFFFFFF));

  const _Tone(this.ink, this.solid, this.soft);
  final Color ink;
  final Color solid;
  final Color soft;

  static _Tone ofSeverity(TripAlertSeverity s) => switch (s) {
        TripAlertSeverity.critical => danger,
        TripAlertSeverity.warning => warn,
        TripAlertSeverity.info => neutral,
      };
}

class _RouteStatus {
  const _RouteStatus(this.label, this.icon, this.tone);
  final String label;
  final IconData icon;
  final _Tone tone;
}

class _Action {
  const _Action(this.icon, this.label, this.onPressed, {this.enabled = true});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
}

// ── Building blocks ────────────────────────────────────────────────────

class _MidnightShell extends StatelessWidget {
  const _MidnightShell({required this.children, this.footer, this.onTap});

  final List<Widget> children;
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: _Palette.radius,
        boxShadow: _Palette.shadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: _Palette.radius,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topLeft,
              radius: 1.4,
              colors: [Color(0xFF2E3285), Color(0xFF161838), Color(0xFF0E1023)],
              stops: [0, .58, 1],
            ),
          ),
          child: DefaultTextStyle.merge(
            style:
                const TextStyle(color: _Palette.fg, fontSize: 14, height: 1.35),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < children.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          children[i],
                        ],
                      ],
                    ),
                  ),
                ),
                if (footer != null) footer!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
    required this.time,
    required this.timeIcon,
  });

  final _RouteStatus status;
  final String time;
  final IconData timeIcon;

  @override
  Widget build(BuildContext context) {
    // Pill left, time right; at large text sizes the time drops to its own
    // line instead of squeezing the pill.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        _Pill(status: status),
        if (time.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(timeIcon, size: 16, color: _Palette.muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  time,
                  style: const TextStyle(fontSize: 12, color: _Palette.muted),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.status});

  final _RouteStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.fromLTRB(7, 2, 10, 2),
      decoration: BoxDecoration(
        color: status.tone.soft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 16, color: status.tone.ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status.label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: status.tone.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteTitle extends StatelessWidget {
  const _RouteTitle(
      {required this.title, required this.waste, this.muted = false});

  final String title;
  final String waste;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: title),
        if (waste.isNotEmpty)
          TextSpan(
              text: ' · $waste',
              style: const TextStyle(fontWeight: FontWeight.w500)),
      ]),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: muted ? 16 : 18,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: muted ? _Palette.muted : _Palette.fg,
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 8,
        color: _Palette.track,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(99)),
          ),
        ),
      ),
    );
  }
}

/// "👤 Ashish Kasana · [UP 16 KT 1912]" — quiet, wraps as one sentence.
class _CrewLine extends StatelessWidget {
  const _CrewLine({
    required this.icon,
    required this.lead,
    required this.vehicleNo,
    this.leadStyle,
  });

  final IconData? icon;
  final String lead;
  final String vehicleNo;
  final TextStyle? leadStyle;

  static final _plate = RegExp(r'^([A-Z]{2})(\d{1,2})([A-Z]{1,3})(\d{1,4})$');

  @override
  Widget build(BuildContext context) {
    final raw = vehicleNo.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    final m = _plate.firstMatch(raw);
    final plate = m == null ? vehicleNo : '${m[1]} ${m[2]} ${m[3]} ${m[4]}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: _Palette.muted),
          ),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: lead, style: leadStyle),
              if (plate.isNotEmpty) ...[
                const TextSpan(text: '  ·  '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: _Palette.line),
                    ),
                    child: Text(
                      plate,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: .36,
                        color: _Palette.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ]),
            style: const TextStyle(fontSize: 12, color: _Palette.muted),
          ),
        ),
      ],
    );
  }
}

/// "Team: (●●●) ASHI‑CHRE‑01 · [UP 16 KT 1912]" — the plan team's faces,
/// its code, and the vehicle. Tapping the faces opens the crew sheet.
class _TeamLine extends StatelessWidget {
  const _TeamLine({required this.plan});

  final SupervisorPlanOption plan;

  @override
  Widget build(BuildContext context) {
    final members = plan.teamMembers;
    final assigned = plan.teamCode != 'Team not assigned';
    // Older backends send names without the members list.
    final faces = members.isNotEmpty
        ? [
            for (final m in members)
              (initials: m.initials, photoUrl: m.photoUrl, name: m.displayName)
          ]
        : [
            for (final n in [plan.driverName, plan.operatorName])
              if (n.isNotEmpty)
                (initials: _initials(n), photoUrl: null, name: _titleCase(n))
          ];
    final vehicle =
        plan.vehicleNo == 'Vehicle not assigned' ? '' : plan.vehicleNo;
    final crew = _crew(members);
    return Semantics(
      label: assigned
          ? 'Team ${plan.teamCode}: ${faces.map((f) => f.name).join(', ')}'
          : 'No team assigned',
      child: Row(
        children: [
          const Text('Team:',
              style: TextStyle(fontSize: 12, color: _Palette.muted)),
          const SizedBox(width: 8),
          if (assigned && faces.isNotEmpty) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: crew == null
                  ? null
                  : () => SupervisorCrewDetailSheet.show(context, crew),
              child: _AvatarStack(faces: faces),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: _CrewLine(
              icon: null,
              lead: assigned
                  // Non-breaking hyphens keep "ASHI-CHRE-01" whole.
                  ? plan.teamCode.replaceAll('-', '\u2011')
                  : 'Not assigned',
              vehicleNo: vehicle,
              leadStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _Palette.fg),
            ),
          ),
        ],
      ),
    );
  }

  static OperatorTripCrew? _crew(List<OperatorTripCrewMember> members) {
    if (members.isEmpty) return null;
    bool isDriver(OperatorTripCrewMember m) =>
        (m.role ?? '').toLowerCase().contains('driver');
    final driver = members.where(isDriver).firstOrNull;
    final others = members.where((m) => !isDriver(m)).toList();
    return OperatorTripCrew(
      driver: driver,
      operator: others.firstOrNull,
      extraOperators: others.skip(1).toList(),
    );
  }

  static String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

/// Overlapping 26px face circles; at most three, then "+N".
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.faces});

  final List<({String initials, String? photoUrl, String name})> faces;

  static const _size = 26.0;
  static const _step = 18.0; // 8px overlap
  static const _ring = Color(0xFF1A1C44); // the card behind the avatars

  @override
  Widget build(BuildContext context) {
    final shown = faces.take(faces.length > 3 ? 2 : 3).toList();
    final extra = faces.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      width: _size + _step * (count - 1),
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(left: _step * i, child: _face(shown[i])),
          if (extra > 0)
            Positioned(
              left: _step * shown.length,
              child: _circle(
                color: _Palette.chip,
                child: Text('+$extra',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _Palette.fg)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _face(({String initials, String? photoUrl, String name}) f) {
    final initials = Text(f.initials,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: _Tone.accent.ink));
    final url = f.photoUrl;
    return _circle(
      color: const Color(0xFF2E3285),
      child: url == null || url.isEmpty
          ? initials
          : Image.network(
              url,
              width: _size,
              height: _size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => initials,
            ),
    );
  }

  Widget _circle({required Color color, required Widget child}) => Container(
        width: _size,
        height: _size,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: _ring, width: 2),
        ),
        child: child,
      );
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? _Palette.muted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: color == null ? FontWeight.w400 : FontWeight.w500,
                  color: c)),
        ),
      ],
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.primary, required this.menu});

  final _Action? primary;
  final List<_Action> menu;

  @override
  Widget build(BuildContext context) {
    final p = primary;
    return Row(
      children: [
        if (p != null)
          Expanded(
            child: FilledButton(
              onPressed: p.enabled ? p.onPressed : null,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _Palette.onWhite,
                disabledBackgroundColor: const Color(0x99FFFFFF),
                minimumSize: const Size.fromHeight(44),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(p.icon, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(p.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          )
        else
          const Spacer(),
        if (menu.isNotEmpty) ...[
          const SizedBox(width: 8),
          _MoreButton(items: menu),
        ],
      ],
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.items});

  final List<_Action> items;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(
          topLeft.dx, topLeft.dy + box.size.height + 6, box.size.width, 0),
      Offset.zero & overlay.size,
    );
    final picked = await showMenu<int>(
      context: context,
      position: position,
      color: const Color(0xFFFBFAF7),
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 200),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 44,
            child: Row(children: [
              Icon(items[i].icon, size: 20, color: const Color(0xFF63615C)),
              const SizedBox(width: 10),
              Flexible(
                child: Text(items[i].label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF070707))),
              ),
            ]),
          ),
      ],
    );
    if (picked != null) items[picked].onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: 'More actions',
        onPressed: () => _open(context),
        style: IconButton.styleFrom(
          backgroundColor: _Palette.chip,
          foregroundColor: _Palette.fg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.more_horiz_rounded, size: 20),
      ),
    );
  }
}

/// The single alerts row along the card's bottom edge. Its colour follows
/// the most severe alert, and its label names that alert so one breakdown
/// is never drowned out by 47 customers waiting.
class _AlertsFooter extends StatelessWidget {
  const _AlertsFooter({required this.alerts, required this.onTap});

  final List<SupervisorTripAlert> alerts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = alerts.fold<int>(0, (n, a) => n + a.count);
    final top = alerts.first; // sorted most severe first
    final severity = top.severity;
    final tone = _Tone.ofSeverity(severity);
    final ink = severity == TripAlertSeverity.info ? _Palette.muted : tone.ink;
    final label = severity == TripAlertSeverity.info
        ? 'For your info'
        : count > 1
            ? '${top.short} · +${count - 1} more'
            : top.short;
    final icon = switch (severity) {
      TripAlertSeverity.critical => Icons.error_rounded,
      TripAlertSeverity.warning => Icons.warning_rounded,
      TripAlertSeverity.info => Icons.notifications_rounded,
    };
    return Semantics(
      button: true,
      label: '$count ${count == 1 ? 'alert' : 'alerts'}, $label. Open alerts',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: tone.soft,
            border: const Border(top: BorderSide(color: _Palette.line)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: ink)),
                  ),
                  const SizedBox(width: 10),
                  Text('$count ${count == 1 ? 'alert' : 'alerts'}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ink,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18, color: ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A finished route collapsed to one tappable row.
class _CompletedRow extends StatelessWidget {
  const _CompletedRow({
    required this.title,
    required this.waste,
    required this.summary,
    this.onTap,
  });

  final String title;
  final String waste;
  final String summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const tone = _Tone.ok;
    return Container(
      decoration: const BoxDecoration(
          borderRadius: _Palette.radius, boxShadow: _Palette.shadow),
      child: Material(
        color: const Color(0xFF1B1D3D),
        borderRadius: _Palette.radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: tone.soft,
                      borderRadius: BorderRadius.circular(11.5)),
                  child: Icon(Icons.check_circle_rounded,
                      size: 20, color: tone.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: title),
                          if (waste.isNotEmpty)
                            TextSpan(
                                text: ' · $waste',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _Palette.fg),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: 'Completed',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: tone.ink)),
                          if (summary.isNotEmpty) TextSpan(text: ' · $summary'),
                        ]),
                        style: const TextStyle(
                            fontSize: 12,
                            color: _Palette.muted,
                            fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: _Palette.muted),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// "No collection today": muted, no progress, reason and who was told.
class _SuspendedCard extends StatelessWidget {
  const _SuspendedCard({
    required this.title,
    required this.waste,
    required this.reason,
    required this.reasonIcon,
    required this.notified,
    required this.menu,
  });

  final String title;
  final String waste;
  final String reason;
  final IconData reasonIcon;
  final String? notified;
  final List<_Action> menu;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1D33),
        borderRadius: _Palette.radius,
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: _Palette.fg, height: 1.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.block_rounded, size: 16, color: _Palette.muted),
              const SizedBox(width: 5),
              const Expanded(
                child: Text('No collection today',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _Palette.muted)),
              ),
              if (menu.isNotEmpty) _MoreButton(items: menu),
            ]),
            const SizedBox(height: 8),
            _RouteTitle(title: title, waste: waste, muted: true),
            const SizedBox(height: 8),
            Row(children: [
              Icon(reasonIcon, size: 18, color: _Palette.fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(reason,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ]),
            if (notified != null) ...[
              const SizedBox(height: 8),
              _MetaLine(icon: Icons.campaign_rounded, text: notified!),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────

String _hhmm(String time) => time.length > 5 ? time.substring(0, 5) : time;

final _kgFormat = NumberFormat('#,##0.#', 'en_IN');
String _kg(double kg) => '${_kgFormat.format(kg)} kg';

String _duration(int seconds) {
  final d = Duration(seconds: seconds);
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// "DRY WASTE" / "Dry Waste" → "Dry waste".
String _sentenceCase(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  return '${t[0].toUpperCase()}${t.substring(1).toLowerCase()}';
}

/// "ASHISH KASANA" → "Ashish Kasana"; names arrive in whatever case the
/// admin typed them.
String _titleCase(String s) => s
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
    .join(' ');
