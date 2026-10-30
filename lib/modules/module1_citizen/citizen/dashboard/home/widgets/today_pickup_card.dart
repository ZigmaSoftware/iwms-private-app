import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:iwms_private_app/core/push/push_notification_service.dart';
import 'package:iwms_private_app/data/models/citizen_pickup_model.dart';
import 'package:iwms_private_app/data/repositories/citizen_pickup_repository.dart';
import 'package:iwms_private_app/modules/module1_citizen/citizen/theme/citizen_theme.dart';
import 'package:iwms_private_app/router/app_router.dart';

/// "Today's pickup" on the citizen home tab.
///
/// Shows today's household stop status. When the driver marked it Collect
/// Later, offers "I'm home now" (alerts the crew). When it ended Not
/// Available, offers "I was home" (opens a pre-filled Missed Pickup
/// grievance) — unless the backend already raised one automatically.
/// Hidden when the citizen has neither a stop nor a service notice today.
class TodayPickupCard extends StatefulWidget {
  const TodayPickupCard({
    super.key,
    required this.surfaceColor,
    required this.outlineColor,
    required this.isDarkMode,
    required this.textColor,
    required this.secondaryTextColor,
    this.refreshSignal,
    this.horizontalPadding = 16,
  });

  final Color surfaceColor;
  final Color outlineColor;
  final bool isDarkMode;
  final Color textColor;
  final Color secondaryTextColor;

  /// Reloads the card when it fires (the home tab's pull-to-refresh).
  final Listenable? refreshSignal;
  final double horizontalPadding;

  @override
  State<TodayPickupCard> createState() => _TodayPickupCardState();
}

class _TodayPickupCardState extends State<TodayPickupCard> {
  final _repo = CitizenPickupRepository();
  CitizenPickupToday? _stop;
  CitizenServiceNotice? _serviceNotice;
  bool _loaded = false;
  bool _sending = false;
  bool _expanded = false;
  StreamSubscription<Map<String, dynamic>>? _pushSub;
  Timer? _dayEndTimer;

  static const _ok = Color(0xFF0B8F61);
  static const _warn = Color(0xFFB7791F);
  static const _bad = Color(0xFFD83B3B);

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_load);
    // Refresh on both exception statuses and a completed collection so the
    // customer sees the latest card without a manual pull-to-refresh.
    _pushSub = PushNotificationService.instance.events.listen((data) {
      if (data['event'] == 'household_status' ||
          data['event'] == 'household_collected' ||
          data['type'] == 'NO_COLLECTION_TODAY' ||
          data['type'] == 'COLLECTION_RESTORED') {
        _load();
      }
    });
    _hideAtEndOfDay();
    _load();
  }

  @override
  void didUpdateWidget(covariant TodayPickupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_load);
      widget.refreshSignal?.addListener(_load);
    }
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_load);
    _pushSub?.cancel();
    _dayEndTimer?.cancel();
    super.dispose();
  }

  void _hideAtEndOfDay() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _dayEndTimer = Timer(tomorrow.difference(now), () {
      if (!mounted) return;
      setState(() {
        _stop = null;
        _serviceNotice = null;
      });
      _hideAtEndOfDay();
    });
  }

  Future<void> _load() async {
    try {
      final stop = await _repo.fetchToday();
      if (!mounted) return;
      setState(() {
        _stop = stop;
        _serviceNotice = _repo.lastServiceNotice;
        _loaded = true;
      });
    } catch (_) {
      // Non-critical card: keep whatever was shown before.
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _sayImHome() async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => const _ImHomeDialog(),
    );
    if (note == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final stop = await _repo.sayImHome(note: note);
      if (!mounted) return;
      setState(() => _stop = stop ?? _stop);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The collection crew has been told you are home.')));
    } on CitizenPickupException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      _load();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _reportWasHome(CitizenPickupToday stop) {
    final when = stop.statusUpdatedAt == null
        ? 'today'
        : 'at ${DateFormat('h:mm a').format(stop.statusUpdatedAt!)} today';
    context.push(AppRoutePaths.citizenGrievanceChat, extra: {
      'categoryCode': 'MISSED_PICKUP',
      'description': 'My pickup was marked "Not Available" $when, '
          'but I was at home and my waste was not collected.',
    });
  }

  @override
  Widget build(BuildContext context) {
    final stop = _stop;
    if (!_loaded) return const SizedBox.shrink();
    final notice = _serviceNotice;
    if (notice != null) return _buildNoCollectionCard(notice);
    if (stop == null) return const SizedBox.shrink();
    return _buildPickupCard(stop);
  }

  Widget _buildNoCollectionCard(CitizenServiceNotice notice) => Padding(
        padding: EdgeInsets.fromLTRB(
            widget.horizontalPadding, 0, widget.horizontalPadding, 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.surfaceColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _bad.withValues(alpha: .35)),
            boxShadow: widget.isDarkMode
                ? const []
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: .08),
                        blurRadius: 14,
                        offset: const Offset(0, 5)),
                  ],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: _bad.withValues(alpha: .12), shape: BoxShape.circle),
              child:
                  const Icon(Icons.event_busy_outlined, size: 17, color: _bad),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text('No collection today',
                          style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: widget.textColor)),
                    ),
                    const _StatusPill(label: 'Service update', color: _bad),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Collection is suspended today due to ${notice.explanation.toLowerCase()}.',
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: widget.secondaryTextColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Please keep your waste safely stored until the next scheduled collection.',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: widget.secondaryTextColor),
                  ),
                ],
              ),
            ),
          ]),
        ),
      );

  Widget _buildPickupCard(CitizenPickupToday stop) {
    final imageUrl = stop.proofImageUrl;
    final collectedAt = stop.collectedAt;
    final time =
        collectedAt == null ? 'Today' : 'Today at ${_time(collectedAt)}';
    final kg = stop.collectedWeightKg ?? 0;
    final weight = kg.toStringAsFixed(1);
    final actions = _actions(stop);
    final canExpand = imageUrl != null ||
        actions.isNotEmpty ||
        (stop.isCollected && stop.wasteBreakdown.isNotEmpty);
    final color = _color(stop);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          widget.horizontalPadding, 0, widget.horizontalPadding, 12),
      child: Material(
        color: widget.surfaceColor,
        elevation: widget.isDarkMode ? 0 : 3,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: widget.outlineColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap:
              canExpand ? () => setState(() => _expanded = !_expanded) : null,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                      child: Icon(_statusIcon(stop),
                          size: 13, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_title(stop),
                          style: TextStyle(
                              fontSize: 16.5,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              color: widget.textColor)),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(label: _label(stop), color: color),
                  ]),
                ),
                Stack(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: !_expanded && imageUrl != null ? 88 : 0,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          !_expanded && imageUrl != null ? 116 : 16,
                          14,
                        ),
                        child: stop.isCollected
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$weight kg',
                                      style: TextStyle(
                                          color: widget.textColor,
                                          fontSize: 27,
                                          height: 1,
                                          fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 5),
                                  Text(
                                      '${stop.wasteDescription} collected\n$time',
                                      style: TextStyle(
                                          color: widget.secondaryTextColor,
                                          fontSize: 13,
                                          height: 1.35,
                                          fontWeight: FontWeight.w500)),
                                ],
                              )
                            : Text(_message(stop),
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: widget.secondaryTextColor)),
                      ),
                    ),
                    if (!_expanded && imageUrl != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: _ProofCornerIllustration(
                          caption: stop.isCollected
                              ? 'Pickup proof photo'
                              : 'Status proof photo',
                          detail: stop.isCollected
                              ? '${_time(stop.collectedAt)} · $weight kg collected'
                              : _label(stop),
                        ),
                      ),
                  ],
                ),
                if (_expanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (stop.isCollected &&
                            stop.wasteBreakdown.isNotEmpty) ...[
                          ...stop.wasteBreakdown.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: Row(children: [
                                  Expanded(
                                    child: Text(item.wasteType,
                                        style: TextStyle(
                                            color: widget.secondaryTextColor,
                                            fontSize: 12.5)),
                                  ),
                                  Text('${_formatWeight(item.weightKg)} kg',
                                      style: TextStyle(
                                          color: widget.textColor,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700)),
                                ]),
                              )),
                        ],
                        if (imageUrl != null) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => _showCollectionImage(imageUrl),
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: const Text('View image'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: CitizenColors.primary,
                              minimumSize: const Size.fromHeight(40),
                              visualDensity: VisualDensity.compact,
                              side: const BorderSide(
                                  color: CitizenColors.primary),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                        ...actions,
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

  String _formatWeight(double value) => value.toStringAsFixed(1);

  String _title(CitizenPickupToday stop) {
    if (stop.isCollected) return 'Pickup completed';
    if (stop.isCollectLater) return 'Pickup delayed';
    if (stop.isNotAvailable) return 'Not picked up';
    return 'Pickup scheduled';
  }

  IconData _statusIcon(CitizenPickupToday stop) {
    if (stop.isCollected) return Icons.check_rounded;
    if (stop.isNotAvailable) return Icons.close_rounded;
    if (stop.isCollectLater) return Icons.schedule_rounded;
    return Icons.local_shipping_outlined;
  }

  void _showCollectionImage(String imageUrl) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : const CircularProgressIndicator(
                                  color: Colors.white),
                      errorBuilder: (_, __, ___) => const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined,
                              size: 46, color: Colors.white70),
                          SizedBox(height: 10),
                          Text('Image could not be loaded',
                              style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filled(
                  tooltip: 'Close image',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _label(CitizenPickupToday s) {
    if (s.isCollected) return 'Completed';
    if (s.isCollectLater) return 'Delayed';
    if (s.isNotAvailable) return 'Not completed';
    return 'Scheduled';
  }

  Color _color(CitizenPickupToday s) {
    if (s.isCollected) return _ok;
    if (s.isCollectLater) return _warn;
    if (s.isNotAvailable) return _bad;
    return CitizenColors.primary;
  }

  String _time(DateTime? t) => t == null ? '' : DateFormat('h:mm a').format(t);

  String _message(CitizenPickupToday s) {
    if (s.isCollected) {
      final kg = s.collectedWeightKg;
      return 'Your waste was collected${s.collectedAt == null ? '' : ' at ${_time(s.collectedAt)}'}'
          '${kg != null && kg > 0 ? ' (${kg.toStringAsFixed(kg >= 10 ? 0 : 1)} kg)' : ''}.';
    }
    if (s.isCollectLater) {
      if (s.customerAvailableAt != null) {
        return 'The crew was notified at ${_time(s.customerAvailableAt)} that you are available.';
      }
      final reason = (s.statusReason ?? '').trim();
      return 'Collection was deferred and will be attempted again today'
          '${reason.isEmpty ? '.' : ': $reason.'}';
    }
    if (s.isNotAvailable) {
      if (s.missedPickupTicketNo != null) {
        return 'Collection could not be completed. Complaint ${s.missedPickupTicketNo} was raised automatically.';
      }
      return 'Collection could not be completed because the household was marked unavailable.';
    }
    return 'Waste collection is scheduled for your household today.';
  }

  List<Widget> _actions(CitizenPickupToday s) {
    Widget button(IconData icon, String label, VoidCallback? onPressed) =>
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(icon, size: 18),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: CitizenColors.primary,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
    if (s.canSayImHome) {
      return [
        button(Icons.home_rounded, "I'm home now", _sending ? null : _sayImHome)
      ];
    }
    if (s.isNotAvailable && s.missedPickupTicketNo == null) {
      return [
        button(Icons.report_outlined, 'I was home', () => _reportWasHome(s))
      ];
    }
    return const [];
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _ProofCornerIllustration extends StatelessWidget {
  const _ProofCornerIllustration({
    required this.caption,
    required this.detail,
  });

  final String caption;
  final String detail;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(108, 88),
        painter: _ProofCornerPainter(caption: caption, detail: detail),
      );
}

class _ProofCornerPainter extends CustomPainter {
  const _ProofCornerPainter({required this.caption, required this.detail});

  final String caption;
  final String detail;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFDDF6F3);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Offset.zero & size,
        topLeft: const Radius.circular(30),
      ),
      background,
    );

    canvas.drawCircle(
      Offset(size.width - 7, 11),
      22,
      Paint()..color = const Color(0xFFFFA94A).withValues(alpha: 0.16),
    );

    _paintText(
      canvas,
      caption,
      const TextStyle(
        color: Color(0xFF172033),
        fontSize: 7,
        fontWeight: FontWeight.w800,
      ),
      top: 14,
      width: size.width,
    );
    _paintText(
      canvas,
      detail,
      const TextStyle(color: Color(0xFF6F7A8B), fontSize: 5.2),
      top: 24,
      width: size.width,
    );

    final blue = Paint()..color = const Color(0xFF1556B8);
    final blueLight = Paint()..color = const Color(0xFF2D79DD);
    final green = Paint()..color = const Color(0xFF12A572);
    final greenLight = Paint()..color = const Color(0xFF28BA88);
    final orange = Paint()..color = const Color(0xFFF7931E);
    final orangeLight = Paint()..color = const Color(0xFFFFA94A);
    final wheel = Paint()..color = const Color(0xFF22304A);

    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 48, 49, 27), const Radius.circular(5)),
        blue);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 41, 39, 9), const Radius.circular(3)),
        blueLight);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(54, 42, 27, 33), const Radius.circular(5)),
        green);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(59, 35, 18, 9), const Radius.circular(3)),
        greenLight);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(86, 50, 22, 25), const Radius.circular(4)),
        orange);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(89, 44, 17, 8), const Radius.circular(3)),
        orangeLight);

    for (final x in <double>[13, 43, 64, 102]) {
      canvas.drawCircle(Offset(x, 79), 5.5, wheel);
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    TextStyle style, {
    required double top,
    required double width,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: width - 8);
    painter.paint(canvas, Offset((width - painter.width) / 2, top));
  }

  @override
  bool shouldRepaint(covariant _ProofCornerPainter oldDelegate) =>
      oldDelegate.caption != caption || oldDelegate.detail != detail;
}

/// Confirms "I'm home now" with an optional short note for the crew.
/// Pops the note ('' when left blank) or null when cancelled.
class _ImHomeDialog extends StatefulWidget {
  const _ImHomeDialog();
  @override
  State<_ImHomeDialog> createState() => _ImHomeDialogState();
}

class _ImHomeDialogState extends State<_ImHomeDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text("Tell the crew you're home?"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'The driver will be alerted to come back for your waste on this trip.'),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 200,
            decoration: const InputDecoration(
              hintText: 'Note for the crew (optional), e.g. "Gate is open"',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(_note.text.trim()),
              child: const Text('Alert crew')),
        ],
      );
}
