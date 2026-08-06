import 'package:flutter/material.dart';

import 'package:iwms_private_app/data/models/staff_notification_models.dart';
import 'package:iwms_private_app/data/repositories/staff_notification_repository.dart';

/// In-app notification inbox shared by the driver and supervisor apps —
/// vehicle replacement approval/rejection, team reassignment, substitution.
/// Same backend feed (`schedule-operations/staff-notifications/`) scoped to
/// whichever staff login is calling.
///
/// Deliberately NOT themed with either module's brand color (driver =
/// green/CaptainTheme, supervisor = indigo/SupervisorTheme) since it's
/// shared — uses its own neutral slate accent instead of inheriting the
/// app-root green theme.
class StaffNotificationsScreen extends StatefulWidget {
  const StaffNotificationsScreen({super.key});

  @override
  State<StaffNotificationsScreen> createState() =>
      _StaffNotificationsScreenState();
}

/// Neutral slate accent for this shared screen — deliberately not green
/// (the app-root brand color) and not tied to either the driver or
/// supervisor module's own accent.
const Color _kNeutralAccent = Color(0xFF334155);

class _StaffNotificationsScreenState extends State<StaffNotificationsScreen> {
  final StaffNotificationRepository _repo = StaffNotificationRepository();

  bool _loading = true;
  String? _error;
  List<StaffNotification> _notifications = const [];

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
      final notifications = await _repo.fetchAll();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
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

  Future<void> _markAllRead() async {
    try {
      await _repo.markAllRead();
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map((n) => n.isRead
                ? n
                : StaffNotification(
                    uniqueId: n.uniqueId,
                    notificationType: n.notificationType,
                    title: n.title,
                    message: n.message,
                    data: n.data,
                    isRead: true,
                    createdAt: n.createdAt,
                  ))
            .toList();
      });
    } catch (_) {
      // Non-fatal — the list still reflects server state on next load.
    }
  }

  Future<void> _onTapNotification(StaffNotification n) async {
    if (n.isRead) return;
    try {
      await _repo.markRead(n.uniqueId);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications
            .map((existing) => existing.uniqueId == n.uniqueId
                ? StaffNotification(
                    uniqueId: existing.uniqueId,
                    notificationType: existing.notificationType,
                    title: existing.title,
                    message: existing.message,
                    data: existing.data,
                    isRead: true,
                    createdAt: existing.createdAt,
                  )
                : existing)
            .toList();
      });
    } catch (_) {
      // Non-fatal — leave as unread locally if the request failed.
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'VEHICLE_REPLACEMENT_APPROVED':
        return Icons.local_shipping_rounded;
      case 'VEHICLE_REPLACEMENT_REJECTED':
        return Icons.cancel_rounded;
      case 'VEHICLE_BREAKDOWN_REPORTED':
        return Icons.build_rounded;
      case 'TEAM_CHANGED':
        return Icons.groups_rounded;
      case 'TEAM_SUBSTITUTED':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((n) => !n.isRead);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _kNeutralAccent,
        foregroundColor: Colors.white,
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kNeutralAccent));
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Center(
            child: Text(_error!, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _load,
              style: TextButton.styleFrom(foregroundColor: _kNeutralAccent),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    if (_notifications.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.notifications_none_rounded,
              size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Center(child: Text('No notifications yet')),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final n = _notifications[index];
        return ListTile(
          onTap: () => _onTapNotification(n),
          leading: CircleAvatar(
            backgroundColor: n.isRead
                ? Colors.grey.shade200
                : _kNeutralAccent.withValues(alpha: 0.12),
            child: Icon(
              _iconFor(n.notificationType),
              color: n.isRead ? Colors.grey.shade500 : _kNeutralAccent,
              size: 20,
            ),
          ),
          title: Text(
            n.title,
            style: TextStyle(
              fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
            ),
          ),
          subtitle: Text(n.message),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _relativeTime(n.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              if (!n.isRead) ...[
                const SizedBox(height: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: _kNeutralAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
