import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_multiselect_sheet.dart';
import 'package:iwms_citizen_app/shared/widgets/keyboard_safe_bottom_sheet.dart';

/// "Form ALT" — creates a new `AlternativeStaffTemplate` (staff substitution)
/// under the supervisor's own hierarchy. Pops `true` on success so the caller
/// can refresh its alt-template dropdown.
class SupervisorAltStaffTemplateForm extends StatefulWidget {
  const SupervisorAltStaffTemplateForm({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SupervisorAltStaffTemplateForm(),
    );
  }

  @override
  State<SupervisorAltStaffTemplateForm> createState() =>
      _SupervisorAltStaffTemplateFormState();
}

class _SupervisorAltStaffTemplateFormState
    extends State<SupervisorAltStaffTemplateForm> {
  final SupervisorRepository _repo = SupervisorRepository();
  final _reasonController = TextEditingController();

  bool _loadingOptions = true;
  String? _loadError;
  bool _saving = false;
  String? _saveError;

  List<SupervisorTeam> _templates = const [];
  List<SupervisorCrewOption> _drivers = const [];
  List<SupervisorCrewOption> _operators = const [];

  String? _staffTemplateId;
  String? _driverId;
  String? _operatorId;
  List<SupervisorCrewOption> _extraOperators = const [];
  DateTime _fromDate = DateTime.now();
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadingOptions = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _repo.fetchTeams(),
        _repo.fetchDrivers(),
        _repo.fetchOperators(),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<SupervisorTeam>;
        _drivers = results[1] as List<SupervisorCrewOption>;
        _operators = results[2] as List<SupervisorCrewOption>;
        _loadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loadingOptions = false;
      });
    }
  }

  /// Prefills driver/operator from the picked team so the supervisor doesn't
  /// have to re-select staff that's already obvious from the chosen team —
  /// only when the team's own driver/operator are present in the (unfiltered)
  /// _drivers/_operators lists, so the dropdown value is never invalid.
  void _onStaffTemplateChanged(String? templateId) {
    SupervisorTeam? team;
    for (final t in _templates) {
      if (t.uniqueId == templateId) {
        team = t;
        break;
      }
    }
    setState(() {
      _staffTemplateId = templateId;
      if (team != null) {
        if (_drivers.any((d) => d.uniqueId == team!.driverId)) {
          _driverId = team.driverId;
        }
        if (_operators.any((o) => o.uniqueId == team!.operatorId)) {
          _operatorId = team.operatorId;
        }
      }
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : (_toDate ?? _fromDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate != null && _toDate!.isBefore(_fromDate)) _toDate = null;
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _pickExtraOperators() async {
    final candidates =
        _operators.where((o) => o.uniqueId != _operatorId).toList();
    final result = await SupervisorMultiSelectSheet.show(
      context,
      title: 'Extra operators',
      options: candidates,
      initiallySelected: _extraOperators,
    );
    if (result != null) setState(() => _extraOperators = result);
  }

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool get _canSave =>
      _staffTemplateId != null &&
      _driverId != null &&
      _operatorId != null &&
      _reasonController.text.trim().isNotEmpty &&
      !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _repo.createAlternativeStaffTemplate(
        staffTemplateId: _staffTemplateId!,
        driverId: _driverId!,
        operatorId: _operatorId!,
        extraOperatorIds: _extraOperators.map((o) => o.uniqueId).toList(),
        fromDate: _fmt(_fromDate),
        toDate: _fmt(_toDate ?? _fromDate),
        changeReason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
          maxHeight: MediaQuery.sizeOf(context).height * 0.9 - keyboardInset,
        ),
        decoration: const BoxDecoration(
          color: SupervisorTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SupervisorTheme.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'New alternative staff template',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText,
                  ),
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
    if (_loadingOptions) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: SupervisorTheme.accent),
        ),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!,
                style: const TextStyle(color: SupervisorTheme.mutedText)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: SupervisorTheme.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dropdown<String>(
            label: 'Staff template',
            value: _staffTemplateId,
            items: _templates
                .map((t) => DropdownMenuItem(
                      value: t.uniqueId,
                      child: Text(
                        '${t.driverName} / ${t.operatorName}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: _onStaffTemplateChanged,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _dateField('From date', _fromDate, true)),
              const SizedBox(width: 12),
              Expanded(
                child: _dateField('To date', _toDate ?? _fromDate, false),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _dropdown<String>(
            label: 'Driver',
            value: _driverId,
            items: _drivers
                .map((d) => DropdownMenuItem(
                      value: d.uniqueId,
                      child: Text(d.name, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _driverId = v),
          ),
          const SizedBox(height: 14),
          _dropdown<String>(
            label: 'Operator',
            value: _operatorId,
            items: _operators
                .map((o) => DropdownMenuItem(
                      value: o.uniqueId,
                      child: Text(o.name, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _operatorId = v),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _pickExtraOperators,
            child: InputDecorator(
              decoration: SupervisorTheme.inputDecoration('Extra operators'),
              child: Text(
                _extraOperators.isEmpty
                    ? 'None selected'
                    : _extraOperators.map((o) => o.name).join(', '),
                overflow: TextOverflow.ellipsis,
                style: SupervisorTheme.inputTextStyle,
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reasonController,
            style: SupervisorTheme.inputTextStyle,
            decoration: SupervisorTheme.inputDecoration('Change reason'),
            onChanged: (_) => setState(() {}),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 10),
            Text(_saveError!,
                style: const TextStyle(color: SupervisorTheme.danger)),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SupervisorTheme.mutedText,
                    side: BorderSide(
                      color: SupervisorTheme.hairline.withValues(alpha: 0.8),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _canSave ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SupervisorTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateField(String label, DateTime value, bool isFrom) {
    return InkWell(
      onTap: () => _pickDate(isFrom: isFrom),
      child: InputDecorator(
        decoration: SupervisorTheme.inputDecoration(label),
        child: Text(_fmt(value), style: SupervisorTheme.inputTextStyle),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      style: SupervisorTheme.inputTextStyle,
      dropdownColor: SupervisorTheme.surface,
      decoration: SupervisorTheme.inputDecoration(label),
      items: items,
      onChanged: onChanged,
    );
  }
}
