import 'package:flutter/material.dart';

import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/widgets/trip_lifecycle_control.dart';

/// True once every stop on [trip] has been acted on — collected, marked Not
/// Available, or postponed as Collect Later — with at least one stop to act
/// on in the first place.
///
/// Mirrors the backend's own `progress.resolved` definition
/// (`is_collected OR status != Pending` — see `trip_today_serializer.py`),
/// so the app and server agree on what "nothing left to do" means.
///
/// Deliberately broader than [OperatorTripToday.isFinished]/
/// `progress.completed` (which requires every stop STRICTLY collected): a
/// trip where the driver postponed a few stops to Collect Later has just as
/// clearly reached "no more work right now" as one that is 100% collected —
/// the only difference is which of the two nudge messages below applies, not
/// whether the nudge should appear at all.
bool isFullyResolved(OperatorTripToday trip) {
  final total = trip.progress.total;
  return total > 0 && trip.progress.resolved == total;
}

/// How many of [trip]'s stops were postponed (Collect Later / Skipped) rather
/// than collected or marked Not Available — decides which of the two nudge
/// messages [TripCompletionNudge] shows.
///
/// Server-computed (`progress.postponed`), NOT counted from
/// `trip.collectionPoints`/`householdCollections` directly: those only ever
/// hold the first page of stops once a trip has more than
/// `STOPS_PAGE_SIZE` (20) of them, so counting locally would silently miss
/// any postponed stop past page 1.
int postponedStopCount(OperatorTripToday trip) => trip.progress.postponed;

/// Floating prompt shown once [trip]'s stops are all resolved but the trip
/// itself has not been ended yet.
///
/// Ending a trip used to be either a manual afterthought (the driver had to
/// notice and reach for "End Trip" themselves) or, for a fully-collected
/// trip, something the backend did invisibly the instant the last stop was
/// scanned (`mark_completed_if_all_cps_collected`/
/// `..._household_stops_collected` used to call `mark_ended()` unconditionally
/// — see those methods' docstrings for the `auto_end` parameter that changed
/// this). Neither gave the driver a moment to actually decide. This widget is
/// that moment: it appears exactly once per resolution (see
/// `_CaptainHomeTabState`'s transition tracking in `captain_home_tab.dart`,
/// which owns showing/dismissing this — the widget itself has no memory of
/// whether it already appeared for this trip).
///
/// Tapping "End Trip" runs the EXACT SAME [confirmAndEndTrip] sequence as
/// [TripLifecycleControl]'s own button — this is a second entry point to that
/// flow, not a second implementation of it.
class TripCompletionNudge extends StatefulWidget {
  const TripCompletionNudge({
    super.key,
    required this.trip,
    required this.onChanged,
    required this.onDismiss,
  });

  final OperatorTripToday trip;

  /// Re-fetches today's trip(s) after a successful end — same contract as
  /// [TripLifecycleControl.onChanged].
  final Future<void> Function() onChanged;

  /// Driver tapped "Not now". The HOST decides whether this can reappear
  /// (e.g. after a fresh resolution on a later continuation trip) — this
  /// widget has no state of its own once it's built.
  final VoidCallback onDismiss;

  @override
  State<TripCompletionNudge> createState() => _TripCompletionNudgeState();
}

class _TripCompletionNudgeState extends State<TripCompletionNudge> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final postponed = postponedStopCount(widget.trip);
    final allCollected = postponed == 0;
    final accent = allCollected ? CaptainTheme.success : CaptainTheme.gold;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CaptainTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
        boxShadow: CaptainTheme.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            allCollected
                ? Icons.task_alt_rounded
                : Icons.event_available_rounded,
            color: accent,
            size: 22,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allCollected
                      ? 'All ${widget.trip.progress.total} stops collected'
                      : 'All stops resolved',
                  style: TextStyle(
                    color: CaptainTheme.strongText,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  allCollected
                      ? 'Nothing left on this trip. End it now?'
                      : '$postponed marked Collect Later. End this trip? '
                          'They\'ll move to a follow-up trip.',
                  style: TextStyle(
                    color: CaptainTheme.mutedText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : widget.onDismiss,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: CaptainTheme.hairline),
                        ),
                        child: Text(
                          'Not now',
                          style: TextStyle(
                            color: CaptainTheme.strongText,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _busy ? null : _endTapped,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : const Text(
                                'End Trip',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _endTapped() async {
    await confirmAndEndTrip(
      context,
      trip: widget.trip,
      onChanged: widget.onChanged,
      setBusy: (busy) {
        if (mounted) setState(() => _busy = busy);
      },
    );
  }
}
