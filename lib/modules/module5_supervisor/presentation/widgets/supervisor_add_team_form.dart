import 'package:flutter/material.dart';

import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/data/models/user_model.dart';
import 'package:iwms_private_app/data/repositories/auth_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_multiselect_sheet.dart';

/// Teams "+Add" — creates a new `StaffTemplate` (driver + operator + extra
/// operators) under the supervisor's own geo hierarchy, read from their login
/// profile (`UserModel.geoScope`) since a brand-new template has no parent
/// record to inherit geo from. Pops `true` on success.
///
/// Also doubles as the "Edit team" form when [existingTeam] is passed: the
/// driver/operator prefill from it, the available-staff lookups exclude only
/// its OWN busy slots (so its current driver/operator still show up), and
/// saving calls `updateStaffTemplate` instead of `createStaffTemplate`.
class SupervisorAddTeamForm extends StatefulWidget {
  const SupervisorAddTeamForm({super.key, this.existingTeam});

  final SupervisorTeam? existingTeam;

  static Future<bool?> show(BuildContext context, {SupervisorTeam? existingTeam}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupervisorAddTeamForm(existingTeam: existingTeam),
    );
  }

  @override
  State<SupervisorAddTeamForm> createState() => _SupervisorAddTeamFormState();
}

class _SupervisorAddTeamFormState extends State<SupervisorAddTeamForm> {
  final SupervisorRepository _repo = SupervisorRepository();

  bool _loadingOptions = true;
  String? _loadError;
  bool _saving = false;
  String? _saveError;

  List<SupervisorCrewOption> _drivers = const [];
  List<SupervisorCrewOption> _operators = const [];
  GeoScope? _geoScope;

  String? _driverId;
  String? _operatorId;
  List<SupervisorCrewOption> _extraOperators = const [];

  bool get _isEdit => widget.existingTeam != null;

  @override
  void initState() {
    super.initState();
    _driverId = widget.existingTeam?.driverId;
    _operatorId = widget.existingTeam?.operatorId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadingOptions = true;
      _loadError = null;
    });
    try {
      // Excludes staff already driver/operator on another active team, so a
      // team member can't be double-booked into a second team. When editing,
      // this team's OWN current driver/operator are excluded from the
      // exclusion (still shown), since they're only "busy" on this template.
      final excludeId = widget.existingTeam?.uniqueId;
      final results = await Future.wait([
        _repo.fetchAvailableDrivers(excludeTemplateId: excludeId),
        _repo.fetchAvailableOperators(excludeTemplateId: excludeId),
      ]);
      final user = await getIt<AuthRepository>().getAuthenticatedUser();
      if (!mounted) return;
      setState(() {
        _drivers = results[0];
        _operators = results[1];
        _geoScope = user?.geoScope;
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

  bool get _canSave => _driverId != null && _operatorId != null && !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final extraIds = _extraOperators.map((o) => o.uniqueId).toList();
      if (_isEdit) {
        await _repo.updateStaffTemplate(
          uniqueId: widget.existingTeam!.uniqueId,
          driverId: _driverId!,
          operatorId: _operatorId!,
          extraOperatorIds: extraIds,
        );
      } else {
        await _repo.createStaffTemplate(
          driverId: _driverId!,
          operatorId: _operatorId!,
          extraOperatorIds: extraIds,
          geo: _geoScope,
        );
      }
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
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                _isEdit ? 'Edit team' : 'Add team',
                style: const TextStyle(
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
          if (!_isEdit && (_geoScope == null || _geoScope!.isEmpty))
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Your account has no geo hierarchy on file — the new team '
                'will be created without a geo scope.',
                style: TextStyle(fontSize: 12, color: SupervisorTheme.warning),
              ),
            ),
          DropdownButtonFormField<String>(
            value: _driverId,
            isExpanded: true,
            style: SupervisorTheme.inputTextStyle,
            dropdownColor: SupervisorTheme.surface,
            decoration: SupervisorTheme.inputDecoration('Driver'),
            items: _drivers
                .map((d) => DropdownMenuItem(
                      value: d.uniqueId,
                      child: Text(d.name, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _driverId = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _operatorId,
            isExpanded: true,
            style: SupervisorTheme.inputTextStyle,
            dropdownColor: SupervisorTheme.surface,
            decoration: SupervisorTheme.inputDecoration('Operator'),
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
}
