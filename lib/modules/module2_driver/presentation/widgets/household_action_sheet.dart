import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:iwms_private_app/core/ui/app_flash.dart';
import 'package:iwms_private_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/widgets/household_collect_sheet.dart';
import 'package:iwms_private_app/modules/module3_operator/utils/assignment_status_store.dart';

/// The customer action drawer — the same "Confirm customer" sheet the QR
/// scanner opens, with **Collect / Collect later / Not available**. Reused by
/// the household list so a list tap behaves exactly like scanning that
/// customer's QR: Collect opens the weight-capture screen; the other two
/// capture a reason and POST the household status.
///
/// Returns `true` when the household's status changed (collected / skipped /
/// missed), so the caller can refresh the list live.
Future<bool> showHouseholdActionSheet(
  BuildContext context, {
  required String customerId,
  required String customerName,
  required String contactNo,
  required String latitude,
  required String longitude,
  required String assignmentId,
  String? currentStatus,
}) async {
  final normalizedStatus = currentStatus?.trim().toLowerCase() ?? '';
  if (_isHandledStatus(normalizedStatus)) {
    final proceed = await _confirmHandledStop(
      context,
      customerId: customerId,
      customerName: customerName,
      currentStatus: normalizedStatus,
    );
    if (!proceed || !context.mounted) return false;
  }

  // Set by the drawer's bottom "Collect later" / "Not available" buttons. The
  // sheet itself resolves to a bool (did a collection finalize?), so the chosen
  // exception is captured here instead of squeezed into that return value.
  String? secondaryAction;

  // One drawer: customer identity at the top, the colour-coded waste list in
  // the middle, and the two exception options at the bottom. There is no
  // separate "Confirm customer" step any more — the driver taps and is
  // immediately looking at the streams they can weigh.
  final collected = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: CaptainTheme.surface,
    isScrollControlled: true,
    // The keyboard opens over this for weight entry and the list grows as a
    // card expands, so it needs a tall cap plus room to scroll.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.92,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => HouseholdCollectSheet(
      customerId: customerId,
      customerName: customerName,
      latitude: latitude,
      longitude: longitude,
      assignmentId: assignmentId,
      // Close this drawer first, then hand the chosen exception back so the
      // reason sheet isn't fighting the collect drawer for the screen.
      onSecondaryAction: (chosen) {
        secondaryAction = chosen;
        Navigator.of(sheetCtx).pop(false);
      },
    ),
  );

  if (!context.mounted) return false;

  if (collected == true) {
    await AssignmentStatusStore.setStatusForAssignment(
      assignmentId,
      customerId,
      'collected',
    );
    if (context.mounted) AppFlash.success(context, 'Collection saved');
    return true;
  }

  final action = secondaryAction;
  if (action == null) return false;

  // 'not_available' / 'collect_later' — capture a reason then POST the status.
  final reason = await _askReason(context, status: action);
  if (reason == null || !context.mounted) return false;

  try {
    await GetIt.instance<OperatorTripRepository>().markHouseholdStatus(
      customerId: customerId,
      status: action,
      reason: reason,
      assignmentId: assignmentId,
      latitude: latitude,
      longitude: longitude,
    );
    final localStatus = action == 'collect_later' ? 'later' : 'skipped';
    await AssignmentStatusStore.setStatusForAssignment(
      assignmentId,
      customerId,
      localStatus,
    );
    if (context.mounted) {
      AppFlash.success(
        context,
        action == 'not_available'
            ? 'Marked not available'
            : 'Marked collect later',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) AppFlash.error(context, 'Could not update: $e');
    return false;
  }
}

bool _isHandledStatus(String status) {
  return status == 'collected' ||
      status == 'not available' ||
      status == 'missed' ||
      status == 'skipped' ||
      status == 'not collected';
}

String _handledStatusLabel(String status) {
  switch (status) {
    case 'collected':
      return 'Collected';
    case 'collect later':
    case 'later':
      return 'Collect later';
    case 'not available':
    case 'missed':
    case 'not collected':
    case 'skipped':
      return 'Not available';
    default:
      return status;
  }
}

Future<bool> _confirmHandledStop(
  BuildContext context, {
  required String customerId,
  required String customerName,
  required String currentStatus,
}) async {
  final label = _handledStatusLabel(currentStatus);
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: CaptainTheme.surface,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.viewPaddingOf(sheetCtx).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stop already marked',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: CaptainTheme.strongText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$customerName • $customerId',
            style: TextStyle(
              color: CaptainTheme.mutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CaptainTheme.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CaptainTheme.hairline),
            ),
            child: Text(
              'This household is already marked as $label. Do you want to update it again?',
              style: TextStyle(
                color: CaptainTheme.strongText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CaptainTheme.strongText,
                    side: BorderSide(color: CaptainTheme.hairline),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.of(sheetCtx).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CaptainTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.of(sheetCtx).pop(true),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return result == true;
}

Future<String?> _askReason(BuildContext context, {required String status}) {
  final notAvailable = status == 'not_available';
  final quick = notAvailable
      ? const ['Gate locked', 'Nobody home', 'Refused', 'No waste out']
      : const ['Not ready yet', 'Come back later', 'Household busy'];
  final controller = TextEditingController();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: CaptainTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(ctx).unfocus(),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: 20 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notAvailable ? 'Why not available?' : 'Why collect later?',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: CaptainTheme.strongText),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in quick)
                    ChoiceChip(
                      label: Text(
                        q,
                        style: TextStyle(
                          color: controller.text == q
                              ? CaptainTheme.accentDeep
                              : CaptainTheme.strongText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      selected: controller.text == q,
                      selectedColor: CaptainTheme.accentSoft,
                      backgroundColor: CaptainTheme.surface,
                      disabledColor: CaptainTheme.surfaceMuted,
                      checkmarkColor: CaptainTheme.accentDeep,
                      side: BorderSide(
                        color: controller.text == q
                            ? CaptainTheme.accent
                            : CaptainTheme.hairline,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onSelected: (_) => setSheet(() => controller.text = q),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 1,
                maxLines: 3,
                cursorColor: CaptainTheme.accent,
                style: TextStyle(
                  color: CaptainTheme.strongText,
                  fontWeight: FontWeight.w600,
                ),
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Add a reason',
                  labelStyle: TextStyle(color: CaptainTheme.mutedText),
                  hintStyle: TextStyle(color: CaptainTheme.mutedText),
                  filled: true,
                  fillColor: CaptainTheme.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: CaptainTheme.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: CaptainTheme.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: CaptainTheme.accent,
                      width: 1.4,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: CaptainTheme.danger),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: CaptainTheme.danger,
                      width: 1.4,
                    ),
                  ),
                ),
                onChanged: (_) => setSheet(() {}),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: controller.text.trim().isEmpty
                      ? null
                      : () => Navigator.of(ctx).pop(controller.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CaptainTheme.accentDeep,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: CaptainTheme.surfaceMuted,
                    disabledForegroundColor: CaptainTheme.mutedText,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
