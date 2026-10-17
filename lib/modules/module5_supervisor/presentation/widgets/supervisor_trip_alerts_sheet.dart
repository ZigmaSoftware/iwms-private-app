import 'package:flutter/material.dart';

import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_breakdowns_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_delay_review_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_retrip_requests_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_photo_viewer.dart';

/// Bottom sheet listing every alert on one trip, "Grouped list" layout
/// (sheet 1 in the trip-card variants artifact): "Needs your action" rows
/// carry their own button, and all customers waiting collapse into one
/// expandable row with a scrollable list.
class SupervisorTripAlertsSheet extends StatelessWidget {
  const SupervisorTripAlertsSheet._({
    required this.title,
    required this.subtitle,
    required this.alerts,
    this.onOpenTrip,
    this.onTripActions,
    this.onChanged,
  });

  final String title;
  final String subtitle;
  final List<SupervisorTripAlert> alerts;
  final VoidCallback? onOpenTrip;
  final VoidCallback? onTripActions;

  /// Called after a review screen opened from here returns, so the card can
  /// refresh (a resolved delay or reviewed breakdown drops off the list).
  final VoidCallback? onChanged;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<SupervisorTripAlert> alerts,
    VoidCallback? onOpenTrip,
    VoidCallback? onTripActions,
    VoidCallback? onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SupervisorTripAlertsSheet._(
        title: title,
        subtitle: subtitle,
        alerts: alerts,
        onOpenTrip: onOpenTrip,
        onTripActions: onTripActions,
        onChanged: onChanged,
      ),
    );
  }

  static const _surface = Color(0xFFFBFAF7);
  static const _fg = Color(0xFF070707);
  static const _muted = Color(0xFF63615C);
  static const _hair = Color(0xFFB7B3AA);
  static const _line = Color(0xFFE2DFD8);
  static const _chip = Color(0xFFEDEBE5);

  @override
  Widget build(BuildContext context) {
    final action =
        alerts.where((a) => a.severity != TripAlertSeverity.info).toList();
    final info =
        alerts.where((a) => a.severity == TripAlertSeverity.info).toList();
    final infoCount = info.fold<int>(0, (n, a) => n + a.count);
    final total = alerts.fold<int>(0, (n, a) => n + a.count);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.fromLTRB(0, 12, 0, 6),
              decoration: BoxDecoration(
                  color: _hair, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$title · $total ${total == 1 ? 'alert' : 'alerts'}',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _fg)),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 12, color: _muted)),
                  ],
                ),
              ),
              SizedBox.square(
                dimension: 44,
                child: IconButton(
                  tooltip: 'Close alerts',
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: _chip,
                    foregroundColor: _fg,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ),
            ]),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
              children: [
                if (action.isNotEmpty) ...[
                  _section('Needs your action · ${action.length}'),
                  for (final a in action) _actionRow(context, a),
                ],
                if (info.isNotEmpty) ...[
                  _section('For your info · $infoCount'),
                  for (final a in info)
                    a.waitingStops.isNotEmpty
                        ? _WaitingCustomers(alert: a)
                        : _infoRow(a),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: _muted)),
      );

  ({String label, VoidCallback onPressed})? _action(
      BuildContext context, SupervisorTripAlert alert) {
    final kind = alert.kind;
    void then(VoidCallback? next) {
      Navigator.of(context).pop();
      next?.call();
    }

    final navigator = Navigator.of(context);
    Future<void> open(Widget screen) async {
      await navigator.push(MaterialPageRoute(builder: (_) => screen));
      onChanged?.call();
    }

    switch (kind) {
      case TripAlertKind.breakdown:
        return (
          label: 'Review',
          onPressed: () => then(
              () => open(SupervisorBreakdownsScreen(breakdownId: alert.refId))),
        );
      case TripAlertKind.retrip:
        return (
          label: 'Decide',
          onPressed: () =>
              then(() => open(const SupervisorRetripRequestsScreen())),
        );
      case TripAlertKind.rejected:
      case TripAlertKind.noDriver:
      case TripAlertKind.noVehicle:
        if (onTripActions == null) return null;
        return (
          label: kind == TripAlertKind.rejected ? 'Resolve' : 'Assign',
          onPressed: () => then(onTripActions),
        );
      case TripAlertKind.delay:
        final id = alert.refId;
        if (id != null && id.isNotEmpty) {
          return (
            label: 'Review',
            onPressed: () =>
                then(() => open(SupervisorDelayReviewScreen(reportId: id))),
          );
        }
        if (onOpenTrip == null) return null;
        return (label: 'View', onPressed: () => then(onOpenTrip));
      case TripAlertKind.startOverdue:
        if (onOpenTrip == null) return null;
        return (label: 'View', onPressed: () => then(onOpenTrip));
      case TripAlertKind.customersWaiting:
      case TripAlertKind.awaitingClosure:
        return null;
    }
  }

  Widget _actionRow(BuildContext context, SupervisorTripAlert a) {
    final tone = AlertTone.of(a.severity);
    final action = _action(context, a);
    final tag = [
      a.severity == TripAlertSeverity.critical ? 'Critical' : 'Warning',
      if (a.time != null) a.time!,
    ].join(' · ');
    return _Row(
      icon: tone.icon,
      tone: tone,
      trailing: action == null
          ? null
          : FilledButton(
              onPressed: action.onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: tone.solid,
                foregroundColor: tone.onSolid,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              child: Text(action.label),
            ),
      children: [
        Text(tag,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: tone.ink)),
        Text(a.title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: _fg)),
        if (a.detail.isNotEmpty)
          Text(a.detail, style: const TextStyle(fontSize: 12, color: _muted)),
        if (a.imageUrls.isNotEmpty) ...[
          const SizedBox(height: 8),
          SupervisorPhotoStrip(urls: a.imageUrls),
        ],
      ],
    );
  }

  Widget _infoRow(SupervisorTripAlert a) => _Row(
        icon: Icons.notifications_rounded,
        tone: AlertTone.of(TripAlertSeverity.info),
        children: [
          Text(a.title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _fg)),
          if (a.detail.isNotEmpty)
            Text(a.detail, style: const TextStyle(fontSize: 12, color: _muted)),
        ],
      );
}

/// Light-surface severity colours shared by the sheet and the home summary.
class AlertTone {
  const AlertTone._(this.icon, this.ink, this.soft, this.solid, this.onSolid);

  final IconData icon;
  final Color ink;
  final Color soft;
  final Color solid;
  final Color onSolid;

  static AlertTone of(TripAlertSeverity severity) => switch (severity) {
        TripAlertSeverity.critical => const AlertTone._(
            Icons.error_rounded,
            Color(0xFFB42323),
            Color(0xFFFCE8E8),
            Color(0xFFD83B3B),
            Colors.white),
        TripAlertSeverity.warning => const AlertTone._(
            Icons.warning_rounded,
            Color(0xFF8B5D00),
            Color(0xFFFBF0D9),
            Color(0xFFD99A21),
            Color(0xFF070707)),
        TripAlertSeverity.info => const AlertTone._(
            Icons.notifications_rounded,
            Color(0xFF63615C),
            Color(0xFFEDEBE5),
            Color(0xFF63615C),
            Colors.white),
      };
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.tone,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final AlertTone tone;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: SupervisorTripAlertsSheet._line))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconBox(icon: icon, tone: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Align(alignment: Alignment.center, child: trailing),
            ],
          ],
        ),
      );
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.tone});

  final IconData icon;
  final AlertTone tone;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: tone.soft, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: tone.ink),
      );
}

/// "Customers waiting (47)" row that expands into a scrollable list of
/// names, addresses and how long each has waited, longest first.
class _WaitingCustomers extends StatefulWidget {
  const _WaitingCustomers({required this.alert});

  final SupervisorTripAlert alert;

  @override
  State<_WaitingCustomers> createState() => _WaitingCustomersState();
}

class _WaitingCustomersState extends State<_WaitingCustomers> {
  bool _open = false;

  static const _rowHeight = 50.0;
  static const _visibleRows = 8;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    int waitMinutes(SupervisorStop s) => now
        .difference(s.customerAvailableAt!.toLocal())
        .inMinutes
        .clamp(0, 9999);
    final stops = [...widget.alert.waitingStops]
      ..sort((a, b) => waitMinutes(b).compareTo(waitMinutes(a)));
    final longest = waitMinutes(stops.first);
    final tone = AlertTone.of(TripAlertSeverity.info);
    return Container(
      decoration: const BoxDecoration(
          border: Border(
              bottom: BorderSide(color: SupervisorTripAlertsSheet._line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                _IconBox(icon: Icons.groups_rounded, tone: tone),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Customers waiting (${stops.length})',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: SupervisorTripAlertsSheet._fg)),
                      Text('Longest wait $longest min · pressed “I’m home now”',
                          style: const TextStyle(
                              fontSize: 12,
                              color: SupervisorTripAlertsSheet._muted)),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? .5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded,
                      color: SupervisorTripAlertsSheet._muted),
                ),
              ]),
            ),
          ),
          if (_open) ...[
            Container(
              constraints:
                  const BoxConstraints(maxHeight: _rowHeight * _visibleRows),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F3EF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: SupervisorTripAlertsSheet._line),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: stops.length,
                separatorBuilder: (_, __) => const Divider(
                    height: 1, color: SupervisorTripAlertsSheet._line),
                itemBuilder: (_, i) =>
                    _customer(stops[i], waitMinutes(stops[i])),
              ),
            ),
            if (stops.length > _visibleRows)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.swipe_vertical_rounded,
                        size: 16, color: SupervisorTripAlertsSheet._muted),
                    const SizedBox(width: 4),
                    Text('Scroll to see all ${stops.length}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: SupervisorTripAlertsSheet._muted)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _customer(SupervisorStop stop, int minutes) {
    final initials = stop.name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
              color: SupervisorTripAlertsSheet._chip, shape: BoxShape.circle),
          child: Text(initials,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: SupervisorTripAlertsSheet._muted)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(stop.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: SupervisorTripAlertsSheet._fg)),
              if (stop.subtitle != null)
                Text(stop.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: SupervisorTripAlertsSheet._muted)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('waiting $minutes min',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: minutes >= 20
                    ? const Color(0xFF8B5D00)
                    : const Color(0xFF4E4C47))),
      ]),
    );
  }
}
