import 'package:flutter/material.dart';
import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/core/permissions/feature_access.dart';
import '../../data/supervisor_models.dart';
import '../../data/supervisor_repository.dart';
import '../screens/supervisor_breakdowns_screen.dart';
import '../theme/supervisor_theme.dart';
import 'supervisor_substitute_staff_sheet.dart';

enum _TripAction { staff, breakdown, approve, reject, cancel }

class SupervisorTripActionsSheet {
  static Future<bool?> show(
    BuildContext context, {
    required String assignmentId,
    SupervisorAssignment? assignment,
  }) async {
    if (assignment != null && !assignment.isRemaining) return false;
    final canEdit =
        context.canDo('schedule-operations', 'daily-trip-assignments');
    final canStaff = context
        .canDo('schedule-setup', 'alternative-staff-templates', action: 'add');
    final canBreakdown =
        context.canDo('schedule-operations', 'vehicle-breakdowns');
    final actions = <_TripAction, String>{
      if (canStaff) _TripAction.staff: 'Substitute staff',
      if (canBreakdown && assignment?.hasPendingBreakdown == true)
        _TripAction.breakdown: 'Review vehicle breakdown',
      if (canEdit &&
          assignment?.isScheduled == true &&
          assignment?.isPendingApproval == true) ...{
        _TripAction.approve: 'Approve assignment',
        _TripAction.reject: 'Reject assignment',
      },
      if (canEdit && assignment?.isScheduled == true)
        _TripAction.cancel: 'Cancel unstarted trip',
    };
    final selected = await showModalBottomSheet<_TripAction>(
        context: context,
        backgroundColor: SupervisorTheme.surface,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
            child: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Trip actions',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          if (actions.isEmpty)
                            const Text(
                                'No changes are available for this trip with your current permissions.'),
                          for (final entry in actions.entries)
                            ListTile(
                                title: Text(entry.value),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () =>
                                    Navigator.of(sheetContext).pop(entry.key)),
                        ])))));
    if (selected == null || !context.mounted) return false;
    if (selected == _TripAction.staff) {
      return SupervisorSubstituteStaffSheet.show(context,
          assignmentId: assignmentId);
    }
    if (selected == _TripAction.breakdown) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const SupervisorBreakdownsScreen()));
      return true;
    }
    final reason = await _confirm(context, actions[selected]!,
        needsReason: selected != _TripAction.approve);
    if (reason == null || !context.mounted) return false;
    try {
      final repo = getIt<SupervisorRepository>();
      if (selected == _TripAction.cancel) {
        await repo.cancelScheduledTrip(assignmentId, reason);
      } else {
        await repo.reviewTripAssignment(assignmentId,
            approve: selected == _TripAction.approve, reason: reason);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Trip updated.')));
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is SupervisorException
                ? e.message
                : 'Could not update the trip. Please refresh and retry.')));
      }
      return false;
    }
  }

  static Future<String?> _confirm(BuildContext context, String title,
      {required bool needsReason}) async {
    var reason = "";
    final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (_, setDialogState) => AlertDialog(
                    title: Text(title),
                    content: needsReason
                        ? TextField(
                            maxLines: 3,
                            onChanged: (value) =>
                                setDialogState(() => reason = value.trim()),
                            style: SupervisorTheme.inputTextStyle,
                            decoration:
                                SupervisorTheme.inputDecoration('Reason'))
                        : const Text('Approve this trip assignment?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Back')),
                      FilledButton(
                          onPressed: needsReason && reason.isEmpty
                              ? null
                              : () => Navigator.of(dialogContext).pop(reason),
                          child: const Text('Confirm')),
                    ])));
    return result;
  }
}
