import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:iwms_private_app/core/ui/app_flash.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';

/// Centralised feedback surfaces for the Captain module.
///
/// Every success / error / info message in the driver experience goes through
/// these helpers so the look (glass banner, status tint, dual-mode colors)
/// stays identical everywhere and call sites stay one-liners:
///
///   CaptainFeedback.success(context, 'Collection completed');
///   CaptainFeedback.error(context, 'Reroute failed');
///   CaptainFeedback.celebrate(context, title: 'Trip completed');
class CaptainFeedback {
  CaptainFeedback._();

  static void success(BuildContext context, String message) =>
      _banner(context, message,
          icon: Icons.check_circle_rounded, color: CaptainTheme.success);

  static void error(BuildContext context, String message) =>
      _banner(context, message,
          icon: Icons.error_outline_rounded, color: CaptainTheme.danger);

  static void warning(BuildContext context, String message) =>
      _banner(context, message,
          icon: Icons.warning_amber_rounded, color: CaptainTheme.warning);

  static void info(BuildContext context, String message) =>
      _banner(context, message,
          icon: Icons.info_outline_rounded, color: CaptainTheme.info);

  static void _banner(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color color,
  }) {
    if (color == CaptainTheme.success) {
      AppFlash.success(context, message);
    } else if (color == CaptainTheme.danger) {
      AppFlash.error(context, message);
    } else if (color == CaptainTheme.warning) {
      AppFlash.warning(context, message);
    } else {
      AppFlash.info(context, message);
    }
  }

  /// Full-width celebratory sheet for milestone moments (trip completed,
  /// collection submitted). Auto-dismisses after [duration] unless the user
  /// taps it away first.
  static Future<void> celebrate(
    BuildContext context, {
    required String title,
    String? message,
    Duration duration = const Duration(milliseconds: 2200),
  }) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        Future.delayed(duration, () {
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).maybePop();
          }
        });
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: _CelebrationCard(title: title, message: message),
        );
      },
    );
  }
}

class _CelebrationCard extends StatelessWidget {
  const _CelebrationCard({required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final dark = CaptainThemeStore.isDark.value;
    return ClipRRect(
      borderRadius: CaptainTheme.cardRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
          decoration: BoxDecoration(
            color: dark
                ? const Color(0xFF151917).withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.96),
            borderRadius: CaptainTheme.cardRadius,
            border: Border.all(
              color: CaptainTheme.success.withValues(alpha: 0.5),
            ),
            boxShadow: CaptainTheme.elevatedShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CaptainTheme.success.withValues(alpha: 0.14),
                    border: Border.all(
                      color: CaptainTheme.success.withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: CaptainTheme.success,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: CaptainTheme.strongText,
                ),
              ),
              if (message != null && message!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: CaptainTheme.mutedText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
