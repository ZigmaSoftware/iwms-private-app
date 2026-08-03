import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// Floating warning shown instead of opening the "Add team" form when every
/// driver/operator is already on an active team — offers the "alternative
/// staff template" (temporary substitution) flow as the only remaining path.
class SupervisorNoStaffDialog {
  const SupervisorNoStaffDialog._();

  /// Returns true if the supervisor tapped "Create alternative staff
  /// template"; false (or null, if dismissed) otherwise.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: SupervisorTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/no_staff_for_teams.png',
                height: 140,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              const Text(
                'All staff are already in a team',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: SupervisorTheme.strongText,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'No new team can be created — every driver and operator is '
                'already assigned to a team. You can still create an '
                'alternative staff template (a temporary substitution on an '
                'existing team).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: SupervisorTheme.mutedText,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SupervisorTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Create alternative staff template'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }
}
