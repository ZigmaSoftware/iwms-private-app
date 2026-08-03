import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';

import 'package:iwms_citizen_app/core/di.dart';
import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';
import 'package:iwms_citizen_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_citizen_app/data/repositories/vehicle_breakdown_repository.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_citizen_app/modules/module3_operator/services/image_compress_service.dart';
import 'package:iwms_citizen_app/shared/widgets/keyboard_safe_bottom_sheet.dart';

Color _assignmentTypeColor(String? type) {
  switch (type) {
    case 'household_collection':
      return CaptainTheme.success;
    case 'bulk_waste_collection':
      return CaptainTheme.warning;
    case 'bin_collection':
    default:
      return CaptainTheme.primary;
  }
}

Widget _assignmentTypeChip(String? collectionType, String label) {
  if (label.isEmpty) return const SizedBox.shrink();
  final color = _assignmentTypeColor(collectionType);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: CaptainTheme.chipRadius,
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );
}

InputDecoration _fieldDecoration(String label) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: CaptainTheme.hairline),
  );
  return InputDecoration(
    labelText: label,
    labelStyle:
        TextStyle(color: CaptainTheme.mutedText, fontWeight: FontWeight.w500),
    filled: true,
    fillColor: CaptainTheme.surfaceMuted,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: CaptainTheme.accent, width: 1.4),
    ),
  );
}

TextStyle _fieldTextStyle() =>
    TextStyle(color: CaptainTheme.strongText, fontWeight: FontWeight.w600);

Widget _sheetHandle() {
  return Center(
    child: Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: CaptainTheme.hairline,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// Step 1: pick which of today's assignments the breakdown is on.
class DriverAssignmentPickerSheet extends StatefulWidget {
  const DriverAssignmentPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DriverAssignmentPickerSheet(),
    );
  }

  @override
  State<DriverAssignmentPickerSheet> createState() =>
      _DriverAssignmentPickerSheetState();
}

class _DriverAssignmentPickerSheetState
    extends State<DriverAssignmentPickerSheet> {
  final OperatorTripRepository _tripRepo = getIt<OperatorTripRepository>();

  bool _loading = true;
  String? _error;
  List<OperatorTripToday> _assignments = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final assignments = await _tripRepo.fetchMyTripsToday();
      if (!mounted) return;
      setState(() {
        _assignments = assignments;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _label(OperatorTripToday a) {
    final area = a.ward?.name ?? a.panchayat?.name ?? '';
    final vehicle = a.vehicle?.vehicleNo ?? '';
    final parts = [area, vehicle].where((v) => v.isNotEmpty);
    return parts.isEmpty ? a.assignmentUniqueId : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      decoration: BoxDecoration(
        color: CaptainTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Select a trip',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: CaptainTheme.strongText,
                ),
              ),
            ),
            Flexible(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: CaptainTheme.accent),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: CaptainTheme.mutedText)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: CaptainTheme.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_assignments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Text(
          'No trips assigned to you today.',
          style: TextStyle(color: CaptainTheme.mutedText),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _assignments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final a = _assignments[i];
        final hasVehicle = a.vehicle != null && a.vehicle!.uniqueId.isNotEmpty;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: !hasVehicle
                ? null
                : () {
                    Navigator.of(context).pop();
                    DriverVehicleBreakdownForm.show(context, assignment: a);
                  },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: CaptainTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: CaptainTheme.hairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_shipping_outlined,
                      color: CaptainTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _label(a),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: CaptainTheme.strongText,
                          ),
                        ),
                        if (a.assignmentTypeLabel.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _assignmentTypeChip(
                              a.collectionType, a.assignmentTypeLabel),
                        ],
                      ],
                    ),
                  ),
                  if (!hasVehicle)
                    Text(
                      'No vehicle',
                      style: TextStyle(
                          fontSize: 11, color: CaptainTheme.mutedText),
                    )
                  else
                    Icon(Icons.chevron_right_rounded,
                        color: CaptainTheme.mutedText),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

const List<String> _breakdownReasons = [
  'FLAT_TYRE',
  'ENGINE_FAILURE',
  'ACCIDENT',
  'ELECTRICAL',
  'OVERHEATING',
  'OTHER',
];

String _reasonLabel(String v) => v
    .split('_')
    .map((w) => w.isEmpty ? '' : '${w[0]}${w.substring(1).toLowerCase()}')
    .join(' ');

/// Step 2: report the breakdown + pick the replacement plan.
class DriverVehicleBreakdownForm extends StatefulWidget {
  const DriverVehicleBreakdownForm({super.key, required this.assignment});

  final OperatorTripToday assignment;

  static Future<void> show(
    BuildContext context, {
    required OperatorTripToday assignment,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DriverVehicleBreakdownForm(assignment: assignment),
    );
  }

  @override
  State<DriverVehicleBreakdownForm> createState() =>
      _DriverVehicleBreakdownFormState();
}

class _DriverVehicleBreakdownFormState
    extends State<DriverVehicleBreakdownForm> {
  final VehicleBreakdownRepository _repo = VehicleBreakdownRepository();
  final ImagePicker _picker = ImagePicker();
  final _locationController = TextEditingController();
  final _weightController = TextEditingController();
  final _remarksController = TextEditingController();

  bool _saving = false;
  String? _saveError;
  bool _detectingLocation = false;

  String _reason = _breakdownReasons.last;
  double? _lat;
  double? _lng;
  final List<File> _photos = [];

  @override
  void initState() {
    super.initState();
    _resolveLocation();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _weightController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _resolveLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 4));
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
      });
    } catch (_) {
      // Location is best-effort — the report still works without it.
    }
  }

  Future<void> _autoDetectLocation() async {
    setState(() => _detectingLocation = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 8));
      _lat = position.latitude;
      _lng = position.longitude;

      final placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.name,
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.postalCode,
        ].where((v) => v != null && v.trim().isNotEmpty).toSet();
        _locationController.text = parts.join(', ');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not detect location: $e')),
      );
    } finally {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  Future<void> _addPhoto(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;
    final compressed = await ImageCompressService.compress(File(picked.path));
    if (!mounted) return;
    setState(() => _photos.add(compressed));
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  Future<void> _showPhotoSourcePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: CaptainTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(Icons.photo_camera_outlined, color: CaptainTheme.accent),
              title: Text('Take photo', style: _fieldTextStyle()),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _addPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: CaptainTheme.accent),
              title: Text('Choose from gallery', style: _fieldTextStyle()),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _addPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSave => !_saving;

  Future<void> _submit() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final weight = double.tryParse(_weightController.text.trim());
      await _repo.createBreakdown(
        tripAssignmentId: widget.assignment.assignmentUniqueId,
        breakdownVehicleId: widget.assignment.vehicle!.uniqueId,
        breakdownReason: _reason,
        breakdownTime: DateTime.now(),
        breakdownLat: _lat,
        breakdownLng: _lng,
        breakdownLocation: _locationController.text.trim(),
        collectedWeightBeforeBreakdownKg: weight,
        breakdownRemarks: _remarksController.text.trim(),
        photos: _photos,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Breakdown reported. Your supervisor has been notified.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveError = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return KeyboardSafeBottomSheet(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92 - keyboardInset,
        ),
        decoration: BoxDecoration(
          color: CaptainTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Report vehicle breakdown',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: CaptainTheme.strongText,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Text(
                      'Vehicle: ${widget.assignment.vehicle?.vehicleNo ?? '—'}',
                      style: TextStyle(
                          color: CaptainTheme.mutedText,
                          fontWeight: FontWeight.w600),
                    ),
                    if (widget.assignment.assignmentTypeLabel.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _assignmentTypeChip(
                        widget.assignment.collectionType,
                        widget.assignment.assignmentTypeLabel,
                      ),
                    ],
                  ],
                ),
              ),
              Flexible(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 16 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _reason,
            isExpanded: true,
            style: _fieldTextStyle(),
            dropdownColor: CaptainTheme.surface,
            decoration: _fieldDecoration('Breakdown reason'),
            items: _breakdownReasons
                .map((r) =>
                    DropdownMenuItem(value: r, child: Text(_reasonLabel(r))))
                .toList(),
            onChanged: (v) => setState(() => _reason = v ?? _reason),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _locationController,
            style: _fieldTextStyle(),
            decoration: _fieldDecoration('Breakdown location').copyWith(
              suffixIcon: _detectingLocation
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: CaptainTheme.accent,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: Icon(Icons.my_location_rounded,
                          color: CaptainTheme.accent),
                      tooltip: 'Auto detect',
                      onPressed: _autoDetectLocation,
                    ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: _fieldTextStyle(),
            decoration:
                _fieldDecoration('Collected weight before breakdown (kg)'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _remarksController,
            style: _fieldTextStyle(),
            decoration: _fieldDecoration('Remarks'),
          ),
          const SizedBox(height: 20),
          Text(
            'Photos',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: CaptainTheme.strongText,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                if (i == _photos.length) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showPhotoSourcePicker(),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: CaptainTheme.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: CaptainTheme.hairline),
                      ),
                      child: Icon(Icons.add_a_photo_outlined,
                          color: CaptainTheme.accent),
                    ),
                  );
                }
                final photo = _photos[i];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        photo,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () => _removePhoto(i),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 10),
            Text(_saveError!, style: TextStyle(color: CaptainTheme.danger)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canSave ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: CaptainTheme.danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Report'),
            ),
          ),
        ],
      ),
    );
  }
}
