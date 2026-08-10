import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:geolocator/geolocator.dart';

import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';

/// Modal sheet for confirming a bin collection.
///
/// Visual language matches the operator Home page: a charcoal gradient header,
/// white inner card with bin / CP details, accent-green CTA.
class BinDetailSheet extends StatefulWidget {
  final BinScanValidateResult validation;

  const BinDetailSheet({super.key, required this.validation});

  @override
  State<BinDetailSheet> createState() => _BinDetailSheetState();
}

class _BinDetailSheetState extends State<BinDetailSheet> {
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  bool _submitting = false;
  bool _statusSubmitting = false;
  String? _errorMessage;

  OperatorTripRepository get _repo => GetIt.instance<OperatorTripRepository>();

  @override
  void dispose() {
    _weightCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _weightCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _errorMessage = 'Please enter waste weight.');
      return;
    }
    final weight = double.tryParse(raw);
    if (weight == null || weight <= 0) {
      setState(() => _errorMessage = 'Enter a valid weight greater than 0.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final location = await _currentLocation();

    try {
      final result = await _repo.scanBin(
        binQr: widget.validation.bin.scanValue,
        weightKg: weight,
        latitude: location?.latitude,
        longitude: location?.longitude,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on OperatorTripException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = _friendlyMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = 'Could not submit. Please try again.';
      });
    }
  }

  Future<Position?> _currentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 4));
    } catch (_) {
      // Location is best-effort.
      return null;
    }
  }

  Future<void> _openStatusReasonSheet({
    required String action,
    required String title,
    required List<String> quickReasons,
  }) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: CaptainTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _StatusReasonSheet(
        title: title,
        quickReasons: quickReasons,
      ),
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;

    setState(() {
      _statusSubmitting = true;
      _errorMessage = null;
    });

    final location = await _currentLocation();
    try {
      final result = await _repo.scanBin(
        binQr: widget.validation.bin.scanValue,
        action: action,
        latitude: location?.latitude,
        longitude: location?.longitude,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        statusReason: reason.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on OperatorTripException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusSubmitting = false;
        _errorMessage = _friendlyMessage(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusSubmitting = false;
        _errorMessage = 'Could not save status. Please try again.';
      });
    }
  }

  String _friendlyMessage(OperatorTripException e) {
    switch (e.code) {
      case 'WRONG_WASTE_TYPE':
        return e.message;
      case 'WRONG_PANCHAYAT':
        return 'This bin is outside your assigned area.';
      case 'ALREADY_COLLECTED':
        return 'This bin was already collected.';
      case 'ALREADY_MISSED':
        return 'This collection point is already marked not available.';
      case 'BIN_NOT_FOUND':
        return 'Bin not found.';
      case 'NO_ACTIVE_TRIP':
        return 'You have no active trip today.';
      case 'TRIP_NOT_STARTED':
        return 'Start the trip before collecting. Press "Start Trip" first.';
      case 'WEIGHT_EXCEEDS_CAPACITY':
        return e.message;
      default:
        return e.message.isEmpty ? 'Submission failed.' : e.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bin = widget.validation.bin;
    final cp = widget.validation.collectionPoint;
    final progress = widget.validation.progress;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ColoredBox(
            color: CaptainTheme.background,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(bin: bin, progress: progress),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _InfoCard(
                            icon: Icons.location_on_outlined,
                            title: 'Collection point',
                            primary: cp.name,
                            secondary: (cp.latitude != null &&
                                    cp.longitude != null)
                                ? '${cp.latitude!.toStringAsFixed(5)}, ${cp.longitude!.toStringAsFixed(5)}'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          _InfoCard(
                            icon: Icons.task_alt_rounded,
                            title: 'Trip progress',
                            primary:
                                '${progress.collected}/${progress.total} CPs collected',
                            secondary: progress.completed
                                ? 'All bins on this trip are now done.'
                                : 'Scan the next bin to continue.',
                            accent: progress.completed
                                ? CaptainTheme.success
                                : CaptainTheme.accent,
                          ),
                          const SizedBox(height: 18),
                          const _SectionLabel('Waste weight'),
                          const SizedBox(height: 6),
                          _WeightField(controller: _weightCtrl),
                          const SizedBox(height: 14),
                          const _SectionLabel('Notes (optional)'),
                          const SizedBox(height: 6),
                          _NotesField(controller: _notesCtrl),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 12),
                            _ErrorBanner(message: _errorMessage!),
                          ],
                          const SizedBox(height: 20),
                          _SubmitButton(
                            loading: _submitting,
                            onTap: (_submitting || _statusSubmitting)
                                ? null
                                : _submit,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _StatusActionButton(
                                  label: 'Collect later',
                                  icon: Icons.schedule_rounded,
                                  color: CaptainTheme.gold,
                                  loading: _statusSubmitting,
                                  onTap: (_submitting || _statusSubmitting)
                                      ? null
                                      : () => _openStatusReasonSheet(
                                            action: 'collect_later',
                                            title:
                                                'Why should this bin be collected later?',
                                            quickReasons: const [
                                              'Waste not ready',
                                              'Road blocked',
                                              'Asked to return later',
                                              'Vehicle capacity issue',
                                            ],
                                          ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatusActionButton(
                                  label: 'Not available',
                                  icon: Icons.report_gmailerrorred_rounded,
                                  color: CaptainTheme.danger,
                                  loading: _statusSubmitting,
                                  onTap: (_submitting || _statusSubmitting)
                                      ? null
                                      : () => _openStatusReasonSheet(
                                            action: 'not_available',
                                            title:
                                                'Why is this bin not available?',
                                            quickReasons: const [
                                              'Bin missing',
                                              'Access locked',
                                              'Contaminated waste',
                                              'Unsafe location',
                                            ],
                                          ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: (_submitting || _statusSubmitting)
                                ? null
                                : () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: CaptainTheme.mutedText,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HEADER  (charcoal gradient, mirrors home _TripHeaderCard)
// ============================================================

class _Header extends StatelessWidget {
  final OperatorTripBinBrief bin;
  final OperatorTripProgress progress;
  const _Header({required this.bin, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: CaptainTheme.headerGradient,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bin.binName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${bin.binQr}  ·  ${bin.binCapacity} L',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.white70,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (bin.wasteType != null) _wasteChip(bin.wasteType!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _wasteChip(OperatorTripWasteType waste) {
    final isWet = waste.isWet;
    final c = isWet ? const Color(0xFF38BDF8) : const Color(0xFFFBBF24);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.22),
        borderRadius: CaptainTheme.chipRadius,
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Text(
        waste.name,
        style: TextStyle(
          color: c,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ============================================================
// SUB-WIDGETS
// ============================================================

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String primary;
  final String? secondary;
  final Color? accent;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.primary,
    this.secondary,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = accent ?? CaptainTheme.accent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CaptainTheme.surface,
        borderRadius: CaptainTheme.cardRadius,
        border: Border.all(color: CaptainTheme.hairline),
        boxShadow: CaptainTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: CaptainTheme.mutedText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  primary,
                  style: TextStyle(
                    fontSize: 15,
                    color: CaptainTheme.strongText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (secondary != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondary!,
                    style: TextStyle(
                      fontSize: 12,
                      color: CaptainTheme.mutedText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: CaptainTheme.mutedText,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _WeightField extends StatelessWidget {
  final TextEditingController controller;
  const _WeightField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: CaptainTheme.strongText,
      ),
      decoration: InputDecoration(
        hintText: 'e.g. 42.5',
        hintStyle: TextStyle(
          color: CaptainTheme.mutedText,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: CaptainTheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: CaptainTheme.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: CaptainTheme.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: CaptainTheme.accent, width: 2),
        ),
        suffixIcon: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          child: Center(
            widthFactor: 1,
            child: Text(
              'kg',
              style: TextStyle(
                color: CaptainTheme.mutedText,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotesField extends StatelessWidget {
  final TextEditingController controller;
  const _NotesField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 1,
      maxLines: 3,
      style: TextStyle(
        fontSize: 14,
        color: CaptainTheme.strongText,
      ),
      decoration: InputDecoration(
        hintText: 'Any remarks for the supervisor',
        hintStyle: TextStyle(color: CaptainTheme.mutedText),
        filled: true,
        fillColor: CaptainTheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: CaptainTheme.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: CaptainTheme.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: CaptainTheme.accent, width: 2),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CaptainTheme.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CaptainTheme.danger.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: CaptainTheme.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: CaptainTheme.danger,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusReasonSheet extends StatefulWidget {
  const _StatusReasonSheet({
    required this.title,
    required this.quickReasons,
  });

  final String title;
  final List<String> quickReasons;

  @override
  State<_StatusReasonSheet> createState() => _StatusReasonSheetState();
}

class _StatusReasonSheetState extends State<_StatusReasonSheet> {
  final TextEditingController _controller = TextEditingController();
  String? _selectedReason;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _errorText = 'Enter a reason before saving.');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: CaptainTheme.strongText,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.quickReasons.map((reason) {
                final selected = _selectedReason == reason;
                return ChoiceChip(
                  label: Text(reason),
                  selected: selected,
                  selectedColor: CaptainTheme.accentSoft,
                  backgroundColor: CaptainTheme.surface,
                  checkmarkColor: CaptainTheme.accentDeep,
                  labelStyle: TextStyle(
                    color: selected
                        ? CaptainTheme.accentDeep
                        : CaptainTheme.strongText,
                    fontWeight: FontWeight.w700,
                  ),
                  side: BorderSide(
                    color:
                        selected ? CaptainTheme.accent : CaptainTheme.hairline,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedReason = reason;
                      _controller.text = reason;
                      _errorText = null;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              cursorColor: CaptainTheme.accent,
              style: TextStyle(
                color: CaptainTheme.strongText,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: 'Enter what happened at this collection point',
                errorText: _errorText,
                labelStyle: TextStyle(color: CaptainTheme.mutedText),
                filled: true,
                fillColor: CaptainTheme.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: CaptainTheme.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: CaptainTheme.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: CaptainTheme.accent, width: 1.4),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: CaptainTheme.danger),
                ),
              ),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: CaptainTheme.accentDeep,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save status'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusActionButton extends StatelessWidget {
  const _StatusActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          : Icon(icon, size: 17),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.48)),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _SubmitButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: onTap == null
                  ? const LinearGradient(
                      colors: [Color(0xFF9CA3AF), Color(0xFF6B7280)],
                    )
                  : CaptainTheme.accentGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: onTap == null ? null : CaptainTheme.softShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : const Text(
                        'Mark Collected',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
