String _str(dynamic v) => v == null ? '' : v.toString().trim();

/// An in-app notification for a driver/operator/supervisor login — vehicle
/// replacement approval/rejection, team reassignment, or substitution.
/// Shared by the driver and supervisor apps (same backend endpoint).
class StaffNotification {
  const StaffNotification({
    required this.uniqueId,
    required this.notificationType,
    required this.title,
    required this.message,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  final String uniqueId;
  final String notificationType;
  final String title;
  final String message;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? createdAt;

  factory StaffNotification.fromJson(Map<String, dynamic> j) {
    return StaffNotification(
      uniqueId: _str(j['unique_id']),
      notificationType: _str(j['notification_type']),
      title: _str(j['title']),
      message: _str(j['message']),
      data: j['data'] is Map
          ? Map<String, dynamic>.from(j['data'] as Map)
          : const {},
      isRead: j['is_read'] == true,
      createdAt: DateTime.tryParse(_str(j['created_at'])),
    );
  }
}
