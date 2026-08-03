import 'package:flutter/material.dart';

/// Wrap a bottom-sheet form's root widget with this so:
///
/// 1. Tapping anywhere on the sheet (outside a text field) dismisses the
///    keyboard — `showModalBottomSheet` doesn't do this itself, so without
///    it the keyboard stays open no matter where else you tap.
/// 2. The sheet's bottom padding grows by the keyboard's height, so a
///    Save/Cancel row pinned near the bottom is pushed up above the
///    keyboard instead of being hidden behind it — `showModalBottomSheet`
///    does NOT automatically inset for `viewInsets` the way `Scaffold` does.
///
/// Use it as the outermost widget returned by a sheet's `build()`:
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   return KeyboardSafeBottomSheet(
///     child: Container(...),
///   );
/// }
/// ```
class KeyboardSafeBottomSheet extends StatelessWidget {
  const KeyboardSafeBottomSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: child,
      ),
    );
  }
}
