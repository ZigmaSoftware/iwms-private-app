import 'package:dio/dio.dart';

import 'package:iwms_citizen_app/core/api_config.dart';
import 'package:iwms_citizen_app/core/network/authorized_dio.dart';
import 'package:iwms_citizen_app/data/models/staff_notification_models.dart';

class StaffNotificationException implements Exception {
  StaffNotificationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// In-app notification feed for the logged-in staff login — shared by the
/// driver and supervisor apps (same `schedule-operations/staff-notifications/`
/// endpoint, scoped server-side to whichever staff made the request).
class StaffNotificationRepository {
  Future<List<StaffNotification>> fetchAll() async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(ApiConfig.staffNotifications);
      return _rawList(res.data).map(StaffNotification.fromJson).toList();
    } on DioException catch (e) {
      throw StaffNotificationException(_message(e));
    } catch (e) {
      throw StaffNotificationException(e.toString());
    }
  }

  Future<int> fetchUnreadCount() async {
    try {
      final dio = await authorizedDio();
      final res = await dio.get(ApiConfig.staffNotificationsUnreadCount);
      final data = res.data;
      if (data is Map && data['unread_count'] != null) {
        return int.tryParse(data['unread_count'].toString()) ?? 0;
      }
      return 0;
    } on DioException catch (e) {
      throw StaffNotificationException(_message(e));
    } catch (e) {
      throw StaffNotificationException(e.toString());
    }
  }

  Future<void> markRead(String uniqueId) async {
    try {
      final dio = await authorizedDio();
      await dio.post('${ApiConfig.staffNotifications}$uniqueId/read/');
    } on DioException catch (e) {
      throw StaffNotificationException(_message(e));
    } catch (e) {
      throw StaffNotificationException(e.toString());
    }
  }

  Future<void> markAllRead() async {
    try {
      final dio = await authorizedDio();
      await dio.post(ApiConfig.staffNotificationsMarkAllRead);
    } on DioException catch (e) {
      throw StaffNotificationException(_message(e));
    } catch (e) {
      throw StaffNotificationException(e.toString());
    }
  }

  List<Map<String, dynamic>> _rawList(dynamic data) {
    final List raw;
    if (data is List) {
      raw = data;
    } else if (data is Map && data['results'] is List) {
      raw = data['results'] as List;
    } else if (data is Map && data['data'] is List) {
      raw = data['data'] as List;
    } else {
      raw = const [];
    }
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    if (data is Map && data['error'] != null) return data['error'].toString();
    return e.message ?? 'Network error';
  }
}
