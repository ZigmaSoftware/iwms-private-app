import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';

class CollectionProgressMeter extends StatefulWidget {
  const CollectionProgressMeter({
    super.key,
    required this.collectionPoints,

    /// Live progress between the previous completed stop and the next stop.
    ///
    /// Expected value:
    /// 0.0 = vehicle is at the previous stop
    /// 0.5 = vehicle is halfway to the next stop
    /// 1.0 = vehicle has reached the next stop
    this.currentLegProgress = 0.0,

    /// Set this to true only when currentLegProgress is calculated using
    /// current GPS or live backend data.
    this.hasLiveLocation = false,

    /// Controls the online/offline status shown in the header.
    this.vehicleOnline = true,

    /// Optional route information.
    this.etaText,
    this.distanceText,
    this.lastUpdatedText,

    /// Existing vehicle GIF or another compatible image asset.
    this.vehicleAsset = 'assets/gif/progressicon.gif',

    /// Optional external collection-point action.
    ///
    /// When this is null, the component opens its own bottom sheet.
    this.onCollectionPointTap,
    this.title = 'Route progress',
  });

  final List<OperatorTripCollectionPoint> collectionPoints;

  final double currentLegProgress;
  final bool hasLiveLocation;
  final bool vehicleOnline;

  final String? etaText;
  final String? distanceText;
  final String? lastUpdatedText;

  final String vehicleAsset;
  final String title;

  final ValueChanged<OperatorTripCollectionPoint>? onCollectionPointTap;

  @override
  State<CollectionProgressMeter> createState() =>
      _CollectionProgressMeterState();
}

class _CollectionProgressMeterState extends State<CollectionProgressMeter>
    with SingleTickerProviderStateMixin {
  static const double _railHeight = 118;
  static const double _nodeSpacing = 126;
  static const double _railStart = 42;
  static const double _railY = 49;
  static const double _nodeSize = 24;
  static const double _vehicleSize = 34;
  static const double _horizontalPadding = 18;

  late final AnimationController _vehicleController;
  late final ScrollController _scrollController;

  double _fromLegProgress = 0;
  double _toLegProgress = 0;

  int? _lastCenteredIndex;

  @override
  void initState() {
    super.initState();

    final initialProgress = _normalizedProgress(
      widget.currentLegProgress,
    );

    _fromLegProgress = initialProgress;
    _toLegProgress = initialProgress;

    _vehicleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
      value: 1,
    );

    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant CollectionProgressMeter oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldActiveSequence = _activeStopSequence(
      oldWidget.collectionPoints,
    );

    final newActiveSequence = _activeStopSequence(
      widget.collectionPoints,
    );

    final activeStopChanged = oldActiveSequence != newActiveSequence;

    final newTarget = _normalizedProgress(
      widget.currentLegProgress,
    );

    final currentDisplayedProgress = _currentAnimatedLegProgress();

    /*
     * When the next stop changes, a new leg has started.
     * Therefore, movement begins from 0.0 for the new leg.
     */
    if (activeStopChanged) {
      _fromLegProgress = 0;
      _toLegProgress = newTarget;

      _startVehicleAnimation();
      return;
    }

    /*
     * A lower progress value usually means GPS correction or backend
     * correction. Snap directly instead of making the vehicle appear
     * to drive backwards.
     */
    if (newTarget < currentDisplayedProgress) {
      _fromLegProgress = newTarget;
      _toLegProgress = newTarget;
      _vehicleController.value = 1;
      return;
    }

    if ((newTarget - currentDisplayedProgress).abs() < 0.001) {
      return;
    }

    /*
     * Animate only from the previously displayed location to the
     * newly received location.
     */
    _fromLegProgress = currentDisplayedProgress;
    _toLegProgress = newTarget;

    _startVehicleAnimation();
  }

  @override
  void dispose() {
    _vehicleController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startVehicleAnimation() {
    if ((_toLegProgress - _fromLegProgress).abs() < 0.001) {
      _vehicleController.value = 1;
      return;
    }

    _vehicleController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final stops = [...widget.collectionPoints]..sort(
        (a, b) => a.sequence.compareTo(b.sequence),
      );

    if (stops.isEmpty) {
      return const SizedBox.shrink();
    }

    final nextIndex = stops.indexWhere(
      (stop) => !stop.isCollected,
    );

    final allCompleted = nextIndex == -1;

    final activeIndex = allCompleted ? stops.length - 1 : nextIndex;

    final completedCount = stops.where((stop) => stop.isCollected).length;

    final nextStop = allCompleted ? null : stops[activeIndex];

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProgressHeader(
          title: widget.title,
          completedCount: completedCount,
          totalCount: stops.length,
          nextStop: nextStop,
          allCompleted: allCompleted,
          vehicleOnline: widget.vehicleOnline,
          hasLiveLocation: widget.hasLiveLocation,
          etaText: widget.etaText,
          distanceText: widget.distanceText,
          lastUpdatedText: widget.lastUpdatedText,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;

            final minimumContentWidth =
                (_railStart * 2) + (_nodeSpacing * (stops.length - 1));

            final contentWidth = math
                .max(
                  viewportWidth - (_horizontalPadding * 2),
                  minimumContentWidth,
                )
                .toDouble();

            _scheduleActiveStopCentering(
              activeIndex: activeIndex,
              viewportWidth: viewportWidth,
            );

            return SizedBox(
              height: _railHeight,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: _horizontalPadding,
                ),
                child: SizedBox(
                  width: contentWidth,
                  height: _railHeight,
                  child: AnimatedBuilder(
                    animation: _vehicleController,
                    builder: (context, _) {
                      final legProgress = reduceMotion
                          ? _toLegProgress
                          : _currentAnimatedLegProgress();

                      final routeValues = _calculateRouteValues(
                        stops: stops,
                        nextIndex: nextIndex,
                        activeIndex: activeIndex,
                        legProgress: legProgress,
                      );

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ProgressRailPainter(
                                stopCount: stops.length,
                                railStart: _railStart,
                                railY: _railY,
                                nodeSpacing: _nodeSpacing,
                                completedEndX: routeValues.completedEndX,
                                activeStartX: routeValues.activeStartX,
                                activeProgressX: routeValues.vehicleX,
                                hasActiveSegment: routeValues.hasActiveSegment,
                                completedColor: CaptainTheme.success,
                                activeColor: CaptainTheme.accent,
                                pendingColor: CaptainTheme.hairline,
                              ),
                            ),
                          ),

                          /*
                           * Vehicle remains at the last known position.
                           * It only changes position when
                           * currentLegProgress changes.
                           */
                          if (stops.length > 1 || !allCompleted)
                            Positioned(
                              left: routeValues.vehicleX - (_vehicleSize / 2),
                              top: _railY - 45,
                              width: _vehicleSize,
                              height: _vehicleSize,
                              child: _VehicleIndicator(
                                assetPath: widget.vehicleAsset,
                                vehicleOnline: widget.vehicleOnline,
                                hasLiveLocation: widget.hasLiveLocation,
                              ),
                            ),
                          for (var index = 0; index < stops.length; index++)
                            _StopNode(
                              key: ValueKey(
                                'collection-stop-${stops[index].sequence}',
                              ),
                              stop: stops[index],
                              left: _nodeX(index) - 38,
                              top: _railY - (_nodeSize / 2),
                              size: _nodeSize,
                              isNext: !allCompleted && index == activeIndex,
                              reduceMotion: reduceMotion,
                              onTap: () {
                                _handleStopTap(
                                  stop: stops[index],
                                  isNext: !allCompleted && index == activeIndex,
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  _RouteValues _calculateRouteValues({
    required List<OperatorTripCollectionPoint> stops,
    required int nextIndex,
    required int activeIndex,
    required double legProgress,
  }) {
    final allCompleted = nextIndex == -1;

    if (allCompleted) {
      final finalNodeX = _nodeX(stops.length - 1);

      return _RouteValues(
        completedEndX: finalNodeX,
        activeStartX: finalNodeX,
        vehicleX: finalNodeX,
        hasActiveSegment: false,
      );
    }

    final lastCompletedIndex = nextIndex - 1;

    final completedEndX =
        lastCompletedIndex >= 0 ? _nodeX(lastCompletedIndex) : _nodeX(0);

    /*
     * When the first stop itself is pending, there is no previous
     * collection-point node. The vehicle is placed at CP 1.
     */
    if (nextIndex == 0) {
      return _RouteValues(
        completedEndX: _nodeX(0),
        activeStartX: _nodeX(0),
        vehicleX: _nodeX(0),
        hasActiveSegment: false,
      );
    }

    final activeStartX = _nodeX(nextIndex - 1);
    final activeEndX = _nodeX(activeIndex);

    final vehicleX = activeStartX + ((activeEndX - activeStartX) * legProgress);

    return _RouteValues(
      completedEndX: completedEndX,
      activeStartX: activeStartX,
      vehicleX: vehicleX,
      hasActiveSegment: true,
    );
  }

  double _nodeX(int index) {
    return _railStart + (index * _nodeSpacing);
  }

  double _normalizedProgress(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _currentAnimatedLegProgress() {
    final easedValue = Curves.easeOutCubic.transform(
      _vehicleController.value,
    );

    return _fromLegProgress +
        ((_toLegProgress - _fromLegProgress) * easedValue);
  }

  int? _activeStopSequence(
    List<OperatorTripCollectionPoint> points,
  ) {
    if (points.isEmpty) {
      return null;
    }

    final sorted = [...points]..sort(
        (a, b) => a.sequence.compareTo(b.sequence),
      );

    final nextIndex = sorted.indexWhere(
      (point) => !point.isCollected,
    );

    if (nextIndex == -1) {
      return null;
    }

    return sorted[nextIndex].sequence;
  }

  void _scheduleActiveStopCentering({
    required int activeIndex,
    required double viewportWidth,
  }) {
    if (_lastCenteredIndex == activeIndex) {
      return;
    }

    _lastCenteredIndex = activeIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      final nodePosition = _horizontalPadding + _nodeX(activeIndex);

      final requestedOffset = nodePosition - (viewportWidth / 2);

      final maximumOffset = _scrollController.position.maxScrollExtent;

      final targetOffset = requestedOffset.clamp(0.0, maximumOffset).toDouble();

      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;

      if (reduceMotion) {
        _scrollController.jumpTo(targetOffset);
        return;
      }

      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _handleStopTap({
    required OperatorTripCollectionPoint stop,
    required bool isNext,
  }) {
    if (widget.onCollectionPointTap != null) {
      widget.onCollectionPointTap!(stop);
      return;
    }

    _showStopDetailsBottomSheet(
      stop: stop,
      isNext: isNext,
    );
  }

  Future<void> _showStopDetailsBottomSheet({
    required OperatorTripCollectionPoint stop,
    required bool isNext,
  }) {
    final visualState = _resolveStopVisualState(
      stop: stop,
      isNext: isNext,
    );

    final weight = stop.collectedWeightKg == null
        ? 'Not recorded'
        : '${stop.collectedWeightKg!.toStringAsFixed(1)} kg';

    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: CaptainTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) {
        final details = <Widget>[
          _DetailTile(
            icon: Icons.flag_rounded,
            label: 'Status',
            value: visualState.label,
            color: visualState.color,
          ),
          _DetailTile(
            icon: Icons.scale_rounded,
            label: 'Collected weight',
            value: weight,
          ),
        ];

        if (isNext && widget.etaText?.trim().isNotEmpty == true) {
          details.add(
            _DetailTile(
              icon: Icons.schedule_rounded,
              label: 'Estimated arrival',
              value: widget.etaText!.trim(),
              color: CaptainTheme.gold,
            ),
          );
        }

        if (isNext && widget.distanceText?.trim().isNotEmpty == true) {
          details.add(
            _DetailTile(
              icon: Icons.route_rounded,
              label: 'Remaining distance',
              value: widget.distanceText!.trim(),
              color: CaptainTheme.accent,
            ),
          );
        }

        details.add(
          _DetailTile(
            icon: widget.vehicleOnline
                ? Icons.gps_fixed_rounded
                : Icons.location_off_rounded,
            label: 'Vehicle location',
            value: _vehicleLocationLabel(),
            color: widget.vehicleOnline && widget.hasLiveLocation
                ? CaptainTheme.success
                : CaptainTheme.mutedText,
          ),
        );

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: visualState.color.withValues(
                        alpha: 0.12,
                      ),
                    ),
                    child: Icon(
                      visualState.icon,
                      color: visualState.color,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CP ${stop.sequence}',
                          style: TextStyle(
                            color: CaptainTheme.strongText,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          stop.collectionPoint.name,
                          style: TextStyle(
                            color: CaptainTheme.mutedText,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...details,
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  String _vehicleLocationLabel() {
    if (!widget.vehicleOnline) {
      return 'Vehicle offline';
    }

    if (!widget.hasLiveLocation) {
      return 'Live location unavailable';
    }

    final updatedText = widget.lastUpdatedText?.trim();

    if (updatedText == null || updatedText.isEmpty) {
      return 'Live';
    }

    return updatedText;
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.title,
    required this.completedCount,
    required this.totalCount,
    required this.nextStop,
    required this.allCompleted,
    required this.vehicleOnline,
    required this.hasLiveLocation,
    required this.etaText,
    required this.distanceText,
    required this.lastUpdatedText,
  });

  final String title;
  final int completedCount;
  final int totalCount;

  final OperatorTripCollectionPoint? nextStop;
  final bool allCompleted;

  final bool vehicleOnline;
  final bool hasLiveLocation;

  final String? etaText;
  final String? distanceText;
  final String? lastUpdatedText;

  @override
  Widget build(BuildContext context) {
    final statusLabel = allCompleted
        ? 'Route completed'
        : !vehicleOnline
            ? 'Vehicle offline'
            : hasLiveLocation
                ? 'Live'
                : 'Location unavailable';

    final statusColor = allCompleted
        ? CaptainTheme.success
        : !vehicleOnline
            ? Colors.red.shade600
            : hasLiveLocation
                ? CaptainTheme.success
                : CaptainTheme.mutedText;

    final metaParts = <String>[];

    if (!allCompleted && etaText?.trim().isNotEmpty == true) {
      metaParts.add('ETA ${etaText!.trim()}');
    }

    if (!allCompleted && distanceText?.trim().isNotEmpty == true) {
      metaParts.add(distanceText!.trim());
    }

    if (lastUpdatedText?.trim().isNotEmpty == true) {
      metaParts.add(lastUpdatedText!.trim());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: CaptainTheme.strongText,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: CaptainTheme.accent.withValues(
                  alpha: 0.09,
                ),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$completedCount of $totalCount completed',
                style: TextStyle(
                  color: CaptainTheme.accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                allCompleted
                    ? 'All collection points completed'
                    : 'Next: CP ${nextStop!.sequence} • '
                        '${nextStop!.collectionPoint.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: allCompleted
                      ? CaptainTheme.success
                      : CaptainTheme.strongText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _LiveStatusChip(
              label: statusLabel,
              color: statusColor,
              animate: hasLiveLocation && vehicleOnline && !allCompleted,
            ),
          ],
        ),
        if (metaParts.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            metaParts.join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: CaptainTheme.mutedText,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _LiveStatusChip extends StatelessWidget {
  const _LiveStatusChip({
    required this.label,
    required this.color,
    required this.animate,
  });

  final String label;
  final Color color;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          animate
              ? _LiveDot(color: color)
              : Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({
    required this.color,
  });

  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      return _dot(1);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return _dot(
          0.72 + (_controller.value * 0.28),
        );
      },
    );
  }

  Widget _dot(double opacity) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(
                alpha: 0.24,
              ),
              blurRadius: 5,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleIndicator extends StatelessWidget {
  const _VehicleIndicator({
    required this.assetPath,
    required this.vehicleOnline,
    required this.hasLiveLocation,
  });

  final String assetPath;
  final bool vehicleOnline;
  final bool hasLiveLocation;

  @override
  Widget build(BuildContext context) {
    final locationUnavailable = !vehicleOnline || !hasLiveLocation;

    return AnimatedOpacity(
      opacity: vehicleOnline ? 1 : 0.48,
      duration: const Duration(milliseconds: 250),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (
                context,
                error,
                stackTrace,
              ) {
                return Icon(
                  Icons.local_shipping_rounded,
                  color: CaptainTheme.accent,
                  size: 31,
                );
              },
            ),
          ),
          if (locationUnavailable)
            Positioned(
              right: -5,
              top: -4,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CaptainTheme.surface,
                  border: Border.all(
                    color: CaptainTheme.hairline,
                  ),
                ),
                child: Icon(
                  Icons.location_off_rounded,
                  size: 9,
                  color: CaptainTheme.mutedText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StopNode extends StatelessWidget {
  const _StopNode({
    super.key,
    required this.stop,
    required this.left,
    required this.top,
    required this.size,
    required this.isNext,
    required this.reduceMotion,
    required this.onTap,
  });

  final OperatorTripCollectionPoint stop;

  final double left;
  final double top;
  final double size;

  final bool isNext;
  final bool reduceMotion;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visualState = _resolveStopVisualState(
      stop: stop,
      isNext: isNext,
    );

    final semanticsLabel = 'Collection point ${stop.sequence}, '
        '${stop.collectionPoint.name}, '
        '${visualState.label}';

    return Positioned(
      left: left,
      top: top,
      child: Semantics(
        button: true,
        label: semanticsLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 76,
            height: 64,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                if (isNext)
                  _NextStopRipple(
                    color: visualState.color,
                    reduceMotion: reduceMotion,
                  ),
                AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(
                          milliseconds: 260,
                        ),
                  curve: Curves.easeOutCubic,
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: visualState.fillColor,
                    border: Border.all(
                      color: visualState.color,
                      width: isNext ? 2.6 : 2.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: visualState.color.withValues(
                          alpha: isNext ? 0.22 : 0.11,
                        ),
                        blurRadius: isNext ? 10 : 6,
                        spreadRadius: isNext ? 1 : 0,
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(
                            milliseconds: 240,
                          ),
                    transitionBuilder: (
                      child,
                      animation,
                    ) {
                      return ScaleTransition(
                        scale: animation,
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      );
                    },
                    child: visualState.icon == null
                        ? const SizedBox.shrink(
                            key: ValueKey(
                              'empty-stop-icon',
                            ),
                          )
                        : Icon(
                            visualState.icon,
                            key: ValueKey(
                              visualState.label,
                            ),
                            size: 15,
                            color: visualState.iconColor,
                          ),
                  ),
                ),
                Positioned(
                  top: 31,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Text(
                        'CP ${stop.sequence}',
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CaptainTheme.strongText,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        visualState.label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: visualState.color,
                          fontSize: 9.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextStopRipple extends StatefulWidget {
  const _NextStopRipple({
    required this.color,
    required this.reduceMotion,
  });

  final Color color;
  final bool reduceMotion;

  @override
  State<_NextStopRipple> createState() => _NextStopRippleState();
}

class _NextStopRippleState extends State<_NextStopRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    );

    _updateAnimation();
  }

  @override
  void didUpdateWidget(
    covariant _NextStopRipple oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.reduceMotion != widget.reduceMotion) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.reduceMotion) {
      _controller
        ..stop()
        ..value = 0.25;
      return;
    }

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion) {
      return _buildRing(0.25);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = Curves.easeOut.transform(
          _controller.value,
        );

        return _buildRing(progress);
      },
    );
  }

  Widget _buildRing(double progress) {
    return Container(
      width: 28 + (17 * progress),
      height: 28 + (17 * progress),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.color.withValues(
            alpha: 0.34 * (1 - progress),
          ),
          width: 1.8,
        ),
      ),
    );
  }
}

class _ProgressRailPainter extends CustomPainter {
  const _ProgressRailPainter({
    required this.stopCount,
    required this.railStart,
    required this.railY,
    required this.nodeSpacing,
    required this.completedEndX,
    required this.activeStartX,
    required this.activeProgressX,
    required this.hasActiveSegment,
    required this.completedColor,
    required this.activeColor,
    required this.pendingColor,
  });

  final int stopCount;

  final double railStart;
  final double railY;
  final double nodeSpacing;

  final double completedEndX;
  final double activeStartX;
  final double activeProgressX;

  final bool hasActiveSegment;

  final Color completedColor;
  final Color activeColor;
  final Color pendingColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (stopCount < 2) {
      return;
    }

    final railEndX = railStart + (nodeSpacing * (stopCount - 1));

    final railStartPoint = Offset(
      railStart,
      railY,
    );

    final railEndPoint = Offset(
      railEndX,
      railY,
    );

    /*
     * Pending route:
     * Light-grey dashed rail.
     */
    _drawDashedLine(
      canvas: canvas,
      start: railStartPoint,
      end: railEndPoint,
      paint: Paint()
        ..color = pendingColor.withValues(
          alpha: 0.95,
        )
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    /*
     * Completed route:
     * Permanent solid green rail.
     */
    final boundedCompletedEnd =
        completedEndX.clamp(railStart, railEndX).toDouble();

    if (boundedCompletedEnd > railStart) {
      canvas.drawLine(
        railStartPoint,
        Offset(
          boundedCompletedEnd,
          railY,
        ),
        Paint()
          ..color = completedColor
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round,
      );
    }

    /*
     * Current active route:
     * Solid accent rail from the previous stop to the
     * vehicle's live position.
     */
    if (hasActiveSegment) {
      final boundedActiveStart =
          activeStartX.clamp(railStart, railEndX).toDouble();

      final boundedActiveProgress = activeProgressX
          .clamp(
            boundedActiveStart,
            railEndX,
          )
          .toDouble();

      if (boundedActiveProgress > boundedActiveStart) {
        final segmentRect = Rect.fromPoints(
          Offset(
            boundedActiveStart,
            railY,
          ),
          Offset(
            boundedActiveProgress,
            railY,
          ),
        );

        final activePaint = Paint()
          ..shader = LinearGradient(
            colors: [
              completedColor,
              activeColor,
            ],
          ).createShader(segmentRect)
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(
          Offset(
            boundedActiveStart,
            railY,
          ),
          Offset(
            boundedActiveProgress,
            railY,
          ),
          activePaint,
        );
      }
    }
  }

  void _drawDashedLine({
    required Canvas canvas,
    required Offset start,
    required Offset end,
    required Paint paint,
  }) {
    const dashWidth = 7.0;
    const dashGap = 6.0;

    final distance = (end - start).distance;

    if (distance <= 0) {
      return;
    }

    final direction = (end - start) / distance;

    var currentDistance = 0.0;

    while (currentDistance < distance) {
      final nextDistance = math.min(
        currentDistance + dashWidth,
        distance,
      );

      canvas.drawLine(
        start + (direction * currentDistance),
        start + (direction * nextDistance),
        paint,
      );

      currentDistance += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(
    covariant _ProgressRailPainter oldDelegate,
  ) {
    return oldDelegate.stopCount != stopCount ||
        oldDelegate.completedEndX != completedEndX ||
        oldDelegate.activeStartX != activeStartX ||
        oldDelegate.activeProgressX != activeProgressX ||
        oldDelegate.hasActiveSegment != hasActiveSegment ||
        oldDelegate.completedColor != completedColor ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.pendingColor != pendingColor;
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? CaptainTheme.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(
          alpha: 0.055,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: effectiveColor.withValues(
            alpha: 0.15,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: effectiveColor.withValues(
                alpha: 0.10,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: effectiveColor,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: CaptainTheme.mutedText,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: CaptainTheme.strongText,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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

class _RouteValues {
  const _RouteValues({
    required this.completedEndX,
    required this.activeStartX,
    required this.vehicleX,
    required this.hasActiveSegment,
  });

  final double completedEndX;
  final double activeStartX;
  final double vehicleX;
  final bool hasActiveSegment;
}

enum _StopKind {
  completed,
  next,
  pending,
  warning,
  failed,
}

class _StopVisualState {
  const _StopVisualState({
    required this.kind,
    required this.label,
    required this.color,
    required this.fillColor,
    required this.iconColor,
    this.icon,
  });

  final _StopKind kind;
  final String label;

  final Color color;
  final Color fillColor;
  final Color iconColor;

  final IconData? icon;
}

_StopVisualState _resolveStopVisualState({
  required OperatorTripCollectionPoint stop,
  required bool isNext,
}) {
  final rawStatus = stop.status.trim();
  final normalizedStatus = rawStatus.toLowerCase();

  if (stop.isCollected) {
    return _StopVisualState(
      kind: _StopKind.completed,
      label: 'Done',
      color: CaptainTheme.success,
      fillColor: CaptainTheme.success,
      iconColor: CaptainTheme.surface,
      icon: Icons.check_rounded,
    );
  }

  if (normalizedStatus.contains('fail') ||
      normalizedStatus.contains('reject')) {
    return _StopVisualState(
      kind: _StopKind.failed,
      label: _readableStatus(
        rawStatus,
        fallback: 'Failed',
      ),
      color: Colors.red.shade600,
      fillColor: CaptainTheme.surface,
      iconColor: Colors.red.shade600,
      icon: Icons.close_rounded,
    );
  }

  if (normalizedStatus.contains('skip') ||
      normalizedStatus.contains('block') ||
      normalizedStatus.contains('delay') ||
      normalizedStatus.contains('access')) {
    return _StopVisualState(
      kind: _StopKind.warning,
      label: _readableStatus(
        rawStatus,
        fallback: 'Collect later',
      ),
      color: CaptainTheme.danger,
      fillColor: CaptainTheme.surface,
      iconColor: CaptainTheme.danger,
      icon: Icons.priority_high_rounded,
    );
  }

  if (isNext) {
    final label = normalizedStatus.isEmpty || normalizedStatus == 'pending'
        ? 'Next'
        : _readableStatus(
            rawStatus,
            fallback: 'Next',
          );

    return _StopVisualState(
      kind: _StopKind.next,
      label: label,
      color: CaptainTheme.gold,
      fillColor: CaptainTheme.surface,
      iconColor: CaptainTheme.gold,
    );
  }

  return _StopVisualState(
    kind: _StopKind.pending,
    label: 'Pending',
    color: CaptainTheme.mutedText,
    fillColor: CaptainTheme.surface,
    iconColor: CaptainTheme.mutedText,
  );
}

String _readableStatus(
  String value, {
  required String fallback,
}) {
  final cleaned = value.trim().replaceAll('_', ' ').replaceAll('-', ' ');

  if (cleaned.isEmpty) {
    return fallback;
  }

  return cleaned
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}
