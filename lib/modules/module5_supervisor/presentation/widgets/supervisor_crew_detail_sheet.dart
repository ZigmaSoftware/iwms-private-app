import 'package:flutter/material.dart';

import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_private_app/shared/widgets/crew_avatar_stack.dart';

/// Tapping the enlarged crew avatar stack on a trip card opens this — the
/// crew's photos in a row, each with their emp id + mobile number.
class SupervisorCrewDetailSheet extends StatelessWidget {
  const SupervisorCrewDetailSheet({super.key, required this.crew});

  final OperatorTripCrew crew;

  static Future<void> show(BuildContext context, OperatorTripCrew crew) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupervisorCrewDetailSheet(crew: crew),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = <OperatorTripCrewMember>[
      if (crew.driver != null) crew.driver!,
      ...crew.operators,
    ];
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
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
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Crew',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: SupervisorTheme.strongText,
                ),
              ),
            ),
            Flexible(
              child: members.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Text(
                        'No crew assigned.',
                        style: TextStyle(color: SupervisorTheme.mutedText),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        4,
                        20,
                        20 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < members.length; i++) ...[
                            if (i > 0) const SizedBox(width: 16),
                            _memberColumn(members[i]),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberColumn(OperatorTripCrewMember member) {
    return SizedBox(
      width: 120,
      child: Column(
        children: [
          CrewAvatar(member: member, size: 64, borderColor: SupervisorTheme.hairline),
          const SizedBox(height: 8),
          Text(
            member.displayName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: SupervisorTheme.strongText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            member.roleLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: SupervisorTheme.mutedText),
          ),
          const SizedBox(height: 6),
          if ((member.empId ?? '').trim().isNotEmpty)
            Text(
              'Emp ID: ${member.empId}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: SupervisorTheme.strongText,
              ),
            ),
          if ((member.phone ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              member.phone!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: SupervisorTheme.strongText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
