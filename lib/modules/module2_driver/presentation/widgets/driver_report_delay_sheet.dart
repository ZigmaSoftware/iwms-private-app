import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/core/ui/app_flash.dart';
import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_private_app/data/repositories/trip_delay_repository.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';

/// "Report delay" — for everything that slows a trip down WITHOUT taking the
/// vehicle out of service: a puncture, a minor repair, a blocked road.
///
/// Deliberately a single screen, unlike the breakdown flow's assignment ->
/// vehicle -> replacement-crew wizard. A delayed driver is standing at the
/// roadside wanting to get moving again, so the only required inputs are a
/// reason chip and the remarks; the trip is auto-selected when the driver has
/// just one today, and location is attached silently.
class DriverReportDelaySheet extends StatefulWidget {
  const DriverReportDelaySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DriverReportDelaySheet(),
    );
  }

  @override
  State<DriverReportDelaySheet> createState() => _DriverReportDelaySheetState();
}

class _DriverReportDelaySheetState extends State<DriverReportDelaySheet> {
  final TripDelayRepository _delayRepo = getIt<TripDelayRepository>();
  final OperatorTripRepository _tripRepo = getIt<OperatorTripRepository>();
  final TextEditingController _remarksCtrl = TextEditingController();
  final TextEditingController _minutesCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  String? _error;

  List<OperatorTripToday> _trips = const [];
  String? _assignmentId;
  String? _reason;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final trips = await _tripRepo.fetchMyTripsToday();
      if (!mounted) return;
      setState(() {
        // Only trips still running can be delayed — a closed one is history.
        _trips = trips.where((t) => !t.isClosed).toList();
        // One trip is the overwhelmingly common case; pre-select it so the
        // driver never taps a picker with a single option in it.
        _assignmentId =
            _trips.length == 1 ? _trips.first.assignmentUniqueId : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load your trips. $e';
        _loading = false;
      });
    }
  }

  Future<Position?> _currentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 4));
    } catch (_) {
      // Best-effort: a delay must be reportable with GPS off.
      return null;
    }
  }

  Future<void> _submit() async {
    final assignmentId = _assignmentId;
    final reason = _reason;
    final remarks = _remarksCtrl.text.trim();

    if (assignmentId == null) {
      setState(() => _error = 'Select which trip is delayed.');
      return;
    }
    if (reason == null) {
      setState(() => _error = 'Pick what caused the delay.');
      return;
    }
    if (remarks.isEmpty) {
      setState(() => _error = 'Describe what happened.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final location = await _currentLocation();
    try {
      await _delayRepo.reportDelay(
        assignmentId: assignmentId,
        reason: reason,
        remarks: remarks,
        estimatedMinutes: int.tryParse(_minutesCtrl.text.trim()),
        latitude: location?.latitude,
        longitude: location?.longitude,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      AppFlash.success(context, 'Delay reported. Your supervisor is notified.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: ColoredBox(
          color: CaptainTheme.surface,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: CaptainTheme.hairline,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.timer_outlined,
                            color: CaptainTheme.warning, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Report delay',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: CaptainTheme.strongText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'For hold-ups that do not stop the vehicle. '
                      'If the vehicle cannot run, report a breakdown instead.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: CaptainTheme.mutedText,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_loadError != null)
                      _banner(_loadError!, CaptainTheme.danger)
                    else if (_trips.isEmpty)
                      _banner(
                        'You have no running trip today to report a delay on.',
                        CaptainTheme.mutedText,
                      )
                    else ...[
                      // Picker only when it is a real choice.
                      if (_trips.length > 1) ...[
                        _label('Which trip'),
                        const SizedBox(height: 6),
                        _tripPicker(),
                        const SizedBox(height: 14),
                      ],
                      _label('What happened'),
                      const SizedBox(height: 8),
                      _reasonChips(),
                      const SizedBox(height: 14),
                      _label('Remarks'),
                      const SizedBox(height: 6),
                      _remarksField(),
                      const SizedBox(height: 14),
                      _label('Delay (minutes, optional)'),
                      const SizedBox(height: 6),
                      _minutesField(),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _banner(_error!, CaptainTheme.danger),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CaptainTheme.warning,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Report delay',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: CaptainTheme.mutedText,
        ),
      );

  Widget _banner(String message, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          message,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );

  Widget _tripPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: CaptainTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CaptainTheme.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _assignmentId,
          hint: const Text('Select trip'),
          items: [
            for (final trip in _trips)
              DropdownMenuItem(
                value: trip.assignmentUniqueId,
                child: Text(
                  [
                    trip.ward?.name ?? trip.panchayat?.name ?? '',
                    trip.vehicle?.vehicleNo ?? '',
                    trip.scheduledTimeLabel,
                  ].where((v) => v.isNotEmpty).join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _submitting
              ? null
              : (value) => setState(() => _assignmentId = value),
        ),
      ),
    );
  }

  Widget _reasonChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final reason in TripDelayRepository.reasons)
          ChoiceChip(
            label: Text(reason.label),
            selected: _reason == reason.code,
            onSelected: _submitting
                ? null
                : (_) => setState(() => _reason = reason.code),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _reason == reason.code
                  ? Colors.white
                  : CaptainTheme.strongText,
            ),
            selectedColor: CaptainTheme.warning,
            backgroundColor: CaptainTheme.surfaceMuted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: CaptainTheme.hairline),
            ),
          ),
      ],
    );
  }

  Widget _remarksField() {
    return TextField(
      controller: _remarksCtrl,
      enabled: !_submitting,
      minLines: 3,
      maxLines: 5,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'e.g. Rear left tyre punctured near Pari Chowk, '
            'changing the spare now.',
        filled: true,
        fillColor: CaptainTheme.surfaceMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: CaptainTheme.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: CaptainTheme.hairline),
        ),
      ),
    );
  }

  Widget _minutesField() {
    return TextField(
      controller: _minutesCtrl,
      enabled: !_submitting,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        hintText: 'e.g. 30',
        suffixText: 'min',
        filled: true,
        fillColor: CaptainTheme.surfaceMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: CaptainTheme.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: CaptainTheme.hairline),
        ),
      ),
    );
  }
}
