import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';

/// Small overlapping circular crew avatars (driver + operator + extras).
/// Each shows the crew member's registered attendance face; falls back to the
/// bundled default silhouette when no face is registered (or the photo fails
/// to load). Shared between the driver and supervisor modules so "who's on
/// this vehicle" looks identical everywhere it appears.
class CrewAvatarStack extends StatelessWidget {
  const CrewAvatarStack({
    super.key,
    required this.crew,
    this.onTap,
    this.size = 22,
    this.overlap = 12,
    this.borderColor = Colors.white,
  });

  final OperatorTripCrew crew;
  final VoidCallback? onTap;
  final double size;
  final double overlap;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final members = <OperatorTripCrewMember>[
      if (crew.driver != null) crew.driver!,
      ...crew.operators,
    ];
    if (members.isEmpty) return const SizedBox.shrink();
    final stackWidth = size + (overlap * (members.length - 1));

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: stackWidth,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var index = members.length - 1; index >= 0; index -= 1)
              Positioned(
                left: overlap * index,
                child: CrewAvatar(
                  member: members[index],
                  size: size,
                  borderColor: borderColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single circular crew-member avatar with the same photo/fallback rules as
/// [CrewAvatarStack] — usable standalone (e.g. a larger avatar in a detail
/// dialog) as well as inside the stack.
class CrewAvatar extends StatelessWidget {
  const CrewAvatar({
    super.key,
    required this.member,
    this.size = 22,
    this.borderColor = Colors.white,
    this.borderWidth = 1.5,
  });

  final OperatorTripCrewMember member;
  final double size;
  final Color borderColor;
  final double borderWidth;

  static const String _defaultAsset = 'assets/images/crew_default.png';

  @override
  Widget build(BuildContext context) {
    final photoUrl = member.photoUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: ClipOval(
        child: (photoUrl != null && photoUrl.isNotEmpty)
            ? Image.network(
                photoUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // No registered face (or the URL fails to load) → default silhouette.
                errorBuilder: (_, __, ___) => Image.asset(
                  _defaultAsset,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              )
            : Image.asset(
                _defaultAsset,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
      ),
    );
  }
}
