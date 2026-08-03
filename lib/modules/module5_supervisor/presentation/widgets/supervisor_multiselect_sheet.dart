import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// A checkbox-list bottom sheet for picking zero or more [SupervisorCrewOption]s
/// (e.g. "extra operators"). Returns the selected list, or null if dismissed
/// without confirming.
class SupervisorMultiSelectSheet extends StatefulWidget {
  const SupervisorMultiSelectSheet({
    super.key,
    required this.title,
    required this.options,
    required this.initiallySelected,
  });

  final String title;
  final List<SupervisorCrewOption> options;
  final List<SupervisorCrewOption> initiallySelected;

  static Future<List<SupervisorCrewOption>?> show(
    BuildContext context, {
    required String title,
    required List<SupervisorCrewOption> options,
    required List<SupervisorCrewOption> initiallySelected,
  }) {
    return showModalBottomSheet<List<SupervisorCrewOption>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupervisorMultiSelectSheet(
        title: title,
        options: options,
        initiallySelected: initiallySelected,
      ),
    );
  }

  @override
  State<SupervisorMultiSelectSheet> createState() =>
      _SupervisorMultiSelectSheetState();
}

class _SupervisorMultiSelectSheetState
    extends State<SupervisorMultiSelectSheet> {
  late final Set<String> _selectedIds = widget.initiallySelected
      .map((o) => o.uniqueId)
      .toSet();

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
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: SupervisorTheme.strongText,
                ),
              ),
            ),
            Flexible(
              child: widget.options.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Text(
                        'No candidates available.',
                        style: TextStyle(color: SupervisorTheme.mutedText),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: widget.options
                          .map((o) => CheckboxListTile(
                                value: _selectedIds.contains(o.uniqueId),
                                title: Text(o.name),
                                activeColor: SupervisorTheme.accent,
                                onChanged: (checked) => setState(() {
                                  if (checked == true) {
                                    _selectedIds.add(o.uniqueId);
                                  } else {
                                    _selectedIds.remove(o.uniqueId);
                                  }
                                }),
                              ))
                          .toList(),
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                12 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final selected = widget.options
                            .where((o) => _selectedIds.contains(o.uniqueId))
                            .toList();
                        Navigator.of(context).pop(selected);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SupervisorTheme.accent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
