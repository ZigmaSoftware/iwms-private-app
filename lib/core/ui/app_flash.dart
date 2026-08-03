import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:iwms_citizen_app/core/theme/app_colors.dart';

/// Semantic flavour of a floating notification.
enum AppFlashType { success, error, warning, info }

/// A beautifully animated, self-contained floating notification ("flash") that
/// replaces raw [SnackBar]s across the app.
///
/// It renders through the root [Overlay], so it floats above bottom nav bars,
/// submit buttons and bottom sheets, and works even on screens without a
/// Scaffold in the immediate context (e.g. login).
///
/// Usage:
/// ```dart
/// AppFlash.success(context, 'Wet Waste added successfully');
/// AppFlash.error(context, 'Invalid username or password', title: 'Login failed');
/// AppFlash.warning(context, 'Capture a photo first');
/// AppFlash.info(context, 'Saved offline — will sync automatically');
/// ```
class AppFlash {
  AppFlash._();

  static OverlayEntry? _entry;

  static void success(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) =>
      show(context,
          message: message,
          title: title,
          type: AppFlashType.success,
          duration: duration);

  static void error(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) =>
      show(context,
          message: message,
          title: title,
          type: AppFlashType.error,
          duration: duration);

  static void warning(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) =>
      show(context,
          message: message,
          title: title,
          type: AppFlashType.warning,
          duration: duration);

  static void info(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) =>
      show(context,
          message: message,
          title: title,
          type: AppFlashType.info,
          duration: duration);

  /// Core entry point. Prefer the [success]/[error]/[warning]/[info] helpers.
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    AppFlashType type = AppFlashType.info,
    Duration? duration,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // Only one flash on screen at a time — replace the current one.
    _entry?.remove();
    _entry = null;

    final brightness = Theme.of(context).brightness;
    final effectiveDuration = duration ??
        (message.length > 90
            ? const Duration(milliseconds: 5200)
            : const Duration(milliseconds: 3600));

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlashWidget(
        key: UniqueKey(),
        message: message,
        title: title,
        type: type,
        brightness: brightness,
        duration: effectiveDuration,
        onClose: () {
          if (_entry == entry) {
            entry.remove();
            _entry = null;
          }
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  /// Immediately dismiss any visible flash.
  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _FlashPalette {
  const _FlashPalette({
    required this.accent,
    required this.icon,
    required this.surface,
    required this.textStrong,
    required this.textMuted,
    required this.border,
  });

  final Color accent;
  final IconData icon;
  final Color surface;
  final Color textStrong;
  final Color textMuted;
  final Color border;

  factory _FlashPalette.of(AppFlashType type, Brightness brightness) {
    final Color accent;
    final IconData icon;
    switch (type) {
      case AppFlashType.success:
        accent = AppColors.success;
        icon = Icons.check_circle_rounded;
        break;
      case AppFlashType.error:
        accent = AppColors.error;
        icon = Icons.error_rounded;
        break;
      case AppFlashType.warning:
        accent = AppColors.warning;
        icon = Icons.warning_amber_rounded;
        break;
      case AppFlashType.info:
        accent = AppColors.primaryVariant;
        icon = Icons.info_rounded;
        break;
    }

    final isDark = brightness == Brightness.dark;
    return _FlashPalette(
      accent: accent,
      icon: icon,
      surface: isDark
          ? const Color(0xFF10261A).withValues(alpha: 0.92)
          : Colors.white.withValues(alpha: 0.9),
      textStrong: isDark ? Colors.white : const Color(0xFF0D2F20),
      textMuted: isDark
          ? Colors.white.withValues(alpha: 0.72)
          : const Color(0xFF4F7A63),
      border: accent.withValues(alpha: isDark ? 0.42 : 0.3),
    );
  }
}

class _FlashWidget extends StatefulWidget {
  const _FlashWidget({
    super.key,
    required this.message,
    required this.title,
    required this.type,
    required this.brightness,
    required this.duration,
    required this.onClose,
  });

  final String message;
  final String? title;
  final AppFlashType type;
  final Brightness brightness;
  final Duration duration;
  final VoidCallback onClose;

  @override
  State<_FlashWidget> createState() => _FlashWidgetState();
}

class _FlashWidgetState extends State<_FlashWidget>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _timer; // doubles as the progress bar
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  bool _closing = false;

  @override
  void initState() {
    super.initState();

    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _enter,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.94, end: 1).animate(CurvedAnimation(
      parent: _enter,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    ));

    _timer = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _close();
      });

    _enter.forward();
    _timer.forward();

    switch (widget.type) {
      case AppFlashType.error:
        HapticFeedback.heavyImpact();
        break;
      case AppFlashType.warning:
        HapticFeedback.mediumImpact();
        break;
      default:
        HapticFeedback.lightImpact();
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer.stop();
    if (mounted) {
      await _enter.reverse();
    }
    widget.onClose();
  }

  @override
  void dispose() {
    _enter.dispose();
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _FlashPalette.of(widget.type, widget.brightness);
    final mediaTop = MediaQuery.of(context).padding.top;

    return Positioned(
      top: mediaTop + 10,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: ScaleTransition(
              scale: _scale,
              alignment: Alignment.topCenter,
              child: _card(palette),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(_FlashPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            onTap: _close,
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -80) _close();
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.28),
                    blurRadius: 26,
                    spreadRadius: -6,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: palette.border, width: 1),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Accent stripe.
                              Container(width: 5, color: palette.accent),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 12, 10, 12),
                                  child: _content(palette),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _progressBar(palette),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(_FlashPalette palette) {
    final title = widget.title;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.accent,
                Color.lerp(palette.accent, Colors.black, 0.18)!,
              ],
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: palette.accent.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(palette.icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null && title.trim().isNotEmpty) ...[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textStrong,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              Text(
                widget.message,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: title != null && title.trim().isNotEmpty
                      ? palette.textMuted
                      : palette.textStrong,
                  fontSize: 13.5,
                  height: 1.28,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _close,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.close_rounded,
              size: 18,
              color: palette.textMuted.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _progressBar(_FlashPalette palette) {
    return AnimatedBuilder(
      animation: _timer,
      builder: (context, _) {
        return FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: (1 - _timer.value).clamp(0.0, 1.0),
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.accent.withValues(alpha: 0.55),
                  palette.accent,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
