import 'package:flutter/material.dart';

import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// The same door-sticker layout the web admin prints from Daily Trip Plan /
/// the Households list (see `customerQrStickerPdf.ts`'s `drawSticker`),
/// reproduced as a Flutter widget instead of a canvas-drawn PDF card —
/// so a supervisor sees the exact template that will be printed and stuck on
/// the door, without leaving the app.
///
/// Layout, top to bottom, matches the web card exactly:
/// project emblem + operator mark → project/local-body name → hairline →
/// ward headline (largest text) → building · unit line → QR, edge to edge →
/// customer id caption → company name footer.
class CustomerQrTemplateCard extends StatelessWidget {
  const CustomerQrTemplateCard({
    super.key,
    required this.household,
    required this.qrImageUrl,
  });

  final SupervisorHousehold household;

  /// Already resolved to an absolute URL (see `_resolveMediaUrl` at the call
  /// site) — this widget doesn't know about the app's media-base handling.
  final String qrImageUrl;

  // Card proportions match the web sheet's CARD_WIDTH:CARD_HEIGHT ratio
  // (508:739 at its 1240x1754 canvas render size — see SHEET_WIDTH/HEIGHT,
  // MARGIN_X/Y, GUTTER_X/Y in customerQrStickerPdf.ts), so the on-screen card
  // has the same silhouette as the printed sticker.
  static const double _aspectRatio = 508 / 739;

  static const _navy = Color(0xFF123A63);
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF5B6B7D);
  static const _hairline = Color(0xFFC8D3DE);

  @override
  Widget build(BuildContext context) {
    final buildingLine = household.stickerBuildingLine;
    final unitLine = household.stickerUnitLine;
    final addressLine = [buildingLine, unitLine]
        .where((part) => part.trim().isNotEmpty)
        .join(' · ');
    final ward = household.wardHeadline;
    final project = household.projectName.trim();
    final company = household.companyName.trim();
    final identifier = household.customerId.isNotEmpty
        ? household.customerId
        : household.uniqueId;

    return AspectRatio(
      aspectRatio: _aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _navy, width: 2.5),
          boxShadow: SupervisorTheme.softShadow,
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top row: project emblem (left) + operator mark (right) ──
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  if (household.projectLogoUrl.trim().isNotEmpty)
                    _LogoBox(url: household.projectLogoUrl)
                  else
                    const Spacer(),
                  const Spacer(),
                  Image.asset(
                    'assets/images/bp_operator_logo.png',
                    height: 34,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Local body / project name ──
            if (project.isNotEmpty)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  project,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            const Divider(height: 1, thickness: 1, color: _hairline),
            const SizedBox(height: 8),

            // ── Ward headline: the largest text on the card ──
            if (ward.isNotEmpty)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  ward,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
            const SizedBox(height: 6),

            // ── Building/area and unit, together on one line ──
            if (addressLine.isNotEmpty)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  addressLine,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
            const SizedBox(height: 10),

            // ── QR: takes every pixel left between the details and footer ──
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: qrImageUrl.trim().isEmpty
                      ? const _QrPlaceholder(label: 'No QR')
                      : Image.network(
                          qrImageUrl,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.none,
                          errorBuilder: (_, __, ___) =>
                              const _QrPlaceholder(label: 'QR unavailable'),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              identifier,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _muted,
                fontFamily: 'monospace',
              ),
            ),

            // ── Footer: which company this household belongs to ──
            if (company.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1, thickness: 1, color: _hairline),
              const SizedBox(height: 6),
              Text(
                company.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogoBox extends StatelessWidget {
  const _LogoBox({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 34,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

class _QrPlaceholder extends StatelessWidget {
  const _QrPlaceholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: CustomerQrTemplateCard._muted,
        ),
      ),
    );
  }
}
