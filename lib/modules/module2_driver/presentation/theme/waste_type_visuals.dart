import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/modules/module2_driver/presentation/theme/captain_theme.dart';

/// Colour + icon for a waste stream, so the same stream reads identically
/// wherever the driver meets it — the household action sheet, the weight-capture
/// screen, a summary chip.
///
/// Everything resolves through [CaptainTheme] tokens rather than raw hex, so the
/// palette follows the light/dark toggle instead of going muddy on black. The
/// four segregated household streams each get their own hue; anything else the
/// panchayat has configured falls back to a neutral.
class WasteTypeVisual {
  const WasteTypeVisual({
    required this.color,
    required this.icon,
    required this.shortLabel,
  });

  final Color color;
  final IconData icon;

  /// Compact label for tight chips ("Wet", "Dry"), where the full
  /// "Wet Waste" would wrap.
  final String shortLabel;

  /// Resolve by waste-type name as the backend stores it ("Wet Waste",
  /// "Sanitary Waste", …). Matching is substring-based and case-insensitive
  /// because panchayats name these inconsistently ("Wet", "Wet Waste",
  /// "Organic Waste").
  factory WasteTypeVisual.forName(String name) {
    final key = name.trim().toLowerCase();

    if (key.contains('wet') || key.contains('organic') || key.contains('food')) {
      return WasteTypeVisual(
        color: CaptainTheme.success,
        icon: Icons.eco_rounded,
        shortLabel: 'Wet',
      );
    }
    if (key.contains('dry') ||
        key.contains('recycl') ||
        key.contains('plastic') ||
        key.contains('paper')) {
      return WasteTypeVisual(
        color: CaptainTheme.info,
        icon: Icons.recycling_rounded,
        shortLabel: 'Dry',
      );
    }
    // Sanitary is the one stream the driver must handle differently, so it
    // carries the danger hue rather than another neutral.
    if (key.contains('sanitary') ||
        key.contains('hazard') ||
        key.contains('medical') ||
        key.contains('diaper')) {
      return WasteTypeVisual(
        color: CaptainTheme.danger,
        icon: Icons.medical_services_rounded,
        shortLabel: 'Sanitary',
      );
    }
    if (key.contains('mixed') || key.contains('reject')) {
      return WasteTypeVisual(
        color: CaptainTheme.gold,
        icon: Icons.delete_sweep_rounded,
        shortLabel: 'Mixed',
      );
    }
    return WasteTypeVisual(
      color: CaptainTheme.mutedText,
      icon: Icons.category_rounded,
      shortLabel: name.trim().isEmpty ? 'Other' : name.trim(),
    );
  }
}

/// A single waste-stream pill: tinted fill, matching outline, icon + name.
///
/// Tint alpha is deliberately low (12%) with a full-strength icon and label, so
/// the chip stays legible on both the white and the black canvas without a
/// per-mode colour table.
class WasteTypeChip extends StatelessWidget {
  const WasteTypeChip({
    super.key,
    required this.name,
    this.dense = false,
  });

  final String name;

  /// Uses the short label ("Wet") instead of the full name — for rows where
  /// several streams have to fit side by side.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = WasteTypeVisual.forName(name);
    final label = dense ? visual.shortLabel : name;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 9 : 11,
        vertical: dense ? 6 : 7,
      ),
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: visual.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: dense ? 14 : 16, color: visual.color),
          SizedBox(width: dense ? 5 : 7),
          Text(
            label,
            style: TextStyle(
              color: visual.color,
              fontSize: dense ? 11.5 : 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
