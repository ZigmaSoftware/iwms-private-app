import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:iwms_private_app/core/ui/app_flash.dart';
import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';

/// Explicit Start / End Trip control for the driver home card.
///
/// Ported from the government app's `trip_lifecycle_control.dart`. Before
/// this, a trip was started only as a *side effect* of the first bin scan,
/// so a household trip never started explicitly and nothing ever closed a
/// trip that had a skipped/not-available stop — it just sat "In Progress"
/// forever. Now the driver presses Start, and End either closes the trip
/// outright or — if stops remain — raises a Re-Trip request for a
/// supervisor to review (see `app/services/retrip_service.py`).
class TripLifecycleControl extends StatefulWidget {
  const TripLifecycleControl({
    super.key,
    required this.trip,
    required this.onChanged,
    this.locked = false,
  });

  final OperatorTripToday trip;

  /// Re-fetches today's trip(s) after a successful start/end — this widget
  /// holds no local trip-state cache of its own.
  final Future<void> Function() onChanged;

  /// Locked trips (an earlier same-type trip isn't finished yet) don't show
  /// the control at all — there is nothing to start yet.
  final bool locked;

  @override
  State<TripLifecycleControl> createState() => _TripLifecycleControlState();
}

class _TripLifecycleControlState extends State<TripLifecycleControl> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    // isClosed (status == Completed on the server), NOT isFinished/
    // progress.completed: ending a trip is now a driver-confirmed action (see
    // TripCompletionNudge) rather than something the backend does silently
    // the moment the last stop resolves. A fully-resolved-but-not-yet-ended
    // trip must keep showing this button — hiding it here would leave the
    // driver with no way to end it if they dismiss the nudge.
    if (widget.locked || trip.isClosed) return const SizedBox.shrink();

    if (trip.hasPendingRetrip) {
      return _PendingRetripBanner(request: trip.retripRequest!);
    }

    final isRunning = trip.isStarted &&
        trip.status.toLowerCase() == 'in progress';

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : (isRunning ? _confirmEnd : _start),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isRunning ? CaptainTheme.danger : CaptainTheme.success,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(
          isRunning ? 'End Trip' : 'Start Trip',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
        ),
      ),
    );
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await GetIt.instance<OperatorTripRepository>()
          .startTrip(widget.trip.assignmentUniqueId);
      if (mounted) AppFlash.success(context, 'Trip started');
      await widget.onChanged();
    } on OperatorTripException catch (e) {
      if (mounted) AppFlash.error(context, _friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmEnd() async {
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

/// Runs the confirm-then-end sequence for [trip]: the confirm sheet, then
/// `endTrip()`, then (if the backend asks for one) the reason sheet, then a
/// final `endTrip(reason: ...)`.
///
/// Top-level and reusable so [TripLifecycleControl]'s own button and
/// `TripCompletionNudge` (the floating "all stops resolved — end trip?"
/// prompt) share exactly one place that knows how to end a trip, rather than
/// each having its own copy of this sequence to keep in sync.
///
/// [setBusy], if given, is called with true/false around the network calls —
/// callers without their own busy indicator can omit it.
Future<void> confirmAndEndTrip(
  BuildContext context, {
  required OperatorTripToday trip,
  required Future<void> Function() onChanged,
  void Function(bool busy)? setBusy,
}) async {
  // Server-computed, NOT `trip.collectionPoints`/`householdCollections` —
  // those only ever hold the first page of stops now (see STOPS_PAGE_SIZE on
  // the backend), so counting against them would undercount a trip with more
  // than one page left pending.
  final pending = trip.progress.total - trip.progress.collected;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ConfirmEndSheet(pendingStopCount: pending),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  await _endTrip(context, trip: trip, onChanged: onChanged, setBusy: setBusy);
}

Future<void> _endTrip(
  BuildContext context, {
  required OperatorTripToday trip,
  required Future<void> Function() onChanged,
  void Function(bool busy)? setBusy,
  String? reason,
}) async {
  setBusy?.call(true);
  try {
    final result = await GetIt.instance<OperatorTripRepository>().endTrip(
      trip.assignmentUniqueId,
      reason: reason,
    );

    if (result.reasonRequired) {
      setBusy?.call(false);
      if (!context.mounted) return;
      final givenReason = await showEndTripReasonSheet(
        context,
        pendingBinCount: result.pendingBinCount,
        pendingHouseholdCount: result.pendingHouseholdCount,
      );
      if (givenReason != null &&
          givenReason.trim().isNotEmpty &&
          context.mounted) {
        await _endTrip(
          context,
          trip: trip,
          onChanged: onChanged,
          setBusy: setBusy,
          reason: givenReason.trim(),
        );
      }
      return;
    }

    if (result.ended) {
      if (context.mounted) AppFlash.success(context, 'Trip completed');
    } else if (result.retripRequested) {
      if (context.mounted) {
        AppFlash.success(
          context,
          'Requested next trip for the remaining stops — '
          'awaiting supervisor approval',
        );
      }
    }
    await onChanged();
  } on OperatorTripException catch (e) {
    if (context.mounted) AppFlash.error(context, _friendlyMessage(e));
  } finally {
    setBusy?.call(false);
  }
}

/// Maps backend error codes to driver-facing copy. `REASON_REQUIRED` never
/// reaches here — the repository converts it to a normal
/// [OperatorTripEndResult] instead of throwing. `ALREADY_ENDED`,
/// `TRIP_CANCELLED` and `RETRIP_PENDING` fall through to the backend's own
/// message text, which already reads as a complete sentence.
String _friendlyMessage(OperatorTripException e) {
  switch (e.code) {
    case 'TRIP_NOT_YOURS':
      return 'This trip is not assigned to you today.';
    default:
      return e.message.isEmpty ? 'Could not update the trip.' : e.message;
  }
}

/// Shown in place of the Start/End button while a Re-Trip request raised
/// from this trip awaits supervisor review. No button — the driver can keep
/// collecting elsewhere on the same trip while they wait.
class _PendingRetripBanner extends StatelessWidget {
  const _PendingRetripBanner({required this.request});

  final OperatorTripRetripRequest request;

  @override
  Widget build(BuildContext context) {
    final pending = request.pendingBinCount + request.pendingHouseholdCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CaptainTheme.goldSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CaptainTheme.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top_rounded, size: 19, color: CaptainTheme.gold),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Awaiting supervisor approval',
                  style: TextStyle(
                    color: CaptainTheme.strongText,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pending > 0
                      ? 'Requested to end this trip with $pending stop(s) '
                          'left. You can keep collecting while you wait.'
                      : 'Requested to end this trip early. You can keep '
                          'collecting while you wait.',
                  style: TextStyle(
                    color: CaptainTheme.mutedText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    height: 1.35,
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

/// Confirm sheet before End Trip — cheap to cancel, so a stray tap doesn't
/// immediately fire the request.
class _ConfirmEndSheet extends StatelessWidget {
  const _ConfirmEndSheet({required this.pendingStopCount});

  final int pendingStopCount;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: _sheetShell(
        context,
        children: [
          Icon(Icons.stop_circle_rounded, size: 40, color: CaptainTheme.danger),
          const SizedBox(height: 12),
          Text(
            'End this trip?',
            style: TextStyle(
              color: CaptainTheme.strongText,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            pendingStopCount > 0
                ? 'You still have $pendingStopCount stop(s) left. Ending now '
                    'will ask your supervisor to arrange the rest on a '
                    'follow-up trip.'
                : 'All stops are resolved — this will mark the trip complete.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CaptainTheme.mutedText,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(color: CaptainTheme.hairline),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: CaptainTheme.strongText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CaptainTheme.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'End Trip',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mandatory reason prompt for ending a trip early. Returns the trimmed
/// reason, or null if the driver backed out.
Future<String?> showEndTripReasonSheet(
  BuildContext context, {
  required int pendingBinCount,
  required int pendingHouseholdCount,
}) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
      final pending = pendingBinCount + pendingHouseholdCount;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: _sheetShell(
          sheetContext,
          children: [
            Icon(Icons.edit_note_rounded, size: 36, color: CaptainTheme.gold),
            const SizedBox(height: 10),
            Text(
              'Reason for ending early',
              style: TextStyle(
                color: CaptainTheme.strongText,
                fontWeight: FontWeight.w800,
                fontSize: 16.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              pending > 0
                  ? '$pending stop(s) are still pending. Tell your '
                      'supervisor why you need to stop now — they\'ll '
                      'arrange the rest.'
                  : 'Tell your supervisor why you need to stop now.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CaptainTheme.mutedText,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'e.g. Vehicle breakdown, running out of shift...',
                filled: true,
                fillColor: CaptainTheme.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
              style: TextStyle(color: CaptainTheme.strongText),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(null),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(color: CaptainTheme.hairline),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: CaptainTheme.strongText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final text = controller.text.trim();
                      if (text.isEmpty) {
                        AppFlash.warning(sheetContext, 'Enter a reason first');
                        return;
                      }
                      Navigator.of(sheetContext).pop(text);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CaptainTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Submit',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// Client-side explainer shown when the driver taps a stop before pressing
/// Start — a friendlier lead-in to the backend's `TRIP_NOT_STARTED` (409).
void showStartRequiredSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _sheetShell(
      sheetContext,
      children: [
        Icon(Icons.play_circle_rounded, size: 40, color: CaptainTheme.accent),
        const SizedBox(height: 12),
        Text(
          'Start the trip first',
          style: TextStyle(
            color: CaptainTheme.strongText,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Press "Start Trip" above before collecting a stop.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: CaptainTheme.mutedText,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(sheetContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: CaptainTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    ),
  );
}

Widget _sheetShell(BuildContext context, {required List<Widget> children}) {
  return SafeArea(
    top: false,
    child: Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: CaptainTheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: CaptainTheme.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    ),
  );
}
