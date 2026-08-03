import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import 'package:iwms_citizen_app/core/ui/app_flash.dart';
import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';
import 'package:iwms_citizen_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/screens/operator_trip_history_screen.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/state/trip_sequence.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/widgets/household_action_sheet.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/widgets/bin_detail_sheet.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/widgets/captain_glass.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/widgets/captain_nav_bar.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/widgets/collection_progress_meter.dart';
import 'package:iwms_citizen_app/shared/widgets/crew_avatar_stack.dart';

/// Captain Home — the "today-first" dashboard of the merged driver app.
///
/// Everything the driver needs at a glance, ranked by how often they reach
/// for it on the road:
///   1. hero trip card (route, vehicle, progress ring, status)
///   2. quick actions (Navigate / Scan / History)
///   3. stop-by-stop timeline — tap a pending stop to open weight entry
///   4. crew card — the operator(s) riding this vehicle today
class CaptainHomeTab extends StatefulWidget {
  const CaptainHomeTab({
    super.key,
    required this.trips,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onOpenMap,
    required this.onScan,
    this.onOpenTrips,
    this.driverName,
  });

  /// All of the driver's trips today. When more than one (e.g. a bin trip AND a
  /// household trip) the header becomes a horizontally-swipeable carousel.
  final List<OperatorTripToday> trips;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;

  /// Opens the Map tab for a specific trip so the map plots that trip's stops
  /// (bin collection points, or household customer locations).
  final void Function(OperatorTripToday trip) onOpenMap;
  final VoidCallback onScan;

  /// Opens the trips view (current + history). Falls back to the shared
  /// trip-history screen when the host doesn't provide one.
  final VoidCallback? onOpenTrips;
  final String? driverName;

  @override
  State<CaptainHomeTab> createState() => _CaptainHomeTabState();
}

class _CaptainHomeTabState extends State<CaptainHomeTab> {
  int _selected = 0;
  // The selected trip's stable identity, so a background refresh (the driver's
  // location poll rebuilds this tab periodically) that returns the trips in a
  // different order doesn't silently swap which trip "index 1" points at —
  // that was surfacing as the carousel appearing to snap back to a previous
  // card even though the user hadn't touched it.
  String? _selectedTripId;

  // A horizontal SingleChildScrollView is used instead of PageView. PageView
  // requires an artificial fixed height, which was the reason the trip card
  // looked too tall on the real DriverHomePage. This carousel takes the exact
  // natural height of its cards and is snapped manually after a swipe.
  final ScrollController _carouselController = ScrollController();
  double _carouselItemExtent = 0;
  bool _carouselSnapping = false;

  @override
  void didUpdateWidget(covariant CaptainHomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trips.isEmpty) return;

    // Re-locate the previously-selected trip by identity in the (possibly
    // reordered) new list, rather than trusting the old raw index.
    final newIndex = _selectedTripId == null
        ? -1
        : widget.trips
            .indexWhere((t) => t.assignmentUniqueId == _selectedTripId);

    final targetIndex =
        newIndex != -1 ? newIndex : _selected.clamp(0, widget.trips.length - 1);

    if (targetIndex != _selected) {
      _selected = targetIndex;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_carouselController.hasClients ||
            _carouselItemExtent <= 0) {
          return;
        }

        final target = (_selected * _carouselItemExtent)
            .clamp(0.0, _carouselController.position.maxScrollExtent)
            .toDouble();
        _carouselController.jumpTo(target);
      });
    }
    _selectedTripId = widget.trips[_selected].assignmentUniqueId;
  }

  @override
  void dispose() {
    _carouselController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CaptainBackground(
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.loading) {
      return Center(
        child: CircularProgressIndicator(color: CaptainTheme.accent),
      );
    }
    if (widget.error != null) {
      return _MessageView(
        icon: Icons.error_outline_rounded,
        iconColor: CaptainTheme.danger,
        title: 'Could not load your trip',
        message: widget.error!,
        actionLabel: 'Retry',
        onAction: widget.onRefresh,
      );
    }
    if (widget.trips.isEmpty) {
      return _MessageView(
        imageAsset: 'assets/images/no_assignments.png',
        title: 'No trip today',
        message:
            'No trip has been assigned to this vehicle yet. Pull to refresh or check with your supervisor.',
        actionLabel: 'Refresh',
        onAction: widget.onRefresh,
      );
    }

    final trips = widget.trips;
    final selected = _selected.clamp(0, trips.length - 1);
    final t = trips[selected];
    final multi = trips.length > 1;
    // First build: seed the identity tracker used by didUpdateWidget above.
    _selectedTripId ??= t.assignmentUniqueId;

    final blockers = tripBlockers(trips);
    final blocker = blockers[t.assignmentUniqueId];
    final locked = blocker != null;

    final bottomSafeArea = MediaQuery.viewPaddingOf(context).bottom;

    return RefreshIndicator(
      color: CaptainTheme.accent,
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // DriverHomePage already owns the header and overlays the bottom
        // navigation/FAB. A 16 px page grid matches its map/profile sections.
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          kCaptainHomeBottomClearance + bottomSafeArea,
        ),
        children: [
          if (multi)
            _buildTripCarousel(
              trips: trips,
              selected: selected,
              blockers: blockers,
            )
          else
            _TripHeroCard(
              trip: t,
              onOpenMap: () => widget.onOpenMap(t),
            ),
          const SizedBox(height: 12),
          _QuickActionsRow(
            onOpenMap: () => widget.onOpenMap(t),
            // Scanning a locked trip's bin is rejected by the backend
            // (TRIP_LOCKED), so don't offer the scanner for it at all.
            onScan: locked ? null : widget.onScan,
            onHistory: widget.onOpenTrips ??
                () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OperatorTripHistoryScreen(),
                      ),
                    ),
          ),
          const SizedBox(height: 16),
          if (locked) ...[
            _LockedTripBanner(blocker: blocker),
            const SizedBox(height: 16),
          ],
          // Household / bulk trips collect customers directly (no bins), so
          // show the household list instead of the bin route + collection points.
          if (t.isHousehold) ...[
            _SectionTitle(
              title: 'Households',
              trailing: '${t.progress.resolved}/${t.progress.total} done',
            ),
            const SizedBox(height: 10),
            _HouseholdTimeline(
              trip: t,
              onChanged: widget.onRefresh,
              locked: locked,
            ),
          ] else ...[
            CollectionProgressMeter(collectionPoints: t.collectionPoints),
            const SizedBox(height: 16),
            _SectionTitle(
              title: 'Collection points',
              trailing: '${t.progress.resolved}/${t.progress.total} done',
            ),
            const SizedBox(height: 10),
            _StopsTimeline(
              trip: t,
              onChanged: widget.onRefresh,
              locked: locked,
            ),
          ],
        ],
      ),
    );
  }

  /// Content-sized horizontal carousel.
  ///
  /// Unlike PageView, this widget does not need a hard-coded height. Its height
  /// is exactly the natural height of [_TripHeroCard], so there is no empty
  /// lower area on Android, iOS, tablets or accessibility text sizes.
  Widget _buildTripCarousel({
    required List<OperatorTripToday> trips,
    required int selected,
    required Map<String, TripBlocker> blockers,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final cardFraction = availableWidth < 340 ? 0.965 : 0.945;
        final cardWidth = availableWidth * cardFraction;
        const gap = 8.0;

        _carouselItemExtent = cardWidth + gap;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NotificationListener<ScrollEndNotification>(
              onNotification: (notification) {
                _snapCarousel(trips.length);
                return false;
              },
              child: SingleChildScrollView(
                controller: _carouselController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                clipBehavior: Clip.none,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < trips.length; index++) ...[
                      SizedBox(
                        width: cardWidth,
                        child: _TripHeroCard(
                          trip: trips[index],
                          onOpenMap: () => widget.onOpenMap(trips[index]),
                          blocker: blockers[trips[index].assignmentUniqueId],
                          // Position within the whole day's carousel, so the
                          // card can label itself "Trip 2 of 3".
                          index: index,
                          total: trips.length,
                        ),
                      ),
                      if (index != trips.length - 1) const SizedBox(width: gap),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            _CarouselDots(count: trips.length, index: selected),
          ],
        );
      },
    );
  }

  Future<void> _snapCarousel(int itemCount) async {
    if (_carouselSnapping ||
        itemCount <= 1 ||
        !_carouselController.hasClients ||
        _carouselItemExtent <= 0) {
      return;
    }

    final maxIndex = itemCount - 1;
    final targetIndex = (_carouselController.offset / _carouselItemExtent)
        .round()
        .clamp(0, maxIndex)
        .toInt();
    final targetOffset = (targetIndex * _carouselItemExtent)
        .clamp(0.0, _carouselController.position.maxScrollExtent)
        .toDouble();

    if (_selected != targetIndex && mounted) {
      setState(() => _selected = targetIndex);
      if (targetIndex < widget.trips.length) {
        _selectedTripId = widget.trips[targetIndex].assignmentUniqueId;
      }
    }

    if ((_carouselController.offset - targetOffset).abs() < 0.5) return;

    _carouselSnapping = true;
    try {
      await _carouselController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _carouselSnapping = false;
    }
  }
}

/// Small page-dots indicator for the header carousel.
class _CarouselDots extends StatelessWidget {
  const _CarouselDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: i == index ? 15 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: i == index
                  ? CaptainTheme.accent
                  : CaptainTheme.mutedText.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

// Crew avatar widgets moved to lib/shared/widgets/crew_avatar_stack.dart
// (CrewAvatarStack / CrewAvatar) so the supervisor module can reuse them.

Future<void> _showCrewDialog(BuildContext context, OperatorTripCrew crew) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Crew',
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) {
      return _CrewDialog(crew: crew);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _CrewDialog extends StatelessWidget {
  const _CrewDialog({required this.crew});

  final OperatorTripCrew crew;

  @override
  Widget build(BuildContext context) {
    final members = <OperatorTripCrewMember>[
      if (crew.driver != null) crew.driver!,
      ...crew.operators,
    ];

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: CaptainGlassCard(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    borderRadius: const BorderRadius.all(Radius.circular(24)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.groups_rounded,
                              size: 20,
                              color: CaptainTheme.accent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Crew details',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: CaptainTheme.strongText,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                              color: CaptainTheme.mutedText,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        if (crew.isAltActive) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  CaptainTheme.warning.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Alternative crew active',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: CaptainTheme.warning,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        for (var i = 0; i < members.length; i++) ...[
                          _CrewMemberTile(member: members[i]),
                          if (i != members.length - 1)
                            const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrewMemberTile extends StatelessWidget {
  const _CrewMemberTile({required this.member});

  final OperatorTripCrewMember member;

  @override
  Widget build(BuildContext context) {
    final statusText = member.attendanceStatus?.trim().isNotEmpty == true
        ? member.attendanceStatus!
        : (member.isPresent ? 'Present' : 'Absent');
    final statusColor =
        member.isPresent ? CaptainTheme.success : CaptainTheme.danger;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          CrewAvatar(
              member: member,
              size: 48,
              borderWidth: 2,
              borderColor: CaptainTheme.surface),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: CaptainTheme.strongText,
                  ),
                ),
                const SizedBox(height: 3),
                if (member.roleLabel.isNotEmpty)
                  Text(
                    member.roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CaptainTheme.mutedText,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Collection-type badge. Only the two meaningful header badges remain as
/// containers; vehicle, waste and time are plain icon/text metadata.
class _CollectionTypePill extends StatelessWidget {
  const _CollectionTypePill({
    required this.collectionType,
    required this.compact,
  });

  final String? collectionType;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(collectionType);
    if (style.label == null) return const SizedBox.shrink();

    final label = compact ? style.compactLabel : style.label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          fontSize: compact ? 9.5 : 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
          color: style.foreground,
          height: 1.05,
        ),
      ),
    );
  }

  _CollectionBadgeStyle _styleFor(String? type) {
    switch (type) {
      case 'bin_collection':
        return const _CollectionBadgeStyle(
          label: 'Bin Collection',
          compactLabel: 'Bin',
          background: Color(0xFFDBEAFE),
          foreground: Color(0xFF1E40AF),
        );
      case 'household_collection':
        return const _CollectionBadgeStyle(
          label: 'Household Collection',
          compactLabel: 'Household',
          background: Color(0xFFDCFCE7),
          foreground: Color(0xFF166534),
        );
      case 'bulk_waste_collection':
        return const _CollectionBadgeStyle(
          label: 'Bulk Waste Collection',
          compactLabel: 'Bulk Waste',
          background: Color(0xFFFEF3C7),
          foreground: Color(0xFF92400E),
        );
      default:
        return const _CollectionBadgeStyle(
          label: null,
          compactLabel: null,
          background: Colors.transparent,
          foreground: Colors.transparent,
        );
    }
  }
}

class _CollectionBadgeStyle {
  const _CollectionBadgeStyle({
    required this.label,
    required this.compactLabel,
    required this.background,
    required this.foreground,
  });

  final String? label;
  final String? compactLabel;
  final Color background;
  final Color foreground;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sequential-trip lock
// ─────────────────────────────────────────────────────────────────────────────

/// Luminance-preserving greyscale (Rec. 601 weights). Drains a locked trip's
/// colour without darkening it, so it stays readable in both themes.
const List<double> _greyscaleMatrix = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Greys out and disables anything belonging to a locked trip — the stop list,
/// the household list. Same treatment as the locked trip card, so the whole
/// screen reads as one state rather than a card that disagrees with its list.
class _LockedContent extends StatelessWidget {
  const _LockedContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.5,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(_greyscaleMatrix),
          child: child,
        ),
      ),
    );
  }
}

/// The padlock badge floated over a locked trip card.
class _LockChip extends StatelessWidget {
  const _LockChip({required this.blocker});

  final TripBlocker blocker;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CaptainTheme.strongText.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 15,
            color: CaptainTheme.surface,
          ),
          const SizedBox(width: 7),
          Text(
            'Locked',
            style: TextStyle(
              color: CaptainTheme.surface,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width explainer under the quick actions when the SELECTED trip is
/// locked. The chip on the card says *that* it's locked; this says *why* and
/// what to do about it.
class _LockedTripBanner extends StatelessWidget {
  const _LockedTripBanner({required this.blocker});

  final TripBlocker blocker;

  @override
  Widget build(BuildContext context) {
    final progress = blocker.blockedBy.progress;

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
          Icon(Icons.lock_clock_rounded, size: 19, color: CaptainTheme.gold),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This trip is not open yet',
                  style: TextStyle(
                    color: CaptainTheme.strongText,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  blocker.message,
                  style: TextStyle(
                    color: CaptainTheme.mutedText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                if (progress.total > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${progress.resolved} of ${progress.total} stops done on that trip',
                    style: TextStyle(
                      color: CaptainTheme.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero trip card
// ─────────────────────────────────────────────────────────────────────────────

class _TripHeroCard extends StatelessWidget {
  const _TripHeroCard({
    required this.trip,
    required this.onOpenMap,
    this.blocker,
    this.index,
    this.total,
  });

  final OperatorTripToday trip;
  final VoidCallback onOpenMap;

  /// Non-null when an earlier same-type trip has to be finished first. The card
  /// then renders desaturated behind a lock chip and stops opening the map —
  /// there is nothing on it the driver can act on yet.
  final TripBlocker? blocker;

  /// Position in the day's carousel, for the "Trip 2 of 3" counter. Omitted
  /// when the card is shown on its own.
  final int? index;
  final int? total;

  bool get _locked => blocker != null;

  Color get _statusColor {
    switch (trip.status.toLowerCase()) {
      case 'completed':
        return CaptainTheme.success;
      case 'in progress':
        return CaptainTheme.gold;
      case 'cancelled':
        return CaptainTheme.danger;
      default:
        return CaptainTheme.info;
    }
  }

  Color get _typeTint {
    switch (trip.collectionType) {
      case 'household_collection':
        return CaptainTheme.success;
      case 'bulk_waste_collection':
        return CaptainTheme.gold;
      case 'bin_collection':
      default:
        return CaptainTheme.accent;
    }
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final parts = raw.split(':');
    if (parts.length < 2) return raw;
    final hh = int.tryParse(parts[0]);
    final mm = int.tryParse(parts[1]);
    if (hh == null || mm == null) return raw;
    return DateFormat.jm().format(DateTime(2000, 1, 1, hh, mm));
  }

  @override
  Widget build(BuildContext context) {
    final card = _buildCard(context);
    if (!_locked) return card;

    // Locked: drain the colour so the live card next to it is unmistakably the
    // one to work on, and swallow taps (IgnorePointer) so the map/crew actions
    // inside can't be reached. Opacity is applied on top of the greyscale so the
    // card still reads as "yours, later" rather than "disabled forever".
    return Semantics(
      label: 'Locked trip. ${blocker!.message}',
      child: Stack(
        children: [
          IgnorePointer(
            child: Opacity(
              opacity: 0.55,
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(_greyscaleMatrix),
                child: card,
              ),
            ),
          ),
          Positioned.fill(
            child: Center(child: _LockChip(blocker: blocker!)),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final progress = trip.progress;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 315;
        final veryNarrow = constraints.maxWidth < 280;
        final ringSize = veryNarrow ? 52.0 : 56.0;

        return CaptainGlassCard(
          onTap: onOpenMap,
          tint: _typeTint,
          padding: EdgeInsets.fromLTRB(
            veryNarrow ? 10 : 13,
            15,
            veryNarrow ? 10 : 12,
            20,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(19)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: compact type + quieter status + secondary date.
              Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (trip.crew != null &&
                            (trip.crew!.driver != null ||
                                trip.crew!.operator != null)) ...[
                          CrewAvatarStack(
                            crew: trip.crew!,
                            onTap: () => _showCrewDialog(context, trip.crew!),
                            borderColor: CaptainTheme.surface,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          flex: 3,
                          child: _CollectionTypePill(
                            collectionType: trip.collectionType,
                            compact: narrow,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          flex: 2,
                          child: _TripStatusPill(
                            status: trip.status,
                            color: _statusColor,
                            compact: veryNarrow,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    // With several trips in a day the date alone doesn't say
                    // which card you're on; the counter does.
                    (index != null && total != null && total! > 1)
                        ? 'Trip ${index! + 1} of $total'
                        : DateFormat(narrow ? 'd MMM' : 'EEE, d MMM')
                            .format(trip.tripDate),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      fontSize: narrow ? 9.5 : 10.5,
                      fontWeight: FontWeight.w600,
                      color: CaptainTheme.mutedText,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // One compact content row. The left side may naturally gain a
              // metadata line on narrow devices; because the card is
              // content-sized, its height grows only when it genuinely needs to.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.areaName,
                          maxLines: veryNarrow ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: veryNarrow ? 15 : 16.5,
                            fontWeight: FontWeight.w800,
                            color: CaptainTheme.strongText,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 7,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (trip.vehicle != null)
                              _CompactInfoItem(
                                icon: Icons.local_shipping_rounded,
                                text: trip.vehicle!.vehicleNo,
                                maxTextWidth: veryNarrow ? 76 : 108,
                              ),
                            _CompactInfoItem(
                              icon: Icons.schedule_rounded,
                              text: _formatTime(trip.scheduledTime),
                              maxTextWidth: 72,
                            ),
                            if (trip.wasteType.name.isNotEmpty)
                              _CompactInfoItem(
                                icon: Icons.recycling_rounded,
                                text: trip.wasteType.name,
                                maxTextWidth: veryNarrow ? 92 : 128,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CompactTripProgress(
                    fraction: progress.resolvedFraction,
                    completed: progress.completed,
                    label: '${progress.resolved}/${progress.total}',
                    size: ringSize,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TripStatusPill extends StatelessWidget {
  const _TripStatusPill({
    required this.status,
    required this.color,
    required this.compact,
  });

  final String status;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 7,
        vertical: 2.5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        status.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: compact ? 8.3 : 8.8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: color,
          height: 1.05,
        ),
      ),
    );
  }
}

/// Plain icon and text. No individual chip background, border or padding.
class _CompactInfoItem extends StatelessWidget {
  const _CompactInfoItem({
    required this.icon,
    required this.text,
    required this.maxTextWidth,
  });

  final IconData icon;
  final String text;
  final double maxTextWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: CaptainTheme.accent),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxTextWidth),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
              color: CaptainTheme.strongText,
              height: 1.05,
            ),
          ),
        ),
      ],
    );
  }
}

/// Fully controlled progress ring with no hidden padding or minimum height.
class _CompactTripProgress extends StatelessWidget {
  const _CompactTripProgress({
    required this.fraction,
    required this.completed,
    required this.label,
    required this.size,
  });

  final double fraction;
  final bool completed;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = completed ? CaptainTheme.success : CaptainTheme.accent;
    final safeFraction = fraction.clamp(0.0, 1.0).toDouble();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: safeFraction,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              backgroundColor: CaptainTheme.hairline.withValues(alpha: 0.65),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: size - 16,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: CaptainTheme.strongText,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  completed ? 'DONE' : 'STOPS',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.35,
                    color: CaptainTheme.mutedText,
                    height: 1.0,
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

// ─────────────────────────────────────────────────────────────────────────────
// Quick actions
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.onOpenMap,
    required this.onScan,
    required this.onHistory,
  });

  final VoidCallback onOpenMap;

  /// Null when the selected trip is locked — the scanner is dimmed rather than
  /// removed, so the row keeps its shape and the driver sees the action exists.
  final VoidCallback? onScan;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    Widget action({
      required String iconAsset,
      required String label,
      required VoidCallback? onTap,
    }) {
      final disabled = onTap == null;
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Opacity(
              opacity: disabled ? 0.4 : 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    iconAsset,
                    width: 76,
                    height: 76,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: CaptainTheme.strongText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        action(
          iconAsset: 'assets/icons/navigate.png',
          label: 'Navigate',
          onTap: onOpenMap,
        ),
        const SizedBox(width: 10),
        action(
          iconAsset: 'assets/icons/scan.png',
          label: 'Scan',
          onTap: onScan,
        ),
        const SizedBox(width: 10),
        action(
          iconAsset: 'assets/icons/history.png',
          label: 'History',
          onTap: onHistory,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stops timeline
// ─────────────────────────────────────────────────────────────────────────────

class _StopsTimeline extends StatelessWidget {
  const _StopsTimeline({
    required this.trip,
    required this.onChanged,
    this.locked = false,
  });

  final OperatorTripToday trip;
  final Future<void> Function() onChanged;

  /// The stops still render when the trip is locked — the driver can see what
  /// is coming — but greyed and inert, matching the trip card above.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final timeline = _buildTimeline(context);
    return locked ? _LockedContent(child: timeline) : timeline;
  }

  Widget _buildTimeline(BuildContext context) {
    final stops = [...trip.collectionPoints]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    if (stops.isEmpty) {
      return CaptainGlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/no_assignments.png',
              height: 150,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 10),
            Text(
              'No collection points on this trip yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CaptainTheme.mutedText),
            ),
          ],
        ),
      );
    }

    // First pending stop is the "next up" highlight.
    final nextIndex = stops.indexWhere((s) => !s.isCollected);

    return Column(
      children: [
        for (var i = 0; i < stops.length; i++)
          _StopTile(
            stop: stops[i],
            isFirst: i == 0,
            isLast: i == stops.length - 1,
            isNext: i == nextIndex,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.stop,
    required this.isFirst,
    required this.isLast,
    required this.isNext,
    required this.onChanged,
  });

  final OperatorTripCollectionPoint stop;
  final bool isFirst;
  final bool isLast;
  final bool isNext;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final statusTone = _statusTone;
    final done = statusTone == _StopTone.collected;
    final skipped = statusTone == _StopTone.skipped;
    final missed = statusTone == _StopTone.missed;
    final nodeColor = switch (statusTone) {
      _StopTone.collected => CaptainTheme.success,
      _StopTone.skipped => CaptainTheme.danger,
      _StopTone.missed => CaptainTheme.danger,
      _StopTone.next => CaptainTheme.gold,
      _StopTone.pending => CaptainTheme.hairline,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2.4,
                    color: isFirst
                        ? Colors.transparent
                        : CaptainTheme.hairline.withValues(alpha: 0.8),
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? CaptainTheme.success : CaptainTheme.surface,
                    border: Border.all(color: nodeColor, width: 2.4),
                    boxShadow: isNext && !skipped && !missed
                        ? [
                            BoxShadow(
                              color: CaptainTheme.gold.withValues(alpha: 0.45),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: done
                      ? Icon(Icons.check_rounded,
                          size: 14, color: CaptainTheme.onAccent)
                      : skipped
                          ? Icon(Icons.schedule_rounded,
                              size: 12, color: CaptainTheme.danger)
                          : missed
                              ? Icon(Icons.report_gmailerrorred_rounded,
                                  size: 12, color: CaptainTheme.danger)
                              : (isNext
                                  ? Icon(Icons.arrow_downward_rounded,
                                      size: 12, color: CaptainTheme.gold)
                                  : null),
                ),
                Expanded(
                  child: Container(
                    width: 2.4,
                    color: isLast
                        ? Colors.transparent
                        : CaptainTheme.hairline.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: CaptainGlassCard(
                onTap: done ? null : () => _openWeightEntry(context),
                tint: done
                    ? CaptainTheme.success
                    : (skipped || missed)
                        ? CaptainTheme.danger
                        : (isNext ? CaptainTheme.gold : null),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.collectionPoint.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: CaptainTheme.strongText,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            done
                                ? 'Collected'
                                    '${stop.collectedWeightKg != null ? ' • ${stop.collectedWeightKg!.toStringAsFixed(1)} kg' : ''}'
                                    '${stop.collectedAt != null ? ' • ${TimeOfDay.fromDateTime(stop.collectedAt!.toLocal()).format(context)}' : ''}'
                                : skipped
                                    ? 'Collect later'
                                    : missed
                                        ? 'Not available'
                                        : (isNext
                                            ? 'Next stop — tap to enter weight'
                                            : 'Stop ${stop.sequence} • ${stop.bin.binName}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: done
                                  ? CaptainTheme.success
                                  : (skipped || missed)
                                      ? CaptainTheme.danger
                                      : (isNext
                                          ? CaptainTheme.gold
                                          : CaptainTheme.mutedText),
                            ),
                          ),
                          if (!done &&
                              stop.statusReason != null &&
                              stop.statusReason!.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              stop.statusReason!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: skipped || missed
                                    ? CaptainTheme.danger
                                    : CaptainTheme.mutedText,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      done
                          ? Icons.verified_rounded
                          : (skipped || missed)
                              ? Icons.error_outline_rounded
                              : Icons.chevron_right_rounded,
                      color: done
                          ? CaptainTheme.success
                          : (skipped || missed)
                              ? CaptainTheme.danger
                              : CaptainTheme.mutedText,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Validate this stop's bin against today's trip, open the weight-entry
  /// sheet, then refresh the dashboard when a collection is submitted.
  Future<void> _openWeightEntry(BuildContext context) async {
    final repo = GetIt.instance<OperatorTripRepository>();

    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: CaptainTheme.accent),
      ),
    );

    BinScanValidateResult? validation;
    String? errorText;
    try {
      validation = await repo.validateBinQr(stop.bin.scanValue);
    } on OperatorTripException catch (e) {
      errorText = friendlyTripError(e);
    } catch (e) {
      errorText = 'Could not load bin: $e';
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialogFuture.catchError((_) {});

    if (errorText != null) {
      if (context.mounted) AppFlash.error(context, errorText);
      return;
    }
    if (validation == null || !context.mounted) return;

    final result = await showModalBottomSheet<BinScanSubmitResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BinDetailSheet(validation: validation!),
    );
    if (result != null) {
      if (result.tripCompleted && context.mounted) {
        AppFlash.success(
            context, 'Trip completed — all stops collected. Great job!');
      }
      await onChanged();
    }
  }

  _StopTone get _statusTone {
    if (stop.isCollected) return _StopTone.collected;
    switch (stop.status.toLowerCase()) {
      case 'skipped':
        return _StopTone.skipped;
      case 'missed':
        return _StopTone.missed;
      default:
        return isNext ? _StopTone.next : _StopTone.pending;
    }
  }
}

enum _StopTone {
  collected,
  skipped,
  missed,
  next,
  pending,
}

// ─────────────────────────────────────────────────────────────────────────────
// Household stops (household / bulk-waste trips) — same timeline look as the
// bin collection points, but each tile is a customer and the collect method is
// the household weight-capture screen instead of a bin scan.
// ─────────────────────────────────────────────────────────────────────────────

class _HouseholdTimeline extends StatelessWidget {
  const _HouseholdTimeline({
    required this.trip,
    required this.onChanged,
    this.locked = false,
  });

  final OperatorTripToday trip;
  final Future<void> Function() onChanged;

  /// See [_StopsTimeline.locked] — visible but inert while an earlier same-type
  /// trip is still open.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final timeline = _buildTimeline(context);
    return locked ? _LockedContent(child: timeline) : timeline;
  }

  Widget _buildTimeline(BuildContext context) {
    final stops = [...trip.householdCollections]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    if (stops.isEmpty) {
      return CaptainGlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/no_assignments.png',
              height: 150,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 10),
            Text(
              'No households on this trip yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CaptainTheme.mutedText),
            ),
          ],
        ),
      );
    }

    final nextIndex = stops.indexWhere((s) => !s.isCollected);

    return Column(
      children: [
        for (var i = 0; i < stops.length; i++)
          _HouseholdTile(
            stop: stops[i],
            assignmentId: trip.assignmentUniqueId,
            isFirst: i == 0,
            isLast: i == stops.length - 1,
            isNext: i == nextIndex,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

class _HouseholdTile extends StatelessWidget {
  const _HouseholdTile({
    required this.stop,
    required this.assignmentId,
    required this.isFirst,
    required this.isLast,
    required this.isNext,
    required this.onChanged,
  });

  final OperatorTripHouseholdStop stop;
  final String assignmentId;
  final bool isFirst;
  final bool isLast;
  final bool isNext;
  final Future<void> Function() onChanged;

  _StopTone get _tone {
    if (stop.isCollected) return _StopTone.collected;
    switch (stop.status.toLowerCase()) {
      case 'collect later':
      case 'skipped':
        return _StopTone.skipped;
      case 'not available':
      case 'missed':
      case 'not collected':
        return _StopTone.missed;
      default:
        return isNext ? _StopTone.next : _StopTone.pending;
    }
  }

  // Premium violet accent — households get a purple identity, distinct from the
  // blue/gold bin collection points.
  static const Color _accent = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) {
    final tone = _tone;
    final done = tone == _StopTone.collected;
    final skipped = tone == _StopTone.skipped;
    final missed = tone == _StopTone.missed;
    final nodeColor = switch (tone) {
      _StopTone.collected => CaptainTheme.success,
      _StopTone.skipped => CaptainTheme.warning, // collect later → amber
      _StopTone.missed => CaptainTheme.danger, // not available → red
      _StopTone.next => _accent,
      _StopTone.pending => _accent.withValues(alpha: 0.55),
    };
    // Status color drives the card tint, subtitle and trailing icon:
    // green = collected, amber = collect later, red = not available, purple
    // otherwise (next / pending).
    final statusColor = switch (tone) {
      _StopTone.collected => CaptainTheme.success,
      _StopTone.skipped => CaptainTheme.warning,
      _StopTone.missed => CaptainTheme.danger,
      _StopTone.next => _accent,
      _StopTone.pending => _accent,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail (mirrors the bin stop tile).
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2.4,
                    color: isFirst
                        ? Colors.transparent
                        : CaptainTheme.hairline.withValues(alpha: 0.8),
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? CaptainTheme.success : CaptainTheme.surface,
                    border: Border.all(color: nodeColor, width: 2.4),
                    boxShadow: isNext && !skipped && !missed
                        ? [
                            BoxShadow(
                              color: _accent.withValues(alpha: 0.5),
                              blurRadius: 9,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: done
                      ? Icon(Icons.check_rounded,
                          size: 14, color: CaptainTheme.onAccent)
                      : Icon(Icons.home_rounded, size: 11, color: nodeColor),
                ),
                Expanded(
                  child: Container(
                    width: 2.4,
                    color: isLast
                        ? Colors.transparent
                        : CaptainTheme.hairline.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: CaptainGlassCard(
                onTap: () => _openHouseholdCollection(context),
                // green = collected · amber = collect later · red = not
                // available · purple = pending/next.
                tint: statusColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: CaptainTheme.strongText,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            done
                                ? 'Collected'
                                    '${stop.collectedWeightKg != null ? ' • ${stop.collectedWeightKg!.toStringAsFixed(1)} kg' : ''}'
                                    '${stop.collectedAt != null ? ' • ${TimeOfDay.fromDateTime(stop.collectedAt!.toLocal()).format(context)}' : ''}'
                                : skipped
                                    ? 'Collect later'
                                    : missed
                                        ? 'Not available'
                                        : (isNext
                                            ? 'Next household — tap to collect'
                                            : (stop.address ??
                                                'Household ${stop.sequence}')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: tone == _StopTone.pending
                                  ? CaptainTheme.mutedText
                                  : statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      done
                          ? Icons.verified_rounded
                          : (skipped || missed)
                              ? Icons.error_outline_rounded
                              : Icons.chevron_right_rounded,
                      color: statusColor,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Open the customer action drawer (Collect / Collect later / Not available)
  /// — the same sheet the QR scan shows — then ALWAYS refresh the list so the
  /// tile reflects the backend (turns green when collected, red/orange when
  /// not-available / collect-later). We refresh unconditionally because the
  /// collect screen's return value isn't reliable (back button vs "Back to
  /// home" return different things), and the source of truth is the backend.
  Future<void> _openHouseholdCollection(BuildContext context) async {
    await showHouseholdActionSheet(
      context,
      customerId: stop.customerUniqueId,
      customerName: stop.customerName,
      contactNo: stop.contactNo ?? '',
      latitude: stop.latitude?.toString() ?? '',
      longitude: stop.longitude?.toString() ?? '',
      assignmentId: assignmentId,
      currentStatus: stop.isCollected ? 'collected' : stop.status,
    );
    await onChanged();
  }
}

/// Human-friendly messages for the operator-mobile error codes.
String friendlyTripError(OperatorTripException e) {
  switch (e.code) {
    case 'WRONG_WASTE_TYPE':
      return e.message;
    case 'WRONG_PANCHAYAT':
      return 'This bin is outside your assigned area.';
    case 'ALREADY_COLLECTED':
      return 'This bin was already collected.';
    case 'BIN_NOT_FOUND':
      return 'Bin not found.';
    case 'CP_NOT_IN_TRIP':
      return 'This collection point is not in your trip.';
    case 'NO_ACTIVE_TRIP':
      return 'You have no active trip today.';
    case 'NETWORK_UNREACHABLE':
    case 'NETWORK_TIMEOUT':
    case 'NETWORK_ERROR':
      return 'Cannot reach the server. Check your connection.';
    default:
      return e.message.isEmpty ? 'Something went wrong.' : e.message;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared bits
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: CaptainTheme.strongText,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: CaptainTheme.mutedText,
            ),
          ),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    this.icon,
    this.iconColor,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.imageAsset,
  });

  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  /// Optional illustration shown instead of the icon chip (e.g. the
  /// "no assignments" artwork on the empty trip state).
  final String? imageAsset;

  @override
  Widget build(BuildContext context) {
    // A ListView so pull-to-refresh still works on empty/error states.
    return RefreshIndicator(
      color: CaptainTheme.accent,
      onRefresh: onAction,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 90, 32, 32),
        children: [
          Center(
            child: CaptainGlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (imageAsset != null)
                    Image.asset(
                      imageAsset!,
                      height: 180,
                      fit: BoxFit.contain,
                    )
                  else if (icon != null)
                    CaptainGlassChip(
                        icon: icon!,
                        color: iconColor ?? CaptainTheme.accent,
                        size: 30,
                        padding: const EdgeInsets.all(14)),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: CaptainTheme.strongText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: CaptainTheme.mutedText,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: onAction,
                    icon: Icon(Icons.refresh_rounded, size: 18),
                    label: Text(actionLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CaptainTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
