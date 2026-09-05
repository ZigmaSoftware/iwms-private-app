import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:iwms_private_app/core/env.dart';

// This function creates and configures a Dio instance
Dio createDioClient() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10), // Increased timeout
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  // You can add interceptors here for logging or auth tokens
  if (!kReleaseMode) {
    dio.interceptors.add(
      LogInterceptor(responseBody: true, requestBody: true),
    );
  }

  return dio;
}

class ApiConfig {
  /// Desktop endpoints (open lists) used for driver-side data pulls.
  static const String desktopBase = kDesktopBase;
  // Attendance module (face registration/recognition, daily register,
  // staff profile) was moved under this prefix on the government backend.
  static const String attendanceBase = '${desktopBase}attendance/';
  static const bool legacyRoleAssignEnabled = false;
  static const bool legacyTripAssignEnabled = false;
  static const String wasteSummaryEndpoint =
      '${desktopBase}waste/citizen-summary/';
  // NOTE: government backend does not yet implement this action (household
  // collection viewset is plain CRUD). Path mirrors iwms-app for consistency;
  // needs a matching endpoint on iwms-government-backend before it works at runtime.
  static const String householdCollectionMarkStatus =
      '${desktopBase}waste/mark-household-status/';
  // The waste streams saved against a customer in Customer Creation. Without
  // `customer_id` it returns every active waste type instead.
  static const String customerWasteTypes =
      '${desktopBase}waste/get-waste-types/';
  static const String customerList =
      '${desktopBase}customer-masters/customercreations/';
  static const String registerFcmToken =
      '${desktopBase}customer-masters/customercreations/register-fcm-token/';
  // "staff-creations", not "user-creations" — the backend's router group and
  // the underlying model package (app.models.user_creations ->
  // app.models.staff_creations) were both renamed in a dev merge. This one
  // was left pointing at the old URL, so every registration attempt 404'd
  // silently (the client only debugPrints a failed registration, never
  // surfaces it) — no driver/operator/supervisor ever got a push as a result.
  static const String registerStaffFcmToken =
      '${desktopBase}staff-creations/staffcreation/register-fcm-token/';

  /// Driver-reported trip delays (puncture, traffic, minor repair) — a delay
  /// does not stop the trip, unlike a breakdown.
  static const String tripDelayReports =
      '${desktopBase}schedule-operations/trip-delay-reports/';

  static const String vehicleBreakdowns =
      '${desktopBase}schedule-operations/vehicle-breakdowns/';
  static const String vehicleBreakdownAvailableStaff =
      '${desktopBase}schedule-operations/vehicle-breakdowns/available-staff/';
  static const String vehicleBreakdownAvailableVehicles =
      '${desktopBase}schedule-operations/vehicle-breakdowns/available-vehicles/';

  static const String retripRequests =
      '${desktopBase}schedule-operations/retrip-requests/';

  static const String staffNotifications =
      '${desktopBase}schedule-operations/staff-notifications/';
  static const String staffNotificationsUnreadCount =
      '${desktopBase}schedule-operations/staff-notifications/unread-count/';
  static const String staffNotificationsMarkAllRead =
      '${desktopBase}schedule-operations/staff-notifications/mark-all-read/';
  static const String staffTemplateAvailableStaff =
      '${desktopBase}schedule-setup/staff-templates/available-staff/';

  // --- Grievance / complaint: citizen mobile (self-scoped, auth-only) ---
  // Government backend exposes the citizen complaint API under `citizen/complaint-tickets/`
  // (list / create / {id} / meta) — same request+response contract as the old
  // `citizen/grievance-tickets/` routes.
  static const String citizenGrievanceTickets =
      '${desktopBase}citizen/complaint-tickets/';
  static const String citizenGrievanceMeta =
      '${desktopBase}citizen/complaint-tickets/meta/';
  // --- Grievance / complaint: supervisor / staff (team + department scoped) ---
  // `complaint-ticket/grievance-tickets/` supports {id}/status/,
  // {id}/escalate/, {id}/resolve/ actions matching the supervisor
  // repository's calls. NOTE: `complaint-ticket/tickets/` is a DIFFERENT,
  // older flat-Complaint model used by the admin web frontend — do not
  // point this constant back at it.
  static const String grievanceTickets =
      '${desktopBase}complaint-ticket/grievance-tickets/';

  static const String assignments =
      '${desktopBase}schedule-operations/daily-trip-assignments/';
  static const String staffAssignments =
      '${desktopBase}schedule-operations/daily-trip-assignments/';
  static const String collectionLogs =
      '${desktopBase}schedule-operations/bin-collection-events/';
  static const String assignmentCustomerStatuses =
      '${desktopBase}schedule-operations/daily-trip-household-collections/';
  static const String citizenAssignments =
      '${desktopBase}schedule-operations/daily-trip-household-collections/';
  static const String tripAssignments =
      '${desktopBase}schedule-operations/daily-trip-assignments/';
  static const String tripShifts = '${desktopBase}schedule-setup/trip-plans/';
  static const String tripCollectionPoints =
      '${desktopBase}schedule-operations/daily-trip-collection-points/';
  static const String tripRoutePlans =
      '${desktopBase}schedule-setup/trip-plans/';
  static const String tripPlannedStops =
      '${desktopBase}schedule-masters/trip-plan-collection-points/';
  static const String tripRouteGeometry =
      '${desktopBase}schedule-operations/daily-trip-collection-points/tracking/';
  static const String tripExecutionStops =
      '${desktopBase}schedule-operations/daily-trip-collection-points/';
  static const String tripRoutePlanGenerate =
      '${desktopBase}schedule-operations/daily-trip-collection-points/optimize-route/';
  static const String tripGenerate =
      '${desktopBase}schedule-operations/daily-trip-assignments/generate-daily/';
  static const String tripDriverRoute =
      '${desktopBase}schedule-operations/daily-trip-collection-points/tracking/';
  static const String staffTemplates =
      '${desktopBase}schedule-setup/staff-templates/';
  static const String vehicles =
      '${desktopBase}transport-masters/vehicle-creation/';
  // Unused — no call site references this constant. Left pointing at the
  // renamed "staff-creations" prefix for consistency with registerStaffFcmToken
  // above, but "users-creation" itself isn't among the screens currently
  // registered there (only departments/designations/staffcreation are) —
  // verify against app/urls/base_urls.py before wiring a real caller to this.
  static const String users = '${desktopBase}staff-creations/users-creation/';
  static const String subproperties =
      '${desktopBase}waste-types/subproperties/';
  static const String wards = '${desktopBase}masters/panchayat/';
  static const String zones = '${desktopBase}masters/hierarchy-nodes/';

  // Operator-mobile flow
  static const String operatorMyTripToday =
      '${desktopBase}operator-mobile/my-trip-today/';
  // All of the operator's trips today (bin + household + bulk) for the header
  // carousel.
  static const String operatorMyTripsToday =
      '${desktopBase}operator-mobile/my-trips-today/';
  static const String operatorValidateBinQr =
      '${desktopBase}operator-mobile/validate-bin-qr/';
  static const String operatorScanBin =
      '${desktopBase}operator-mobile/scan-bin/';
  static const String operatorTripHistory =
      '${desktopBase}operator-mobile/trip-history/';
  // Stops beyond the first page: my-trip-today/my-trips-today only ever embed
  // the first STOPS_PAGE_SIZE (20) bin/household stops now — the rest is
  // fetched here, 20 at a time, as the driver scrolls.
  static const String operatorTripStops =
      '${desktopBase}operator-mobile/trip-stops/';
  // Explicit trip start / end. `end` does NOT always end the trip: with
  // stops still pending it raises a Re-Trip request for a supervisor to
  // decide, rather than closing the assignment.
  static const String operatorTripLifecycle =
      '${desktopBase}operator-mobile/trip-lifecycle/';
  static String operatorTripStart(String assignmentId) =>
      '$operatorTripLifecycle$assignmentId/start/';
  static String operatorTripEnd(String assignmentId) =>
      '$operatorTripLifecycle$assignmentId/end/';

  // ORS key is sourced from build-time env (`VITE_ORS_API_KEY`).
  static const String orsApiKey = kOrsApiKey;

  // Live GPS feed used by all-vehicle map screens. Route/trip maps still use
  // the government backend; this endpoint provides actual vehicle telemetry.
  static const String vehicleLiveApi =
      '$kVehicleLiveApiBaseUrl?providerName=$kVehicleProviderName&fcode=$kVehicleFCode';

  static const String driverNextHouse = '$kApiBase/driver/next-house/';
  static const String updateAssignmentStatus =
      '$kApiBase/driver/assignment/update-status/';

  /// Government Django backend endpoint for mobile authentication.
  /// Login is exposed at `/api/v1/login/`.
  static const String _defaultMobileLogin = '${desktopBase}login/';
  static const String _defaultCitizenLogin = _defaultMobileLogin;
  static const String citizenLogin = String.fromEnvironment(
    'CITIZEN_LOGIN_URL',
    defaultValue: _defaultCitizenLogin,
  );
  // Mobile apps should use the unified mobile login endpoint.
  static const String staffLogin = _defaultMobileLogin;
  static const String mobileLogin = _defaultMobileLogin;
  static const String myPermissions = '${desktopBase}login/my-permissions/';

  /// Default user type identifier expected by the Django login API.
  static const String citizenUserType = 'citizen';
}
