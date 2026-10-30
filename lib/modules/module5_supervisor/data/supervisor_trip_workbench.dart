import 'supervisor_models.dart';

/// One complete, supervisor-scoped snapshot. Today remains distinct from
/// unfinished earlier assignments; terminal trips never inflate active counts.
class SupervisorTripWorkbench {
  const SupervisorTripWorkbench({
    required this.serviceDate,
    required this.serverNow,
    required this.assignments,
  });

  final DateTime serviceDate;
  final DateTime serverNow;
  final List<SupervisorAssignment> assignments;

  bool isToday(SupervisorAssignment a) =>
      a.tripDate != null &&
      a.tripDate!.year == serviceDate.year &&
      a.tripDate!.month == serviceDate.month &&
      a.tripDate!.day == serviceDate.day;

  List<SupervisorAssignment> get today => assignments.where(isToday).toList();
  List<SupervisorAssignment> get remaining => assignments
      .where((a) =>
          a.isRemaining &&
          a.tripDate != null &&
          (isToday(a) || a.tripDate!.isBefore(serviceDate)))
      .toList();
  List<SupervisorAssignment> get carriedOver =>
      remaining.where((a) => !isToday(a)).toList();
}

class SupervisorTripHistoryPage {
  const SupervisorTripHistoryPage(
      {required this.items,
      required this.count,
      required this.hasMore,
      required this.serviceDate});
  final List<SupervisorAssignment> items;
  final int count;
  final bool hasMore;
  final DateTime serviceDate;
}

/// ISO offsets are deliberately removed: this value represents the server's
/// local wall clock for service-day labels and scheduled-time comparisons.
DateTime parseServiceWallTime(String value) {
  final match =
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}').firstMatch(value);
  if (match == null) throw const FormatException('Missing server time');
  return DateTime.parse(match.group(0)!);
}
