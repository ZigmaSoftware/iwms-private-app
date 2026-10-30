import 'package:flutter/material.dart';

import 'package:iwms_private_app/data/models/vehicle_breakdown_models.dart';
import 'package:iwms_private_app/data/repositories/vehicle_breakdown_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// "Change vehicle" for a trip that hasn't started — the fix for a trip
/// blocked because its vehicle is under breakdown (helpDoc
/// 11-vehicle-breakdown.md, P4). The crew stays the same.
///
/// Lists the vehicles `available-vehicles` offers for the trip's date:
/// active, not under breakdown and without another trip that day.
class SupervisorChangeVehicleSheet extends StatefulWidget {
  const SupervisorChangeVehicleSheet._({
    required this.assignmentId,
    required this.tripDate,
    required this.currentVehicleNo,
  });

  final String assignmentId;
  final DateTime tripDate;
  final String currentVehicleNo;

  /// Returns true when the vehicle was changed.
  static Future<bool?> show(
    BuildContext context, {
    required String assignmentId,
    DateTime? tripDate,
    String currentVehicleNo = '',
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupervisorChangeVehicleSheet._(
        assignmentId: assignmentId,
        tripDate: tripDate ?? DateTime.now(),
        currentVehicleNo: currentVehicleNo,
      ),
    );
  }

  @override
  State<SupervisorChangeVehicleSheet> createState() =>
      _SupervisorChangeVehicleSheetState();
}

class _SupervisorChangeVehicleSheetState
    extends State<SupervisorChangeVehicleSheet> {
  final VehicleBreakdownRepository _vehicles = VehicleBreakdownRepository();
  final SupervisorRepository _repo = SupervisorRepository();

  bool _loading = true;
  String? _loadError;
  List<VehicleBreakdownOption> _options = const [];
  String? _selectedId;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final options = await _vehicles.fetchAvailableVehicles(widget.tripDate);
      if (!mounted) return;
      setState(() {
        _options = options;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final id = _selectedId;
    if (id == null || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _repo.changeTripVehicle(widget.assignmentId, id);
      if (!mounted) return;
      final label = _options.firstWhere((o) => o.uniqueId == id).label;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Trip moved to $label.')),
      );
    } on SupervisorException catch (e) {
      if (!mounted) return;
      setState(() {
        _saveError = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: SupervisorTheme.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'Change vehicle',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: SupervisorTheme.strongText,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '${widget.currentVehicleNo.isEmpty ? 'The vehicle' : widget.currentVehicleNo} '
              'is under breakdown. The trip keeps its crew.',
              style: const TextStyle(
                color: SupervisorTheme.mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(child: _body()),
          if (_saveError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                _saveError!,
                style: const TextStyle(color: SupervisorTheme.danger),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
            child: ElevatedButton(
              onPressed: _selectedId == null || _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: SupervisorTheme.success,
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
                  : const Text('Change vehicle'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
            child: CircularProgressIndicator(color: SupervisorTheme.accent)),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_loadError!,
                style: const TextStyle(color: SupervisorTheme.mutedText)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(
          'No vehicle is free that day. The trip stays blocked until a '
          'vehicle frees up or this one is marked repaired.',
          style: TextStyle(
            color: SupervisorTheme.danger,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final o in _options)
          ListTile(
            onTap: _saving ? null : () => setState(() => _selectedId = o.uniqueId),
            leading: Icon(
              _selectedId == o.uniqueId
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: _selectedId == o.uniqueId
                  ? SupervisorTheme.accent
                  : SupervisorTheme.mutedText,
            ),
            title: Text(
              o.label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: SupervisorTheme.strongText,
              ),
            ),
          ),
      ],
    );
  }
}
