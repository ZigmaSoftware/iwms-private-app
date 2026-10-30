import 'package:flutter/material.dart';

/// Full-screen, pinch-to-zoom view of an evidence photo. Tap anywhere or the
/// close button to dismiss.
Future<void> showSupervisorPhoto(BuildContext context, String url) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) => GestureDetector(
      onTap: () => Navigator.of(dialogContext).pop(),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: Image.network(
                url,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              tooltip: 'Close photo',
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A row of square photo thumbnails that open [showSupervisorPhoto].
class SupervisorPhotoStrip extends StatelessWidget {
  const SupervisorPhotoStrip({super.key, required this.urls, this.size = 56});

  final List<String> urls;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Semantics(
          button: true,
          label: 'View photo ${i + 1}',
          child: GestureDetector(
            onTap: () => showSupervisorPhoto(context, urls[i]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                urls[i],
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: size,
                  height: size,
                  color: const Color(0xFFEDEBE5),
                  child: const Icon(Icons.broken_image_outlined,
                      size: 20, color: Color(0xFF63615C)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
