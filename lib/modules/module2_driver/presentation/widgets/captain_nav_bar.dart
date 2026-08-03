import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_citizen_app/modules/module3_operator/utils/attendance_blink_store.dart';

const double kCaptainNavBarHeight = 68;
const double kCaptainNavBarHorizontalPadding = 16;
const double kCaptainNavBarRadius = 28;
const double kCaptainHomeBottomClearance = 102;
const double kCaptainMapBottomOverlayOffset = 74;
const double kCaptainProfileBottomSpacer = 94;

/// Captain bottom navigation — a docked glass bar with 4 tabs and the Scan
/// FAB hovering over its centre.
/// Layout: [tab0][tab1] (Scan FAB) [tab2][tab3].
///
/// Rules carried over from the original version: big tap targets (full slot
/// height), icon + always-visible label, glass blur, animated indicator pill,
/// and the attendance blink badge so a due check-in is impossible to miss.
class CaptainNavBar extends StatelessWidget {
  const CaptainNavBar({
    super.key,
    required this.activeIndex,
    required this.onTabSelected,
    required this.items,
    this.height = kCaptainNavBarHeight,
  });

  final int activeIndex;
  final ValueChanged<int> onTabSelected;
  final List<CaptainNavItem> items;
  final double height;

  @override
  Widget build(BuildContext context) {
    assert(items.length == 4, 'CaptainNavBar expects exactly 4 side tabs');
    final dark = CaptainThemeStore.isDark.value;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(kCaptainNavBarRadius),
      topRight: Radius.circular(kCaptainNavBarRadius),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kCaptainNavBarHorizontalPadding,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          // Keep the same frosted texture, but let the bar sit flush to the
          // screen bottom instead of floating above it.
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            height: height + bottomInset,
            padding: EdgeInsets.only(bottom: bottomInset),
            decoration: BoxDecoration(
              color: CaptainTheme.surface.withValues(alpha: dark ? 0.55 : 0.62),
              borderRadius: borderRadius,
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.14)
                    : const Color(0xFF0B1220).withValues(alpha: 0.12),
                width: 1,
              ),
              // Empty in light mode — glass carries no shadow there.
              boxShadow: CaptainTheme.elevatedShadow,
            ),
            child: Row(
              children: [
                Expanded(child: _slot(0)),
                Expanded(child: _slot(1)),
                const SizedBox(width: 64), // gap under the hovering Scan FAB
                Expanded(child: _slot(2)),
                Expanded(child: _slot(3)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _slot(int index) => _CaptainNavTab(
        item: items[index],
        selected: index == activeIndex,
        onTap: () => onTabSelected(index),
      );
}

class CaptainNavItem {
  const CaptainNavItem({
    required this.icon,
    required this.label,
    this.blink = false,
  });

  final IconData icon;
  final String label;
  final bool blink;
}

class _CaptainNavTab extends StatelessWidget {
  const _CaptainNavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final CaptainNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? CaptainTheme.accent : CaptainTheme.mutedText;

    return InkResponse(
      onTap: onTap,
      radius: 38,
      highlightColor: Colors.white.withValues(alpha: 0.06),
      splashColor: Colors.white.withValues(alpha: 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            width: selected ? 22 : 0,
            height: 3,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: CaptainTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _TabIcon(item: item, color: color, selected: selected),
          const SizedBox(height: 3),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({
    required this.item,
    required this.color,
    required this.selected,
  });

  final CaptainNavItem item;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = AnimatedScale(
      scale: selected ? 1.12 : 1,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      child: Icon(item.icon, color: color, size: 22),
    );

    if (!item.blink) return icon;

    return ValueListenableBuilder<bool>(
      valueListenable: AttendanceBlinkStore.notifier,
      builder: (context, isBlinking, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            icon,
            if (isBlinking)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: CaptainTheme.danger,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: CaptainTheme.surface,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: CaptainTheme.danger.withValues(alpha: 0.6),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The pulsing Scan FAB — bright mint with DARK ink iconography (a bright
/// fill needs dark ink for contrast, not white). Hovers over the docked bar's
/// centre via `FloatingActionButtonLocation.centerDocked`.
class CaptainScanFab extends StatefulWidget {
  const CaptainScanFab({
    super.key,
    required this.onPressed,
    this.label = 'Scan',
  });

  final VoidCallback onPressed;
  final String label;

  @override
  State<CaptainScanFab> createState() => _CaptainScanFabState();
}

class _CaptainScanFabState extends State<CaptainScanFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_pulse.value);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64 + (12 * t),
                height: 64 + (12 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CaptainTheme.accent.withValues(alpha: 0.25 * (1 - t)),
                ),
              ),
              child!,
            ],
          );
        },
        child: Material(
          color: CaptainTheme.accent,
          shape: const CircleBorder(),
          elevation: 8,
          shadowColor: CaptainTheme.accent.withValues(alpha: 0.45),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPressed,
            child: Semantics(
              label: widget.label,
              button: true,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: CaptainTheme.accentGradient,
                ),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  // Navy ink on the bright blue in dark mode; white in light
                  // mode so the FAB matches the light theme's clean look.
                  color: CaptainThemeStore.isDark.value
                      ? CaptainTheme.onAccent
                      : Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
