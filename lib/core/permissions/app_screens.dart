/// Mobile screen keys, mirroring `SCREEN_PERMISSIONS` in
/// `app/utils/app_feature_grants.py`.
///
/// There is one permission list: a screen ticked on a Staff Access
/// Configuration grants it in web and in this app identically. The backend
/// maps each screen below to the single permission that decides whether it
/// appears, and sends the resolved list as `app_screens`. Gate UI on these
/// keys rather than on API modules and resources — a screen usually reads
/// several endpoints, and gating on all of them means one missed tick makes a
/// tab silently vanish.
///
/// Keep in step with the backend map; the names must match exactly.
class AppScreens {
  const AppScreens._();

  // ---- Supervisor ----
  static const supervisorDashboard = 'supervisor.dashboard';
  static const supervisorTrips = 'supervisor.trips';
  static const supervisorCrew = 'supervisor.crew';
  static const supervisorHouseholds = 'supervisor.households';
  static const supervisorWaste = 'supervisor.waste';
  static const supervisorBreakdowns = 'supervisor.breakdowns';
  static const supervisorRetrips = 'supervisor.retrips';
  static const supervisorComplaints = 'supervisor.complaints';
  static const supervisorNotifications = 'supervisor.notifications';
  static const supervisorLiveMap = 'supervisor.livemap';
  static const supervisorVehicles = 'supervisor.vehicles';
  static const supervisorAttendance = 'supervisor.attendance';
  static const supervisorProfile = 'supervisor.profile';

  // ---- Driver ----
  static const driverTrips = 'driver.trips';
  static const driverHouseholds = 'driver.households';
  static const driverBins = 'driver.bins';
  static const driverBreakdowns = 'driver.breakdowns';
  static const driverDelays = 'driver.delays';
  static const driverRetrips = 'driver.retrips';
  static const driverNotifications = 'driver.notifications';
  static const driverCustomers = 'driver.customers';
  static const driverAttendance = 'driver.attendance';
  static const driverProfile = 'driver.profile';

  // ---- Operator (deprecated shell, merged into Driver) ----
  static const operatorTrips = 'operator.trips';
  static const operatorHouseholds = 'operator.households';
  static const operatorBins = 'operator.bins';
  static const operatorBreakdowns = 'operator.breakdowns';
  static const operatorNotifications = 'operator.notifications';
  static const operatorAttendance = 'operator.attendance';
  static const operatorProfile = 'operator.profile';

  // ---- Citizen ----
  static const citizenComplaints = 'citizen.complaints';
  static const citizenCollections = 'citizen.collections';
  static const citizenProfile = 'citizen.profile';
}
