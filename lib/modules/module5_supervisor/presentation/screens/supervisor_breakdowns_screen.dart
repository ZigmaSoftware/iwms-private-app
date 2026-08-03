import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/data/models/vehicle_breakdown_models.dart';
import 'package:iwms_citizen_app/data/repositories/vehicle_breakdown_repository.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_state_views.dart';
import 'package:iwms_citizen_app/shared/widgets/keyboard_safe_bottom_sheet.dart';

/// Vehicle breakdown reports awaiting (or already given) this supervisor's
/// approval — reachable from the Dashboard's "Breakdowns" quick-action tile
/// and from the header bell icon.
class SupervisorBreakdownsScreen extends StatefulWidget {
  const SupervisorBreakdownsScreen({super.key});

  @override
  State<SupervisorBreakdownsScreen> createState() =>
      _SupervisorBreakdownsScreenState();
}

class _SupervisorBreakdownsScreenState
    extends State<SupervisorBreakdownsScreen> {
  final VehicleBreakdownRepository _repo = VehicleBreakdownRepository();

  bool _loading = true;
  String? _error;
  List<VehicleBreakdownReport> _reports = const [];
  final Set<String> _busyIds = {};

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
      final reports = await _repo.fetchBreakdowns();
      if (!mounted) return;
      setState(() {
        _reports = reports;
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

  Future<void> _openReplacementPlan(VehicleBreakdownReport r) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReplacementPlanSheet(report: r, repo: _repo),
    );
    if (result == true) await _load();
  }

  Future<void> _reject(VehicleBreakdownReport r) async {
    final remarks = await _promptRejectionRemarks();
    if (remarks == null) return;
    setState(() => _busyIds.add(r.uniqueId));
    try {
      await _repo.reject(r.uniqueId, rejectionRemarks: remarks);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Breakdown rejected.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _busyIds.remove(r.uniqueId));
    }
  }

  Future<String?> _promptRejectionRemarks() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject breakdown'),
        content: TextField(
          controller: controller,
          style: SupervisorTheme.inputTextStyle,
          decoration: SupervisorTheme.inputDecoration('Rejection reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.of(dialogContext).pop(text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SupervisorTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SupervisorTheme.background,
      appBar: AppBar(
        backgroundColor: SupervisorTheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Breakdowns'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const SupervisorLoadingView();
    if (_error != null) {
      return SupervisorErrorView(message: _error!, onRetry: _load);
    }
    if (_reports.isEmpty) {
      return SupervisorEmptyView(
        message: 'No vehicle breakdown reports.',
        icon: Icons.car_repair_rounded,
        onRefresh: _load,
      );
    }
    return RefreshIndicator(
      color: SupervisorTheme.accent,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        itemCount: _reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _BreakdownCard(
          report: _reports[i],
          busy: _busyIds.contains(_reports[i].uniqueId),
          onArrangeReplacement: () => _openReplacementPlan(_reports[i]),
          onReject: () => _reject(_reports[i]),
        ),
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.report,
    required this.busy,
    required this.onArrangeReplacement,
    required this.onReject,
  });

  final VehicleBreakdownReport report;
  final bool busy;
  final VoidCallback onArrangeReplacement;
  final VoidCallback onReject;

  Color get _statusColor {
    switch (report.approvalStatus.toUpperCase()) {
      case 'APPROVED':
        return SupervisorTheme.success;
      case 'REJECTED':
        return SupervisorTheme.danger;
      default:
        return SupervisorTheme.warning;
    }
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog<void>(
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
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoRow(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: report.photoUrls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final url = report.photoUrls[i];
          return GestureDetector(
            onTap: () => _showFullImage(context, url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                url,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 64,
                  height: 64,
                  color: SupervisorTheme.surfaceMuted,
                  child: const Icon(Icons.broken_image_outlined,
                      size: 20, color: SupervisorTheme.mutedText),
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: 64,
                    height: 64,
                    color: SupervisorTheme.surfaceMuted,
                    child: const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SupervisorTheme.hairline),
        boxShadow: SupervisorTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.car_repair_rounded,
                  color: SupervisorTheme.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  report.breakdownVehicleNo.isEmpty
                      ? 'Vehicle breakdown'
                      : report.breakdownVehicleNo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                  border:
                      Border.all(color: _statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  report.approvalStatus.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Reason: ${report.breakdownReason}',
            style: const TextStyle(
                fontSize: 12.5, color: SupervisorTheme.mutedText),
          ),
          if (report.breakdownLocation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Location: ${report.breakdownLocation}',
              style: const TextStyle(
                  fontSize: 12.5, color: SupervisorTheme.mutedText),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Original crew: ${report.originalDriverName} / ${report.originalOperatorName}',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: SupervisorTheme.strongText),
          ),
          if (report.replacementVehicleNo.isNotEmpty ||
              report.replacementDriverName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Replacement: ${report.replacementVehicleNo} — '
              '${report.replacementDriverName} / ${report.replacementOperatorName}',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: SupervisorTheme.info),
            ),
          ],
          if (report.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Photos',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: SupervisorTheme.mutedText,
              ),
            ),
            const SizedBox(height: 6),
            _photoRow(context),
          ],
          if (report.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SupervisorTheme.danger,
                      side: BorderSide(
                          color: SupervisorTheme.danger.withValues(alpha: 0.4)),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: busy ? null : onArrangeReplacement,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SupervisorTheme.success,
                      foregroundColor: Colors.white,
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Arrange replacement'),
                  ),
                ),
              ],
            ),
          ] else if (report.rejectionRemarks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Rejection reason: ${report.rejectionRemarks}',
              style:
                  const TextStyle(fontSize: 12, color: SupervisorTheme.danger),
            ),
          ],
        ],
      ),
    );
  }
}

/// Drawer opened from "Arrange replacement" — the supervisor picks the
/// replacement vehicle/driver/operator here and approves in one step.
class _ReplacementPlanSheet extends StatefulWidget {
  const _ReplacementPlanSheet({required this.report, required this.repo});

  final VehicleBreakdownReport report;
  final VehicleBreakdownRepository repo;

  @override
  State<_ReplacementPlanSheet> createState() => _ReplacementPlanSheetState();
}

class _ReplacementPlanSheetState extends State<_ReplacementPlanSheet> {
  final _remarksController = TextEditingController();

  bool _loadingOptions = true;
  String? _loadError;
  bool _saving = false;
  String? _saveError;

  List<VehicleBreakdownOption> _vehicles = const [];
  List<VehicleBreakdownOption> _drivers = const [];
  List<VehicleBreakdownOption> _operators = const [];

  String? _replacementVehicleId;
  String? _replacementDriverId;
  String? _replacementOperatorId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadingOptions = true;
      _loadError = null;
    });
    try {
      final today = DateTime.now();
      final results = await Future.wait([
        widget.repo.fetchAvailableVehicles(today),
        widget.repo
            .fetchAvailableStaff(today, VehicleBreakdownRepository.driverRole),
        widget.repo.fetchAvailableStaff(
            today, VehicleBreakdownRepository.operatorRole),
      ]);
      if (!mounted) return;
      setState(() {
        _vehicles = results[0];
        _drivers = results[1];
        _operators = results[2];
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

  bool get _canSave =>
      !_saving &&
      _replacementVehicleId != null &&
      _replacementDriverId != null &&
      _replacementOperatorId != null;

  Future<void> _submit() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.repo.approve(
        widget.report.uniqueId,
        remarks: _remarksController.text.trim(),
        replacementVehicleId: _replacementVehicleId!,
        replacementDriverId: _replacementDriverId!,
        replacementOperatorId: _replacementOperatorId!,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Breakdown approved — vehicle replaced.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveError = e.toString();
        _saving = false;
      });
    }
  }

  InputDecoration _fieldDecoration(String label) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: SupervisorTheme.hairline),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
          color: SupervisorTheme.mutedText, fontWeight: FontWeight.w500),
      filled: true,
      fillColor: SupervisorTheme.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SupervisorTheme.accent, width: 1.4),
      ),
    );
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Arrange replacement',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Broken down: ${widget.report.breakdownVehicleNo}',
                  style: const TextStyle(
                      color: SupervisorTheme.mutedText,
                      fontWeight: FontWeight.w600),
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
            child: CircularProgressIndicator(color: SupervisorTheme.accent)),
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
          20, 4, 20, 16 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _replacementVehicleId,
            isExpanded: true,
            dropdownColor: SupervisorTheme.surface,
            decoration: _fieldDecoration('Replacement vehicle'),
            items: _vehicles
                .map((v) => DropdownMenuItem(
                      value: v.uniqueId,
                      child: Text(v.label, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _replacementVehicleId = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _replacementDriverId,
            isExpanded: true,
            dropdownColor: SupervisorTheme.surface,
            decoration: _fieldDecoration('Replacement driver'),
            items: _drivers
                .map((d) => DropdownMenuItem(
                      value: d.uniqueId,
                      child: Text(d.label, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _replacementDriverId = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _replacementOperatorId,
            isExpanded: true,
            dropdownColor: SupervisorTheme.surface,
            decoration: _fieldDecoration('Replacement operator'),
            items: _operators
                .map((o) => DropdownMenuItem(
                      value: o.uniqueId,
                      child: Text(o.label, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _replacementOperatorId = v),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _remarksController,
            decoration: _fieldDecoration('Remarks (optional)'),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 10),
            Text(_saveError!,
                style: const TextStyle(color: SupervisorTheme.danger)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canSave ? _submit : null,
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
                  : const Text('Approve & assign replacement'),
            ),
          ),
        ],
      ),
    );
  }
}
