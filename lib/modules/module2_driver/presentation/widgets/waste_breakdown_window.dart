import 'package:flutter/material.dart';

import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';

/// One row in the floating waste-breakdown window.
class WasteBreakdownRow {
  const WasteBreakdownRow({required this.wasteType, required this.weightKg});

  final String wasteType;
  final double weightKg;
}

/// The "eye" button's floating window — a compact centered card (not a
/// full-width bottom sheet, so it reads as a quick glance rather than another
/// screen to navigate) listing what was collected, split by waste type.
///
/// Used from both `_StopTile` (bin — always exactly one row, the bin's own
/// waste type) and `_HouseholdTile` (household — one row per waste type
/// actually captured, from `OperatorTripHouseholdStop.wasteBreakdown`).
Future<void> showWasteBreakdownWindow(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<WasteBreakdownRow> rows,
  String? imageUrl,
}) {
  final total = rows.fold<double>(0, (sum, r) => sum + r.weightKg);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: CaptainTheme.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: CaptainTheme.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_rounded,
                    size: 20, color: CaptainTheme.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: CaptainTheme.strongText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CaptainTheme.mutedText,
              ),
            ),
            const SizedBox(height: 14),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'No waste-type breakdown was recorded for this collection.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: CaptainTheme.mutedText,
                  ),
                ),
              )
            else ...[
              for (final row in rows) _WasteBreakdownTile(row: row),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: CaptainTheme.strongText,
                    ),
                  ),
                  Text(
                    '${total.toStringAsFixed(2)} kg',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: CaptainTheme.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 4),
              _CollectionPhotoThumbnail(imageUrl: imageUrl),
              const SizedBox(height: 10),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Thumbnail of the collection's proof photo — tap to expand into a
/// floating, zoomable full-size preview.
class _CollectionPhotoThumbnail extends StatelessWidget {
  const _CollectionPhotoThumbnail({required this.imageUrl});

  final String imageUrl;

  void _showFullImage(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Icon(Icons.broken_image_outlined,
                        size: 40, color: Colors.white70),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -12,
              right: -12,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded,
                        size: 22, color: Colors.black87),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Image.network(
              imageUrl,
              width: double.infinity,
              height: 120,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 120,
                  alignment: Alignment.center,
                  color: CaptainTheme.surface.withValues(alpha: 0.5),
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                height: 120,
                alignment: Alignment.center,
                color: CaptainTheme.surface.withValues(alpha: 0.5),
                child: Icon(Icons.broken_image_outlined,
                    size: 26, color: CaptainTheme.mutedText),
              ),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.zoom_in_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WasteBreakdownTile extends StatelessWidget {
  const _WasteBreakdownTile({required this.row});

  final WasteBreakdownRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: CaptainTheme.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.wasteType,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: CaptainTheme.strongText,
              ),
            ),
          ),
          Text(
            '${row.weightKg.toStringAsFixed(2)} kg',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: CaptainTheme.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}
