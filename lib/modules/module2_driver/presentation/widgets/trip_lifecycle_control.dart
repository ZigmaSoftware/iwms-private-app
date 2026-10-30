import 'dart:async';

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

    final isRunning =
        trip.isStarted && trip.status.toLowerCase() == 'in progress';

    // Mirrors the backend's start guard: only a not-yet-started trip is
    // blocked; one already running on the broken vehicle can still be ended.
    if (!trip.isStarted && (trip.vehicle?.isUnderBreakdown ?? false)) {
      return _VehicleBreakdownBanner(vehicleNo: trip.vehicle!.vehicleNo);
    }

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
      // The vehicle went into breakdown since the last refresh — reload so
      // the card shows the breakdown banner instead of Start.
      if (e.code == 'VEHICLE_BREAKDOWN') await widget.onChanged();
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
  EndTripReason? reason,
}) async {
  setBusy?.call(true);
  try {
    final result = await GetIt.instance<OperatorTripRepository>().endTrip(
      trip.assignmentUniqueId,
      reason: reason?.note,
      reasonCode: reason?.code,
    );

    if (result.reasonRequired) {
      setBusy?.call(false);
      if (!context.mounted) return;
      final givenReason = await showEndTripReasonSheet(
        context,
        pendingBinCount: result.pendingBinCount,
        pendingHouseholdCount: result.pendingHouseholdCount,
        reasonCodes: result.reasonCodes,
        initial: reason,
        // Only a rejected submission has something to explain; the first
        // prompt's detail is just "enter a reason".
        errorText: reason != null ? result.message : null,
      );
      if (givenReason != null && context.mounted) {
        await _endTrip(
          context,
          trip: trip,
          onChanged: onChanged,
          setBusy: setBusy,
          reason: givenReason,
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
    case 'VEHICLE_BREAKDOWN':
      return 'This vehicle is under breakdown. Contact your supervisor.';
    default:
      return e.message.isEmpty ? 'Could not update the trip.' : e.message;
  }
}

/// Shown in place of the Start/End button while a Re-Trip request raised
/// from this trip awaits supervisor review. No button — the driver can keep
/// collecting elsewhere on the same trip while they wait.
class _PendingRetripBanner extends StatefulWidget {
  const _PendingRetripBanner({required this.request});

  final OperatorTripRetripRequest request;

  @override
  State<_PendingRetripBanner> createState() => _PendingRetripBannerState();
}

class _PendingRetripBannerState extends State<_PendingRetripBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
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
                if (request.expiryLabel().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    request.expiryLabel(),
                    style: TextStyle(
                      color: request.remaining() == Duration.zero
                          ? CaptainTheme.danger
                          : CaptainTheme.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
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

/// Shown in place of Start while the trip's vehicle is under breakdown. The
/// supervisor either moves the trip to a replacement vehicle or marks this
/// one repaired; either way the next refresh brings Start back.
class _VehicleBreakdownBanner extends StatelessWidget {
  const _VehicleBreakdownBanner({required this.vehicleNo});

  final String vehicleNo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CaptainTheme.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CaptainTheme.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.car_repair_rounded, size: 19, color: CaptainTheme.danger),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vehicle under breakdown',
                  style: TextStyle(
                    color: CaptainTheme.strongText,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${vehicleNo.isEmpty ? 'This vehicle' : vehicleNo} can\'t '
                  'start this trip until it is repaired or replaced. '
                  'Contact your supervisor.',
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

/// The driver's answer to the end-early prompt: a reason category (null when
/// the backend offered none) plus a note. The note is required only for
/// "Other" / no category; for a listed category it's optional detail.
class EndTripReason {
  const EndTripReason({this.code, this.note = ''});

  final String? code;
  final String note;
}

/// Backend: TripRetripRequest.OTHER_REASON_MIN_LENGTH.
const int _minEndReasonLength = 10;

/// Mandatory reason prompt for ending a trip early. Returns the reason, or
/// null if the driver backed out.
Future<EndTripReason?> showEndTripReasonSheet(
  BuildContext context, {
  required int pendingBinCount,
  required int pendingHouseholdCount,
  List<RetripReasonCode> reasonCodes = const [],
  EndTripReason? initial,
  String? errorText,
}) {
  return showModalBottomSheet<EndTripReason>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _EndTripReasonSheet(
      pendingStopCount: pendingBinCount + pendingHouseholdCount,
      reasonCodes: reasonCodes,
      initial: initial,
      errorText: errorText,
    ),
  );
}

class _EndTripReasonSheet extends StatefulWidget {
  const _EndTripReasonSheet({
    required this.pendingStopCount,
    required this.reasonCodes,
    this.initial,
    this.errorText,
  });

  final int pendingStopCount;
  final List<RetripReasonCode> reasonCodes;
  final EndTripReason? initial;
  final String? errorText;

  @override
  State<_EndTripReasonSheet> createState() => _EndTripReasonSheetState();
}

class _EndTripReasonSheetState extends State<_EndTripReasonSheet> {
  late final TextEditingController _note =
      TextEditingController(text: widget.initial?.note ?? '');
  late RetripReasonCode? _selected = widget.reasonCodes
      .where((c) => c.value == widget.initial?.code)
      .firstOrNull;

  bool get _hasCodes => widget.reasonCodes.isNotEmpty;

  /// No categories (older backend) behaves like "Other": text is the reason.
  bool get _noteRequired => !_hasCodes || (_selected?.isOther ?? false);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (_hasCodes && _selected == null) {
      AppFlash.warning(context, 'Choose a reason first');
      return;
    }
    final text = _note.text.trim();
    if (_noteRequired) {
      if (text.isEmpty) {
        AppFlash.warning(context, 'Enter a reason first');
        return;
      }
      if (text.length < _minEndReasonLength) {
        AppFlash.warning(
          context,
          'Reason must be at least $_minEndReasonLength characters',
        );
        return;
      }
    }
    Navigator.of(context).pop(EndTripReason(code: _selected?.value, note: text));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final pending = widget.pendingStopCount;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: _sheetShell(
        context,
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
          if (_hasCodes) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final code in widget.reasonCodes)
                  ChoiceChip(
                    label: Text(code.label),
                    selected: _selected?.value == code.value,
                    onSelected: (_) => setState(() => _selected = code),
                    selectedColor: CaptainTheme.accent,
                    backgroundColor: CaptainTheme.surfaceMuted,
                    showCheckmark: false,
                    side: BorderSide(color: CaptainTheme.hairline),
                    labelStyle: TextStyle(
                      color: _selected?.value == code.value
                          ? Colors.white
                          : CaptainTheme.strongText,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            autofocus: !_hasCodes,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _noteRequired
                  ? (_hasCodes
                      ? 'Describe the reason (at least $_minEndReasonLength characters)'
                      : 'e.g. Vehicle breakdown, running out of shift...')
                  : 'Add a note (optional)',
              filled: true,
              fillColor: CaptainTheme.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
              errorText: widget.errorText,
              errorMaxLines: 3,
            ),
            style: TextStyle(color: CaptainTheme.strongText),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
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
                  onPressed: _submit,
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
  }
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
            child: const Text('Got it',
                style: TextStyle(fontWeight: FontWeight.w800)),
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
