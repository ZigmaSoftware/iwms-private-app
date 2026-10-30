import 'package:equatable/equatable.dart';

/// A single event on the citizen-visible timeline.
class GrievanceTimelineEvent extends Equatable {
  final String statusCode;
  final String statusName;
  final DateTime? at;
  final String? remarks;

  const GrievanceTimelineEvent({
    required this.statusCode,
    required this.statusName,
    this.at,
    this.remarks,
  });

  factory GrievanceTimelineEvent.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return GrievanceTimelineEvent(
      statusCode: json['status_code']?.toString() ?? '',
      statusName: json['status_name']?.toString() ?? '',
      at: parseDate(json['at']),
      remarks: json['remarks']?.toString(),
    );
  }

  @override
  List<Object?> get props => [statusCode, statusName, at, remarks];
}

/// A grievance ticket (shared by citizen + supervisor screens).
class GrievanceTicket extends Equatable {
  final String uniqueId;
  final String ticketNo;
  final String? title;
  final String? description;
  final String? categoryName;
  final String? subcategoryName;
  final String? priorityCode;
  final String? statusCode;
  final String? statusName;
  final String? assignedStaffName;

  /// Whether the ticket has escalated past its first assignee. Set by the
  /// backend's SLA sweep as well as by a manual escalate.
  final bool isEscalated;

  /// Who the ticket currently sits with once escalated — null while it is
  /// still with [assignedStaffName].
  final String? escalatedToStaffName;

  /// Current hop in the project's staff hierarchy (0 = first assignee).
  final int escalationLevel;

  /// Human role name for [escalationLevel], e.g. "Supervisor". Resolved by
  /// the backend from the project's staff hierarchy, so the app never has to
  /// know how a given project is structured.
  final String? escalationLevelName;

  final String? locationText;
  final String? waPhone;
  final String? customerName;
  final DateTime? createdAt;

  /// Deadline for the current [escalationLevel]. Past this and unresolved,
  /// the backend auto-escalates to the next level. Null once resolved/closed
  /// or at the top of the hierarchy, where there is no further deadline.
  final DateTime? nextEscalationDueAt;

  final List<GrievanceTimelineEvent> timeline;

  const GrievanceTicket({
    required this.uniqueId,
    required this.ticketNo,
    this.title,
    this.description,
    this.categoryName,
    this.subcategoryName,
    this.priorityCode,
    this.statusCode,
    this.statusName,
    this.assignedStaffName,
    this.isEscalated = false,
    this.escalatedToStaffName,
    this.escalationLevel = 0,
    this.escalationLevelName,
    this.locationText,
    this.waPhone,
    this.customerName,
    this.createdAt,
    this.nextEscalationDueAt,
    this.timeline = const [],
  });

  bool get isFinal => const {'RESOLVED', 'CLOSED', 'REJECTED', 'CANCELLED'}
      .contains(statusCode);

  /// The staff member actually responsible right now. Once a ticket has
  /// escalated it sits with [escalatedToStaffName]; before that, with the
  /// person it was first assigned to.
  String? get handlerName => escalatedToStaffName ?? assignedStaffName;

  /// Role currently holding the ticket, e.g. "Supervisor". Falls back to null
  /// rather than a guess when the project has no hierarchy configured.
  String? get handlerRole => escalationLevelName;

  /// Time left before the backend escalates this to the next level. Negative
  /// once the deadline has passed; null when there is no deadline (resolved,
  /// closed, or already at the top of the hierarchy).
  Duration? get timeToEscalation {
    if (nextEscalationDueAt == null || isFinal) return null;
    return nextEscalationDueAt!.difference(DateTime.now());
  }

  /// Whether this ticket has blown its current level's deadline and is due to
  /// escalate on the backend's next sweep.
  bool get isEscalationOverdue {
    final remaining = timeToEscalation;
    return remaining != null && remaining.isNegative;
  }

  factory GrievanceTicket.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    final tl = (json['public_timeline'] as List?) ?? const [];
    return GrievanceTicket(
      uniqueId: json['unique_id']?.toString() ?? '',
      ticketNo: json['ticket_no']?.toString() ?? '',
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      categoryName: json['category_name']?.toString(),
      subcategoryName: json['subcategory_name']?.toString(),
      priorityCode: json['priority_code']?.toString(),
      statusCode: json['status_code']?.toString(),
      statusName: json['status_name']?.toString(),
      assignedStaffName: json['assigned_staff_name']?.toString(),
      isEscalated: json['is_escalated'] == true,
      escalatedToStaffName: json['escalated_to_staff_name']?.toString(),
      escalationLevel:
          int.tryParse(json['escalation_level']?.toString() ?? '') ?? 0,
      escalationLevelName: json['escalation_level_name']?.toString(),
      locationText: json['location_text']?.toString(),
      waPhone: json['wa_phone']?.toString(),
      customerName: json['customer_name']?.toString(),
      createdAt: parseDate(json['created']),
      nextEscalationDueAt: parseDate(json['next_escalation_due_at']),
      timeline: tl
          .map(
              (e) => GrievanceTimelineEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [
        uniqueId,
        ticketNo,
        statusCode,
        assignedStaffName,
        escalatedToStaffName,
        escalationLevel,
        isEscalated,
      ];
}

/// Category + priority choices for the citizen chat (from the `meta` endpoint).
class GrievanceCategoryOption extends Equatable {
  final String uniqueId;
  final String code;
  final String name;
  final String? defaultPriority; // priority unique_id
  final String? defaultPriorityCode;
  final bool requiresLocation;

  const GrievanceCategoryOption({
    required this.uniqueId,
    required this.code,
    required this.name,
    this.defaultPriority,
    this.defaultPriorityCode,
    this.requiresLocation = false,
  });

  factory GrievanceCategoryOption.fromJson(Map<String, dynamic> json) {
    return GrievanceCategoryOption(
      uniqueId: json['unique_id']?.toString() ?? '',
      code: json['category_code']?.toString() ?? '',
      name: json['category_name']?.toString() ?? '',
      defaultPriority: json['default_priority']?.toString(),
      defaultPriorityCode: json['default_priority_code']?.toString(),
      requiresLocation: json['requires_location'] == true,
    );
  }

  @override
  List<Object?> get props => [uniqueId];
}

class GrievanceSubcategoryOption extends Equatable {
  final String uniqueId;
  final String category; // parent category unique_id
  final String name;

  const GrievanceSubcategoryOption({
    required this.uniqueId,
    required this.category,
    required this.name,
  });

  factory GrievanceSubcategoryOption.fromJson(Map<String, dynamic> json) {
    return GrievanceSubcategoryOption(
      uniqueId: json['unique_id']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      name: json['subcategory_name']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [uniqueId];
}

/// A priority a citizen can choose when raising a grievance (from the `meta`
/// endpoint's `priorities` array).
class GrievancePriorityOption extends Equatable {
  final String uniqueId;
  final String code;
  final String name;

  const GrievancePriorityOption({
    required this.uniqueId,
    required this.code,
    required this.name,
  });

  factory GrievancePriorityOption.fromJson(Map<String, dynamic> json) {
    return GrievancePriorityOption(
      uniqueId: json['unique_id']?.toString() ?? '',
      code: json['priority_code']?.toString() ?? '',
      name: json['priority_name']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [uniqueId];
}

class GrievanceMeta {
  final List<GrievanceCategoryOption> categories;
  final List<GrievanceSubcategoryOption> subcategories;
  final List<GrievancePriorityOption> priorities;

  const GrievanceMeta({
    this.categories = const [],
    this.subcategories = const [],
    this.priorities = const [],
  });

  factory GrievanceMeta.fromJson(Map<String, dynamic> json) {
    final categories = ((json['categories'] as List?) ?? const [])
        .map((e) => GrievanceCategoryOption.fromJson(e as Map<String, dynamic>))
        .where((category) => category.code != 'VEHICLE_ISSUE')
        .toList();
    final allowedIds = categories.map((category) => category.uniqueId).toSet();
    return GrievanceMeta(
      categories: categories,
      subcategories: ((json['subcategories'] as List?) ?? const [])
          .map((e) =>
              GrievanceSubcategoryOption.fromJson(e as Map<String, dynamic>))
          .where((subcategory) => allowedIds.contains(subcategory.category))
          .toList(),
      priorities: ((json['priorities'] as List?) ?? const [])
          .map((e) =>
              GrievancePriorityOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  List<GrievanceSubcategoryOption> subFor(String categoryId) =>
      subcategories.where((s) => s.category == categoryId).toList();

  /// Priority option matching a category's own default, if the backend sent
  /// one — used to preselect the picker rather than leaving it blank.
  GrievancePriorityOption? priorityFor(GrievanceCategoryOption? category) {
    if (category?.defaultPriority == null) return null;
    for (final p in priorities) {
      if (p.uniqueId == category!.defaultPriority) return p;
    }
    return null;
  }
}
