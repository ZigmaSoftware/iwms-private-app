changes for driver app:
1. The bottom nav bar texture is perfect, howevern the floatin functionality does not seem to be perfect. Can you attach the bottom nav bat down to the bottom without spaces.

2.
plan:
 Analyse how we plan "start/stop" feature for assignments in driver app. Analyse both frontend and backend and app. There is an "start time" in backend already. Reuse whatever is in the backend and create new logic only if necessary. 

First plan on backend in daily trip plan. 
Then plan on web frontend
Then plan on how the app should show it.
I mean, how driver will start the assignment? Will he swipe start? Will he press a button to start the assignment and end it? 


Resulsts:
I have everything needed. Here's the inventory.

Web (admin) inventory for DailyTripAssignment
1. Daily Trip Assignment screens
/Users/zigma-mac/Documents/IWMS/iwms-government-frontend/src/pages/admin/modules/core_modules/dailyOperations/dailyTripAssignment/

List — dailyTripAssignmentList.tsx (950 lines), titled "Daily Trip Plans"
Columns (<Column> defs at lines 858–946):

#	Header	Source	line
1	S.No	rowIndex	858
2	ID	unique_id	859
3	Trip Plan	trip_plan.display_code	860
4	Effective Staff	effective_staff.display_code (amber if alt)	866
5	Operator / Driver	effective_staff ?? staff_template	874
6	Vehicle	vehicle.vehicle_no	888
7	Location	derived local-body level + tag	894
8	Collection Type	derived badge (bin/household/bulk/mixed)	909
9	Collection Points	count of collection_points + household_collection_points	915
10	Trip Date	trip_date, sortable	921
11	Start Time	scheduled_time (NOT actual) formatted 12h, sortable	927
12	Status	status badge, sortable	934
13	Breakdown	breakdown_info.approval_status pill	941
14	Actions	edit pencil only	946
Key gaps: there is no actual_start_time / actual_end_time / duration / progress-% column at all. scheduled_time is mislabeled "Start Time" (list line 929 and Excel export line 437 "Start Time": formatTime12Hour(row.scheduled_time)). Actual times only appear in the detailed PDF export: ["Actual Start", row.actual_start_time], ["Actual End", row.actual_end_time] at lines 533–534 (plus ["Approval", row.approval_status] 536).

Actions / toolbar (lines 713–743, 786–835):

Download Excel (419), Download PDF (448)
Run Scheduler → dailyTripAssignmentApi.action("run-scheduler", { date }) (line 354)
New Daily Trip Plan
Auto-generate config bar: action("scheduler-status") (line 339) + api.patch(adminEndpoints.schedulerConfig, …) (line 382)
Row action = edit only, disabled when status === "Completed" || "Cancelled" (line 690)
No status-change button, no approve/reject, no bulk actions, no delete. (Contrast: vehicleBreakdownList.tsx:384–417 DOES have Approve/Reject/PENDING actions.)
Filters: HierarchyFilterBar, Collection Type (client-side, current page only), Trip Date (?date=), debounced ?search=. Server-side pagination + ordering restricted to SORTABLE_FIELDS = {trip_date, scheduled_time, status, approval_status} (line 190).

Form — dailyTripAssignmentForm.tsx (1309 lines)
Fields: Trip Date (794), Start Time = scheduled_time time input (799), Trip Plan, Staff Template, Alt Staff Template, geo cascade, Waste Types, Wards, Remarks.
Status: admin CAN manually set it, edit-mode only <Select> with STATUS_OPTIONS = Scheduled | In Progress | Completed | Cancelled (lines 87–92, 991–996), submitted as status in the payload (line 730).
Approval Status: read-only disabled <Input> in edit mode (998–1003); never sent in the payload.
actual_start_time / actual_end_time are NOT in the form — not read, not editable, not submitted.
Inline per-stop editing: bin stops (collection_points_input, 734–741 — sequence, is_collected, collected_at, collected_weight_kg, status) and household stops PATCHed one-by-one via dailyTripHouseholdCollectionApi.update (751–757).
types.ts
DailyTripAssignmentRecord already declares status, approval_status, actual_start_time, actual_end_time (lines 107–110) — the type is ready; only the UI doesn't surface them.

2. Daily Trip Tracking — dailyTripTracking/DailyTripTracking.tsx (1313 lines)
Polls every 15s: TRACKING_REFRESH_INTERVAL_MS = 15000 (line 60), setInterval(() => load(true), …) (467–473). Separate 15s poll for external GPS URL (507–510).
Endpoints — all via dailyTripCollectionPointApi.action(...), not the assignment API:
"tracking" with params.trip_assignment_id → per-trip (line 433)
"tracking-overview" → all-trips overview (line 437)
"optimize-route" POST {trip_assignment_id, vehicle_start} → ORS (line 693)
Shows per-collection-point progress, not trip lifecycle: summary {total, completed, in_progress, pending, missed, completion_percentage} (types.ts:18–25), progress bar (1163–1179), status tabs with counts (971–1001), Leaflet map with live vehicle marker, ORS ETA panel.
Trip-level info shown in the overview cards: trip.status as a plain gray pill (line 1203–1205), trip_date, vehicle_no, completion %, distance km, duration min.
Timing shown = only per-stop collected_at (fmtTime, lines 64–68, 208, 277) and trip_assignment.scheduled_time (198, 278–281). No actual_start_time/actual_end_time, no elapsed timer, no trip duration. "Start of Trip"/"End of Trip" markers (1256–1284) are purely decorative.
Its Row type (dailyTripTracking/types.ts:1–13) exposes only trip_assignment.{unique_id, scheduled_time} — would need extending for driver start/end.
3. Daily Trip Log — dailyTripLog/
dailyTripLogList.tsx DataTable columns (1008–1134): S.No, ID, Trip Assignment, Location, Ward, Staff Template, Alt Staff Template, Waste Type, Bin Weight (kg), HH Weight (kg), Log Status badge, Collection Status badge, Driver, Operator, Vehicle, Trip Date, Actions. → No start/end/duration columns. actual_start_time / actual_end_time appear only inside the expanded row detail as InfoRows, and only when truthy: lines 287–288.
DailyTripLogReportPage.tsx:334–335 renders them unconditionally as "Start Time"/"End Time" InfoRows.
No duration/elapsed computation anywhere in the log module (collectionTime.ts is only a collected-at formatter).
4. API layer
src/helpers/admin/endpoints.ts:

tripPlans: "schedule-setup/trip-plans" (62)
dailyTripAssignment: "schedule-operations/daily-trip-assignments" (63)
dailyTripLog: "schedule-operations/daily-trip-logs" (64)
dailyTripCollectionPoint: "schedule-operations/daily-trip-collection-points" (65)
dailyTripHouseholdCollection: "schedule-operations/daily-trip-household-collections" (66)
binCollectionEvent: "schedule-operations/bin-collection-events" (67)
vehicleBreakdown: "schedule-operations/vehicle-breakdowns" (68)
schedulerConfig: "schedule-operations/daily-trip-assignments/scheduler-config/" (69)
tripAttendances (142), vehicleTripAudits (148), tripExceptionLogs (149), dashboardSummary: "dashboard/summary" (11)
src/helpers/admin/index.ts exports: tripPlanApi (115), tripAttendanceApi (116), dailyTripAssignmentApi (118), dailyTripLogApi (119), dailyTripCollectionPointApi (120), dailyTripHouseholdCollectionApi (121), binCollectionEventApi (122), vehicleBreakdownApi (123), tripExceptionLogApi (130), dashboardSummaryApi (83).

src/helpers/admin/crudHelpers.ts — the generic DRF @action caller already exists:


action: <R = any, P = any>(action: string, payload?: P, config?: AxiosRequestConfig) => Promise<R>   // signature, line 110
// impl, line 269:
const url = `${resource}${cleanAction}${cleanAction.endsWith("/") ? "" : "/"}`;
const { data } = payload ? await api.post(url, stripTenancyKeys(payload), …) : await api.get(url, …);
Important behaviours for planning:

No payload ⇒ GET; payload present ⇒ POST. For a detail-route POST with an empty body pass {} (as complaintNotificationApi.action(${id}/read, {}) does, src/features/complaintTicketing/api.ts:229) — passing undefined would issue a GET.
Detail routes work by embedding the id in the action string: action(`${id}/resolve`, payload) — see src/features/complaintTicketing/api.ts:74–92. So a driver start/stop would be dailyTripAssignmentApi.action(${id}/start-trip, {}) / `${id}/end-trip` with zero new plumbing.
stripTenancyKeys is applied to payloads; response goes through capitalizeApiFormData.
5. Status display conventions — no shared component; duplicated local maps
There is no shared status-badge/pill. src/components/common/ has only ExpiryBadge.tsx; src/components/ui/badge.tsx is the generic shadcn variant badge (used in StaffAccessDashboard.tsx:816 as <Badge variant="secondary">{row.trip_status}</Badge>).

The convention to match for trip status is the local map in dailyTripAssignmentList.tsx:38–49:


const STATUS_STYLES = {
  Scheduled: "bg-blue-100 text-blue-800",
  "In Progress": "bg-yellow-100 text-yellow-800",
  Completed: "bg-green-100 text-green-800",
  Cancelled: "bg-red-100 text-red-800",
};
const Badge = ({value, styleMap}) => <span className="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold …">
Other, divergent maps that a new feature should be aware of:

dailyTripLogList.tsx:28–38 — STATUS_STYLES (Draft/Submitted/Verified) and COLLECTION_STATUS_STYLES ("Not Started" red / "In Progress" yellow-50 / "Completed" green).
DailyTripTracking.tsx:21–37 — hex STATUS_COLOR (In Progress: #f59e0b, Collected/Completed: #22c55e, Pending: #ef4444) + STATUS_BG, plus statusLabel() mapping "Collected"→"Completed" (83–85) and TAB_FILTER mapping the "On Process" tab → "In Progress" (41–47).
vehicleBreakdownList.tsx ApprovalBadge (used at 550) — the model for an approval pill.
Stop-level status vocabularies differ from trip-level: bin stops Pending | In Progress | Collected | Skipped | Missed (form 1152–1156), household stops Pending | Collected | Not Available | Collect Later (form 1264–1267).
6. Dashboard — src/pages/dashboard/pages/Dashboard/HomeDashboard.tsx
Single data source: dashboardSummaryApi.readAllwithPaginated(1, 1, { params }) → dashboard/summary (line 1384), alongside complaintTicketApi / wasteTypeApi (1385–1386). All KPIs are backend-computed; the web does no client-side trip aggregation.
"Trips Completed" OverviewMetric at 1790–1800, fed by tripsCompleted / tripsTarget / tripsPct computed at 1563–1569 from summary.operations.trips_completed / trips_total, with a fallback tripsCompleted + summary.bins.not_collected. Sub-detail line splits Household vs Bin (summary.operations.household.trips_completed, .bin.trips_completed, line 1795).
Response shape declared at 175–241: operations.{household,bin,bulk}.{trips_completed,trips_total,…}, trip_performance[] = {trip_id, vehicle_no, ward_name, start_time, stops, weight_tons, status} rendered as a 5-row table at 1606–1617 (status colored green if "Completed", else amber). Note trip_performance[].start_time is the only trip-level start currently on the dashboard — plan should confirm whether the backend fills it from scheduled_time or actual_start_time.
Ward drill-down trips (WardTrip, ~65–78) expose only trip_date / trip_time, rendered at 1053–1077.
Critical alerts include a vehicle_breakdown kind carrying trip, trip_date, scheduled_time, breakdown_time, approval_status (drill-down 450–465).
Live map panels also poll tracking-overview: map/VehicleMapContent.tsx:104,155 and map/VehicleMapPanel.tsx:205,260.
Impact: any new explicit start/stop lifecycle changes what "Completed" means for operations.trips_completed, trip_performance[].status/start_time, and the tracking-overview trip.status pill — all computed server-side, so the web changes are display-only unless the backend contract changes.

7. Supervisor / approval flow for trips on the web — none exists
Grep for approval_status|approve|force across dailyOperations/ returns hits only in vehicleBreakdown (real Approve/Reject actions, vehicleBreakdownList.tsx:338, 363, 384–417, 546–550) and read-only mentions on assignments.
On assignments, approval_status is: a disabled input on the form (dailyTripAssignmentForm.tsx:1001), a PDF export field (dailyTripAssignmentList.tsx:536), listed in SORTABLE_FIELDS but deliberately not wired to a column (comment at 187–190), and rendered indirectly through breakdown_info.approval_status in BreakdownCell (51–81).
No "force close", no "approve trip", no supervisor override anywhere. Zero occurrences of force.
Closest existing analogue for a per-row admin action with confirm + optimistic row patch: vehicleBreakdownList.tsx:338/363.
What the web would need to ADD
Assignment list (dailyTripAssignmentList.tsx)

Rename col 11 to "Scheduled Time" and add "Actual Start" + "Actual End" columns (actual_start_time / actual_end_time already on the type, types.ts:109–110) — needs a datetime formatter; existing formatTime12Hour (144–152) only handles "HH:MM" strings, tracking's fmtTime (DailyTripTracking.tsx:64) handles ISO.
A Duration column — elapsed = now - actual_start_time while status === "In Progress" (needs a 1s/30s ticker; none exists today, no timer hook in the repo), else actual_end_time - actual_start_time.
Optional Progress column — the list currently has no completion %; that number only lives in the tracking endpoints' summary.completion_percentage, so it'd need a new field on the assignment serializer or a join.
Add actual_start_time/actual_end_time (and duration) to the Excel export rows (427–439) to match the PDF which already has them (533–534).
Add an admin force-close / force-start row action calling dailyTripAssignmentApi.action(${id}/force-close, { reason }), gated on status === "In Progress", modeled on vehicleBreakdownList.tsx:338–417 (Swal confirm + optimistic row patch + reload). The current action cell (681–697) is edit-only.
Consider a status filter dropdown (there is none — only date/hierarchy/collection-type).
SORTABLE_FIELDS (line 190) must be extended with actual_start_time/actual_end_time only if the backend ordering_fields allowlist also gets them.
Assignment form (dailyTripAssignmentForm.tsx)
8. Decide the fate of the manual Status <Select> (991–996) — with a driver-driven lifecycle it should become read-only/derived, or be restricted to Cancel-only, otherwise an admin can silently desync status from actual_start_time.
9. Add read-only Actual Start / Actual End display rows (mirroring the disabled Approval Status input at 998–1003), and read them in the edit-load effect (~302–305) which currently ignores them.

Tracking (DailyTripTracking.tsx)
10. Extend TrackingResponse / OverviewTrip (dailyTripTracking/types.ts:15–83) with the trip's actual_start_time/actual_end_time; surface a live elapsed timer in the trip-info card (1115–1180) and "Not started yet" state when actual_start_time is null — the 15s poll (467–473) already refreshes the data, only a local seconds-ticker is missing.
11. Overview trip cards (1184–1222) should show started-at / elapsed next to the plain trip.status pill, and should distinguish "Scheduled but not started" from "In Progress".

Log
12. Promote actual_start_time/actual_end_time from expansion-only InfoRows (dailyTripLogList.tsx:287–288) to real Start/End/Duration DataTable columns after col 16 (trip_date, line 1127).

Shared
13. Extract the trip STATUS_STYLES map + Badge (dailyTripAssignmentList.tsx:38–49) into a shared component (e.g. src/components/common/TripStatusBadge.tsx) so the list, tracking overview pill (1203), log, and any new start/stop UI agree — today three files hold three divergent copies.
14. No new API plumbing needed: crudHelpers.action() (crudHelpers.ts:110/269) already supports DRF detail @action sub-routes via action(`${id}/start-trip`, {}). Just remember payload-presence controls GET vs POST.

You've hit your session limit · resets 1:50pm (Asia/Calcutta)

I have everything. Here are the findings.

PART A — Bottom nav bar float
The exact cause
/Users/zigma-mac/Documents/IWMS/iwms-government-app/lib/modules/module2_driver/presentation/widgets/captain_nav_bar.dart:34-72 — CaptainNavBar.build:


return SafeArea(
  top: false,
  minimum: const EdgeInsets.only(bottom: 10),      // ← line 36: 10px gap BELOW the bar
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),  // ← line 38: 16px side gaps
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),     // ← line 40
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),  // line 43
        child: Container(
          height: height,                          // 68 (default, param at line 21)
          decoration: BoxDecoration(
            color: CaptainTheme.surface.withValues(alpha: dark ? 0.55 : 0.62),  // line 48
            borderRadius: BorderRadius.circular(28),  // line 49
            border: Border.all(... width: 1),         // lines 50-55
            boxShadow: CaptainTheme.elevatedShadow,   // line 57
          ),
          child: Row([_slot(0), _slot(1), SizedBox(width: 64), _slot(2), _slot(3)]),  // 59-67
        ),
Three things create the "floating" look, in priority order:

SafeArea(minimum: EdgeInsets.only(bottom: 10)) at line 36. SafeArea with bottom: true (the default — only top is disabled) already inserts MediaQuery.padding.bottom (34px on a notched iPhone, ~24px gesture bar on Android). minimum: bottom: 10 guarantees at least 10px even on a device with no bottom inset. So the gap under the bar is max(10, viewPadding.bottom). This is the single property causing the detached-from-bottom look.
Padding(horizontal: 16) at line 38 — the left/right detachment.
BorderRadius.circular(28) on both ClipRRect (line 40) and the Container decoration (line 49) — full rounding on all four corners; if you attach to the bottom you'll likely want bottom corners at 0 (or keep them and lose the detached read).
There is no Positioned, no Container(margin:), no BottomAppBar, no notch/custom shape. The FAB "notch" is faked by const SizedBox(width: 64) at line 63 — a literal empty Row slot under the hovering FAB, not a NotchedShape.

FAB positioning
/Users/zigma-mac/Documents/IWMS/iwms-government-app/lib/modules/module2_driver/presentation/screens/driver_home_page.dart:457-458:

floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
floatingActionButton: CaptainScanFab(onPressed: _openScanner),
CaptainScanFab — captain_nav_bar.dart:212-298. It's a plain SizedBox(64x64) (line 241) containing a pulsing halo (Container growing 64 + 12*t, lines 252-259) around a Material(CircleBorder, elevation: 8) → InkWell → Container(60x60, gradient) with a 30px scanner icon. Not a real FloatingActionButton, so centerDocked centres it on the top edge of the bottomNavigationBar's box — i.e. its vertical position is derived from the nav bar's total height including the SafeArea bottom inset. Important consequence: if you remove the 10px minimum / bottom inset, the FAB will drop down by that same amount. You may need to compensate (a custom FloatingActionButtonLocation or an offset) to keep the FAB visually straddling the bar's top edge.
Scaffold config
/Users/zigma-mac/Documents/IWMS/iwms-government-app/lib/modules/module2_driver/presentation/screens/driver_home_page.dart:408-484:


Scaffold(
  backgroundColor: DriverTheme.background,   // 409
  extendBody: true,                          // 410  → body paints under the nav bar
  body: SafeArea(bottom: false, child: Column([DriverHeader(...), Expanded(PageTransitionSwitcher...)])),  // 411-456
  floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,  // 457
  floatingActionButton: CaptainScanFab(onPressed: _openScanner),            // 458
  bottomNavigationBar: CaptainNavBar(activeIndex: ..., items: [4 items]),   // 459-483
)
resizeToAvoidBottomInset is not set anywhere in this Scaffold (defaults to true). The only resizeToAvoidBottomInset in lib/ is module1_citizen/citizen/login.dart:127.

Bottom-inset / clearance handling that must change with it
File:line	What
lib/modules/module2_driver/presentation/screens/captain_home_tab.dart:163	final bottomSafeArea = MediaQuery.viewPaddingOf(context).bottom;
captain_home_tab.dart:172	padding: EdgeInsets.fromLTRB(16, 12, 16, 112 + bottomSafeArea) — the ListView's bottom clearance for nav bar + FAB
driver_home_page.dart:2193-2194	Map tab: final bottomInset = MediaQuery.viewPaddingOf(context).bottom; final bottomOverlayOffset = 84.0 + bottomInset; — positions map overlay controls above the bar
driver_home_page.dart:4106	Profile tab tail spacer: SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 104)
Math today: bar height 68 + max(10, inset) gap + card side gaps. 112 + bottomSafeArea in captain_home_tab overshoots slightly (68 + 10 = 78 plus FAB overhang ≈ 32 → ~110), which is why 112 was chosen. If you drop the 10px minimum and let the bar sit flush, these three constants (112, 84, 104) should each drop by ~10 (or be recomputed against a shared constant). Right now the magic numbers are duplicated in four places with no shared source — worth extracting one kCaptainNavBarClearance.

Blast radius
CaptainNavBar is used in exactly one place: driver_home_page.dart:459. Nowhere else. (grep across lib/ confirms: only the definition, the README mention, and that one call site.)
CaptainScanFab: also only driver_home_page.dart:458.
SupervisorAnimatedNavBar (lib/modules/module5_supervisor/presentation/widgets/supervisor_animated_nav_bar.dart:37-41) is a separate class that copies the identical float recipe:

SafeArea(top: false, minimum: const EdgeInsets.only(bottom: 10),
  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), ...
with static const double _radius = 28 (line 30) and height = 68 (line 28). Used only at lib/modules/module5_supervisor/presentation/screens/main_supervisor_tabbar.dart:196 (that Scaffold also has extendBody: true at line 171). It will not change unless you edit it too — so changing the driver bar leaves the supervisor bar floating, which is a visual-consistency decision for you, not a technical dependency.
DriverAnimatedNavBar (lib/modules/module2_driver/presentation/widgets/driver_animated_nav_bar.dart:11) is dead code — zero call sites.
Module 3 operator (main_operator_tabbar.dart:265) also uses extendBody: true but with its own nav bar.
Files to change for Part A (minimum): captain_nav_bar.dart (lines 34-49, and possibly 63/FAB compensation), plus the clearance constants at captain_home_tab.dart:172, driver_home_page.dart:2194, driver_home_page.dart:4106. Optionally supervisor_animated_nav_bar.dart:37-41 for parity.

PART B — Trip start/stop inventory
1. Trip hero card — captain_home_tab.dart
_TripHeroCard (lines 819-1054). Constructor takes trip, onOpenMap, optional blocker, index, total. Locked state (lines 887-905): IgnorePointer + Opacity(0.55) + greyscale ColorFiltered + centred _LockChip.

Card body (_buildCard, 908-1053) is a CaptainGlassCard(onTap: onOpenMap, tint: _typeTint, padding: LTRB(13,15,12,20), borderRadius: 19) containing:

Header row (932-986): CrewAvatarStack → _CollectionTypePill → _TripStatusPill → date / "Trip 2 of 3" counter.
Content row (992-1047): area name (bold 16.5), then a Wrap of _CompactInfoItems — vehicle no., _formatTime(trip.scheduledTime) (line 1025, DateFormat.jm() via _formatTime at 868-876), waste type. Right side: _CompactTripProgress.
_TripStatusPill (1056-1095): tiny outlined pill showing status.toUpperCase(), colour from _statusColor (843-854): completed→success, in progress→gold, cancelled→danger, else info. Purely read-only — no tap handler.

_CompactTripProgress (1137-1210): 56px ring on progress.resolvedFraction, centre label "resolved/total", sublabel DONE/STOPS.

Note: actualStartTime / actualEndTime are never rendered anywhere on the hero card. The only time shown is the scheduled time.

_QuickActionsRow (1216-1294): three equal Expanded InkWells, each a 76×76 Image.asset + 11.5pt label:

Navigate → assets/icons/navigate.png → onOpenMap
Scan → assets/icons/scan.png → onScan (null when locked → rendered at Opacity(0.4), see call site line 190)
History → assets/icons/history.png → onHistory
Call site: lines 186-197.

2. OperatorTripToday — lib/data/models/operator_trip_models.dart:342-560
Full field list (342-368):

Field	Type	JSON key (fromJson, 506-545)
assignmentUniqueId	String	assignment_unique_id (508)
tripDate	DateTime	trip_date (509)
status	String	status (510)
scheduledTime	String?	scheduled_time (518)
actualStartTime	String?	actual_start_time (519)
actualEndTime	String?	actual_end_time (520)
panchayat / ward	OperatorTripPanchayat? / OperatorTripWard?	(521-530)
wasteType	OperatorTripWasteType	OperatorTripWasteType.resolve(json) (533)
vehicle	OperatorTripVehicle?	vehicle (534)
tripPlan	OperatorTripPlanBrief?	trip_plan (539)
progress	OperatorTripProgress	
distanceMeters, durationSeconds	double	
routeGeojson	Map<String,dynamic>?	
vehicleStart	List<double>?	
collectionPoints	List<OperatorTripCollectionPoint>	
crew	OperatorTripCrew?	
collectionType	String?	collection_type (511)
householdCollections	List<OperatorTripHouseholdStop>	household_collections (512-517)
Derived members:

areaName (422), isHousehold (426-428)
isFinished (436-437): status.toLowerCase() == 'completed' || progress.completed
scheduledTimeLabel (440-446) — HH:mm
assignmentTypeLabel (448-459)
totalCollectedWeightKg (465-468)
withCollectionPoints (395-418), toHistorySummary (475-492), toHistoryDetail (498-504)
OperatorTripProgress (300-326): collected, total, resolved, completed + fraction, resolvedFraction.

actualStartTime / actualEndTime are parsed and carried through toHistorySummary but are not used in any driver UI. Nothing writes them.

3. operator_trip_repository.dart — every method
Method	Line	HTTP	Endpoint
fetchCustomerWasteTypes(customerId)	35	GET	ApiConfig.customerWasteTypes
fetchMyTripToday()	62	GET	ApiConfig.operatorMyTripToday
fetchMyTripsToday()	78	GET	ApiConfig.operatorMyTripsToday
markHouseholdStatus({customerId, status, reason, assignmentId, lat, lng})	100	POST	ApiConfig.householdCollectionMarkStatus
validateBinQr(binQr)	126	POST	ApiConfig.operatorValidateBinQr
scanBin({binQr, weightKg, action, lat, lng, notes, statusReason})	141	POST	ApiConfig.operatorScanBin
fetchHistory({from, to})	173	GET	ApiConfig.operatorTripHistory
fetchHistoryDetail(tripId)	200	GET	${ApiConfig.operatorTripHistory}$tripId/
_throwDio	216	—	error mapping
There is NO start/stop call today. No method touches assignment status directly.

4. lib/core/api_config.dart — trip/operator endpoints

operatorMyTripToday      120-121  {desktopBase}operator-mobile/my-trip-today/
operatorMyTripsToday     124-125  {desktopBase}operator-mobile/my-trips-today/
operatorValidateBinQr    126-127  {desktopBase}operator-mobile/validate-bin-qr/
operatorScanBin          128-129  {desktopBase}operator-mobile/scan-bin/
operatorTripHistory      130-131  {desktopBase}operator-mobile/trip-history/
householdCollectionMarkStatus 37-38  {desktopBase}waste/mark-household-status/
Desktop/admin-side (not driver): tripAssignments (90), tripShifts (92), tripCollectionPoints (93), tripRoutePlans (95), tripPlannedStops (97), tripRouteGeometry (99), tripExecutionStops (101), tripRoutePlanGenerate (103), tripGenerate (105), tripDriverRoute (107). Also legacyTripAssignEnabled = false (31).

No operator-mobile/start-trip/ or end-trip/ constant exists. Backend app/viewsets/operator_mobile/ contains only my_trip_today_viewset.py, scan_bin_viewset.py, trip_history_viewset.py, validate_bin_qr_viewset.py — there is no server endpoint for this yet either.

5. How work is marked done today — and the implicit start
Bins — _StopsTimeline (1300-1360) sorts trip.collectionPoints by sequence, computes nextIndex = first !isCollected (1345), renders _StopTile per stop. _StopTile (1362-1602): timeline rail + CaptainGlassCard(onTap: done ? null : () => _openWeightEntry(context)) (line 1455). _openWeightEntry (1551-1596): shows a blocking spinner dialog → repo.validateBinQr(stop.bin.scanValue) → showModalBottomSheet(BinDetailSheet(validation:)) → on non-null result, flashes "Trip completed" if result.tripCompleted (1591-1593) and calls onChanged().

Households — _HouseholdTimeline (1627-1687) / _HouseholdTile (1689-1892). Tap → _openHouseholdCollection (1878-1890) → showHouseholdActionSheet(context, customerId, customerName, contactNo, lat, lng, assignmentId, currentStatus) → then unconditional await onChanged().

Yes — the trip is implicitly started by the first scan, server-side. iwms-government-backend/app/viewsets/operator_mobile/scan_bin_viewset.py:73 calls _ensure_assignment_in_progress(ctx.assignment), defined at 184-194:


if assignment.status in (DailyTripAssignment.STATUS_SCHEDULED,):
    now = timezone.localtime().time()
    assignment.status = DailyTripAssignment.STATUS_IN_PROGRESS
    if not assignment.actual_start_time:
        assignment.actual_start_time = now
The only explicit status transition endpoint is the desktop/admin one: app/viewsets/core_modules/daily_operations/daily_trip_assignment_viewset.py:185-217 — PATCH /trip-assignments/{unique_id}/status/, which sets actual_start_time on IN_PROGRESS and actual_end_time on COMPLETED. Note there is no operator-mobile path that ever sets actual_end_time — grep across app/viewsets/operator_mobile/ returns zero hits. So today: start is implicit-on-first-scan, end is never recorded from the app.

6. trip_sequence.dart — the sequential lock
/Users/zigma-mac/Documents/IWMS/iwms-government-app/lib/modules/module2_driver/presentation/state/trip_sequence.dart (97 lines):

TripBlocker (19-37): blockedBy (the earlier same-type trip), position (1-based), message getter producing "Finish your 06:30 bin trip to unlock this one."
tripBlockers(List<OperatorTripToday>) (45-75): groups by collectionType (line 51); within each group, first !isFinished trip becomes liveTrip, every trip after it is locked and all report that same live trip as blocker (61-71). Different collection types never gate each other.
isTripLocked(trips, trip) (78-81)
firstWorkableTrip(trips) (86-97): first unlocked-and-unfinished, then first unlocked, then trips.first.
Critical interaction: isFinished is status == 'completed' || progress.completed — purely derived from stop resolution. An explicit "end assignment" that sets status to Completed would immediately unlock the next same-type trip via this exact predicate, which is the desired behaviour and needs no change to trip_sequence.dart. But an explicit "start" that flips status to In Progress does not affect locking at all — so you can start trip 2 while trip 1 is unfinished unless you add a guard. Consumers of the lock: captain_home_tab.dart:159-161 (blockers/blocker/locked), :190 (scan disabled), :200 (_LockedTripBanner), :214/:227 (timelines inert), :278 (per-card blocker in the carousel).

7. Swipe-to-confirm / slide-to-action
None exists. A full grep of lib/ for Dismissible, Slidable, SlideAction, swipe, Draggable, onHorizontalDrag returns only:

barrierDismissible / isDismissible flags on dialogs and sheets
DraggableScrollableSheet at module5_supervisor/.../supervisor_grievance_screen.dart:709 and module1_citizen/citizen/grievance_status_screen.dart:320 (vertical sheets, not slide-to-action)
comments referring to the trip carousel as "swipeable" (captain_home_tab.dart:41, :73) — that's a manually-snapped horizontal SingleChildScrollView (_buildTripCarousel, 240-298; _snapCarousel, 300-336), not a reusable slide-to-confirm
pubspec.yaml has no flutter_slidable / slide_action dependency. A swipe-to-start control would have to be built from scratch (GestureDetector.onHorizontalDragUpdate + AnimationController), or the carousel's snap logic could be a loose template.

8. Reusable confirmation-sheet patterns
All in lib/modules/module2_driver/presentation/widgets/:

File:line	Pattern
household_action_sheet.dart:40-48	showHouseholdActionSheet → showModalBottomSheet<String>(isScrollControlled: true) returning the chosen action string
household_action_sheet.dart:236-240	Confirm sheet returning bool — the closest existing "are you sure?" primitive
household_action_sheet.dart:333-335	Reason-picker sheet returning String
household_action_sheet.dart:349	bottom: 20 + MediaQuery.viewInsetsOf(ctx).bottom keyboard handling
driver_report_actions_sheet.dart:11-14	static Future<void> show(BuildContext) — the cleanest static-entry convention
driver_vehicle_breakdown_flow.dart:91-94, 309-315, 417	Multi-step flow: sheet → sheet → sheet; keyboardInset at 492
bin_detail_sheet.dart:99-101	Reason sheet returning String; insets at 172 and 689
collection_progress_meter.dart:553	Sheet with viewInsetsOf(sheetContext).bottom + 24
Shared visual shell: CaptainGlassCard / CaptainBackground in lib/modules/module2_driver/presentation/widgets/captain_glass.dart; flashes via AppFlash.success / AppFlash.error (used at captain_home_tab.dart:1575, :1592).

Where a start/stop control slots in
UI, primary slot — between the hero card and _QuickActionsRow, i.e. captain_home_tab.dart:185 (the SizedBox(height: 12) between line 184 and line 186). A full-width swipe-to-start bar there is the natural home and inherits the selected-trip context (t) and locked already computed at 154-161.
UI, alternative — a fourth action(...) in _QuickActionsRow (1272-1291), but that row is icon-only 76px tiles and a destructive "End trip" doesn't belong beside Navigate/Scan/History.
Status surface — _TripStatusPill (1056) and _CompactInfoItem for _formatTime(trip.scheduledTime) (1023-1027) are where actualStartTime / elapsed time should be surfaced once start is explicit; both fields are already parsed and unused.
Data layer — new method(s) on OperatorTripRepository (file has no start/stop today; add beside scanBin at line 141), new constants in api_config.dart beside lines 128-131.
Backend — needs a new viewset in app/viewsets/operator_mobile/ (only 4 exist). scan_bin_viewset.py:184-194 _ensure_assignment_in_progress is the exact logic to extract/share so an explicit start and an implicit scan-start don't diverge. Nothing in operator_mobile ever writes actual_end_time today.
Locking — trip_sequence.dart needs no change for "end" (it flows through isFinished), but consider whether "start" should be blocked on locked trips; the locked bool at captain_home_tab.dart:161 is the flag to gate the new control with, mirroring how onScan is nulled at line 190.
Refresh — the control's success handler should call widget.onRefresh (wired to _loadAssignmentsForDriver, driver_home_page.dart:860), same as _openWeightEntry (captain_home_tab.dart:1594) and _openHouseholdCollection (:1889).
You've hit your session limit · resets 1:50pm (Asia/Calcutta)

I have a complete picture. Here is the report.

DailyTripAssignment start/stop lifecycle — current state
1. Model — app/models/core_modules/daily_operations/daily_trip_assignment.py
Status / approval constants
Constant	Value	Line
STATUS_SCHEDULED	"Scheduled"	:37
STATUS_IN_PROGRESS	"In Progress"	:38
STATUS_COMPLETED	"Completed"	:39
STATUS_CANCELLED	"Cancelled"	:40
STATUS_CHOICES	the 4 above	:42–47
APPROVAL_PENDING	"Pending"	:49
APPROVAL_APPROVED	"Approved"	:50
APPROVAL_REJECTED	"Rejected"	:51
APPROVAL_CHOICES	the 3 above	:53–57
Timing / lifecycle fields
Field	Type	Line	Notes
unique_id	CharField(50, unique, editable=False)	:63	TRIP-YYYY-MM-NNN, generated in _generate_trip_assignment_unique_id() :22
trip_date	DateField	:227	
scheduled_time	TimeField (not null)	:228	inherited from trip_plan_id.scheduled_time in save() :280
actual_start_time	TimeField (null/blank)	:229	⚠️ see flag below
actual_end_time	TimeField (null/blank)	:230	⚠️ see flag below
status	CharField(20, choices, default=Scheduled, db_index)	:236–241	
approval_status	CharField(20, choices, default=Pending, db_index)	:243–248	
remarks	TextField	:250	
created_at / updated_at	DateTimeField(auto_now_add / auto_now)	:256, :257	
vehicle_id	FK VehicleCreation (nullable)	:213	
There are NO odometer, latitude, longitude, start_*/end_* photo/geo/remark fields on this model at all. The only geo capture in the flow lives on child rows: BinCollectionEvent.driver_latitude/driver_longitude (used by scan_bin_viewset.py:_create_event), DailyTripCollectionPoint.status_latitude/status_longitude, DailyTripHouseholdCollection.status_latitude/status_longitude, and VehicleBreakdown.breakdown_lat/breakdown_lng (vehicle_breakdown.py:139–140).

Methods
save() — :275–292. Inherits staff template, vehicle, flat geo (copy_flat_geo) and scheduled_time from the trip plan; generates unique_id; on create copies waste_types and wards from the plan and calls sync_daily_assignment_stops_from_plan(). No timing/status logic.
__str__ — :295
mark_completed_if_all_cps_collected() — :298–315. The only model-level completion logic:
returns False if there are no trip_collection_points
returns False if any stop is not in {"Collected", "Missed"} (note: "Skipped"/collect-later stays unresolved)
sets status = STATUS_COMPLETED, and if actual_end_time is empty sets it to timezone.localtime().time(), saves with update_fields=["status","actual_end_time","updated_at"]
Bin trips only — it ignores DailyTripHouseholdCollection entirely, so a household/bulk trip is never auto-completed by this path.
There is no mark_started() / mark_completed() / duration property.
2. Every write-site for actual_start_time / actual_end_time / status
START (SCHEDULED → IN_PROGRESS, stamps actual_start_time)
#	File:line	Trigger	What it sets
1	app/viewsets/operator_mobile/scan_bin_viewset.py:184–194 (_ensure_assignment_in_progress)	first bin scan on POST /operator-mobile/scan-bin/	if status == Scheduled: status = In Progress; if actual_start_time empty → timezone.localtime().time(). update_fields=["status","updated_at"(,"actual_start_time")]
2	app/viewsets/core_modules/daily_operations/daily_trip_assignment_viewset.py:199–205 (update_status)	web/admin PATCH .../daily-trip-assignments/{uid}/status/ with {"status": "In Progress"}	actual_start_time = timezone.now().time() then instance.save() (full save, no update_fields). ⚠️ uses timezone.now() (UTC) not localtime() — inconsistent with every other site
3	app/serializers/core_modules/daily_operations/vehicle_breakdown_serializer.py:285–292	supervisor approves a VehicleBreakdown (replacement arranged)	swaps vehicle_id + alt_staff_template_id; if status == Scheduled → In Progress. Does NOT stamp actual_start_time — leaves it null while In Progress
4	app/management/commands/seeders/masters/transport_masters/trip_attendance.py:32–33	seeder only	forces In Progress
5	app/management/commands/seeders/superadmin/staff_management/driver_user.py:829–835, :849–855	seeder / demo reset	resets to Scheduled + Approved, nulls both actual_start_time and actual_end_time
END (→ COMPLETED, stamps actual_end_time)
#	File:line	Trigger	What it sets
6	app/models/.../daily_trip_assignment.py:298–315 (mark_completed_if_all_cps_collected)	see callers below	status = Completed, actual_end_time = localtime().time() if empty
6a	caller app/models/.../daily_trip_collection_point.py:228 (mark_collected)	any stop marked collected	→ 6
6b	caller app/models/.../daily_trip_collection_point.py:251 (mark_status)	stop marked Missed/Skipped	→ 6
6c	caller app/viewsets/.../secondary_bin_collection_event_viewset.py:238	web CRUD on a BinCollectionEvent	→ 6
6d	caller app/viewsets/.../daily_trip_collection_point_viewset.py:479 (_sync_assignment_and_log)	web CRUD on a trip stop	→ 6
6e	caller app/management/commands/backfill_daily_trip_logs.py:44–45	manual manage.py backfill_daily_trip_logs	→ 6
7	app/models/core_modules/daily_operations/daily_trip_log.py:389–399 (DailyTripLog.save())	any save of a DailyTripLog whose log_status is Submitted or Verified	assignment.status = Completed; actual_end_time = log.actual_end_time or localtime().time() if empty. This is the path the household/bluetooth flow reaches: finalize-waste (waste_bluetooth_viewset.py:335) → WasteCollection saved → signal sync_household_collection_on_waste_save (app/signals/trip_plan_signals.py:189) creates/updates the log and, when every household stop is collected, sets log_status = Submitted (:275–278) → assignment completed. Same for bins via sync_trip_log_on_bin_event_save (trip_plan_signals.py:281, auto-submit at :337–340)
8	app/viewsets/.../daily_trip_assignment_viewset.py:201–205	PATCH .../status/ with {"status":"Completed"}	actual_end_time = timezone.now().time()
9	app/viewsets/operator_mobile/scan_bin_viewset.py:196–227 (_upsert_trip_log)	end of a scan	creates/updates the DailyTripLog with log_status=Submitted when weight > 0 → indirectly triggers #7
10	app/viewsets/.../daily_trip_assignment_viewset.py:164–170 (perform_destroy)	DELETE	is_deleted=True, is_active=False, status = Cancelled
11	seeders: daily_trip_assignment.py:118–125, driver_user.py:555, :713, :790–791	seeding only	sets both times + Completed/Cancelled
Signals
app/signals/ contains only permission_signals.py and trip_plan_signals.py. trip_plan_signals.py has no direct write to DailyTripAssignment.status or the actual times — it only touches DailyTripHouseholdCollection and DailyTripLog; the assignment status change happens transitively through DailyTripLog.save() (#7). copy_trip_plan_stops_to_daily_assignment (:161–166, post_save on DailyTripAssignment) only clones stops.

Scheduler / cron
scheduler.sh → manage.py generate_daily_trips — creation only (nightly 00:05). app/services/daily_trip_scheduler.py (run_daily_trip_job) same. manage.py detect_sla_breaches and backfill_daily_trip_logs are the only other commands. There is no end-of-day auto-close job — a trip started but never finished stays In Progress forever.

3. Existing API surface — daily-trip-assignments
Registered at app/urls/base_urls.py:313: router.register_group("schedule-operations", "daily-trip-assignments", DailyTripAssignmentViewSet) → /api/v1/schedule-operations/daily-trip-assignments/. Related registrations: :314 daily-trip-collection-points, :315 daily-trip-household-collections, :316 bin-collection-events, :317 vehicle-breakdowns, :318 daily-trip-logs, :254 wastecollections.

app/viewsets/core_modules/daily_operations/daily_trip_assignment_viewset.py (full ModelViewSet, lookup_field="unique_id"):

Method	Path	Line	Notes
GET/POST	/daily-trip-assignments/	ModelViewSet	list filters: date/trip_date, today, trip_plan_id, status, waste_type_id(s), ward_id(s), geo scope, mine=true (supervisor) — :104–143
GET/PUT/PATCH	/{unique_id}/	:149–158	update blocked unless status == Scheduled
DELETE	/{unique_id}/	:164–177	soft-delete + Cancelled
PATCH	/{unique_id}/status/	:184–217	the only state-machine endpoint; stamps start/end times
PATCH	/{unique_id}/approval/	:224–254	approval action; gated by _has_approval_role → can_manage_trips (app/utils/roles.py)
GET	/scheduler-status/	:263–269	
GET/PATCH	/scheduler-config/	:271–312	
POST	/run-scheduler/	:314–332	
POST	/generate-daily/	:340–376	
There is no start, stop, end, or complete action. /{uid}/status/ is the closest thing and it is a web/admin endpoint (no driver-specific permission class, no geo/odometer payload).

DailyTripAssignmentStatusSerializer — app/serializers/.../daily_trip_assignment_serializer.py:379–396

class DailyTripAssignmentStatusSerializer(serializers.Serializer):
    VALID_TRANSITIONS = {
        DailyTripAssignment.STATUS_SCHEDULED:   [DailyTripAssignment.STATUS_IN_PROGRESS],
        DailyTripAssignment.STATUS_IN_PROGRESS: [DailyTripAssignment.STATUS_COMPLETED],
    }
    status = serializers.ChoiceField(choices=DailyTripAssignment.STATUS_CHOICES)
validate_status (:387–396): returns early if no instance in context; Cancelled is always allowed from any state (:392–393); otherwise the target must be in VALID_TRANSITIONS[current]. Note Completed and Cancelled have no entry → they are terminal. The serializer accepts only a status key — no timestamp, lat/lng, odometer, or remarks.

DailyTripAssignmentApprovalSerializer — :399+, single approval_status ChoiceField.

Main DailyTripAssignmentSerializer.Meta (:91–96): exposes trip_date, scheduled_time, actual_start_time, actual_end_time, status, approval_status, remarks, …; read_only_fields = ["unique_id", "actual_start_time", "actual_end_time", "approval_status", "created_at", "updated_at"] — so the times can never be set through normal CRUD.

4. Operator-mobile API surface
Registered app/urls/base_urls.py:366–394, prefix /api/v1/operator-mobile/:

Method	Endpoint	Viewset:line	What it does
GET	/operator-mobile/my-trip-today/	my_trip_today_viewset.py:16–32	single "active" trip via find_active_assignment_for_operator
GET	/operator-mobile/my-trips-today/	my_trip_today_viewset.py:35–56	{"results":[…]} all today's trips, ordered scheduled_time, unique_id
POST	/operator-mobile/validate-bin-qr/	validate_bin_qr_viewset.py:20–	dry-run bin check
POST	/operator-mobile/scan-bin/	scan_bin_viewset.py:32–	collect / mark-missed a bin; implicitly starts the trip
GET	/operator-mobile/trip-history/	trip_history_viewset.py:142–160	?from=&to=, capped at 200
GET	/operator-mobile/trip-history/{unique_id}/	trip_history_viewset.py:162–	detail
All gated by IsOperatorRole (app/permissions/operator_permission.py). Adjacent driver-facing surface lives outside this package: /waste-bluetooth/…/finalize-waste/, /mark-household-status/ (app/viewsets/waste_collection_bluetooth/waste_bluetooth_viewset.py:335, :47).

There is nothing resembling start-trip or end-trip. The driver has no way to say "I'm rolling" or "I'm done" — both are inferred from stop-level events.

progress_payload() — app/viewsets/operator_mobile/helpers.py:366–385
Returns {"collected": int, "total": int, "resolved": int, "completed": bool} where resolved counts Collected|Missed and completed = total > 0 and resolved == total. Bin stops only — it reads assignment.trip_collection_points, so household trips always report total=0, completed=False from this helper. (The serializer's own get_progress at trip_today_serializer.py:155–200 does handle household types; progress_payload does not — duplicated logic.)

Also in helpers: assignment_is_finished() :168–208 (already the "is this trip done?" predicate, handles both bin and household stops, returns True when there are no stops at all) and serialize_assignment_brief() :440–464 (returns unique_id, status, trip_date, panchayat, waste_types, vehicle — no times).

MyTripTodaySerializer — app/serializers/operator_mobile/trip_today_serializer.py:89–116
Fields returned to the driver app:
assignment_unique_id (source unique_id), trip_date (DateField), status (CharField :92), collection_type, scheduled_time (TimeField :96), actual_start_time (TimeField, allow_null :97), actual_end_time (TimeField, allow_null :98), panchayat, ward, waste_types, vehicle, progress, distance_meters, duration_seconds, route_geojson, vehicle_start, collection_points, household_collections, crew.

So the app already receives status, scheduled_time, actual_start_time, actual_end_time — it just has no way to write them. duration_seconds here is the routing duration from OpenRouteService (_route_for_assignment :272–319), not elapsed trip time.

trip_history_viewset._serialize_summary (:19–66) returns assignment_unique_id, trip_date, status, panchayat, ward, waste_types, progress, total_weight_kg — no actual_start_time/actual_end_time at all, so history can't show trip duration today.

5. DailyTripLog — app/models/core_modules/daily_operations/daily_trip_log.py
OneToOneField to DailyTripAssignment (:68–75) — one log per trip.
trip_date DateField :181; actual_start_time = TimeField(null) :182; actual_end_time = TimeField(null) :183 — same TimeField problem, mirrored.
autofill_from_assignment() :277–302 copies actual_start_time/actual_end_time from the assignment (:284–285) — the log is a mirror, not the source of truth.
No duration field, no property, no computation. daily_trip_log_serializer.py:425–428 only validates actual_end_time > actual_start_time (naive time comparison — breaks on trips crossing midnight).
log_status: Draft / Submitted / Verified (:48–56), plus verified_by/verified_at (:221–228, verified_at is a DateTimeField).
Weight aggregation: sync_from_secondary_bin_collection_events() :330–…, sync_from_household_collections() :306–….
save() :381–399 — autofill → full_clean() → save → sync weights → and the completion side-effect (#7 above).
Written from: scan_bin_viewset.py:196 _upsert_trip_log, trip_plan_signals.py:239–286 (household) and :281–340 (sync_trip_log_on_bin_event_save), daily_trip_collection_point_viewset.py:_upsert_trip_log_for_assignment (~:455–472), backfill_daily_trip_logs.py:68, plus the daily-trip-logs CRUD viewset.

Verdict: DailyTripLog is positioned as the trip's operational record (weight, crew, vehicle, verification), and it has the two timing columns — but they are copied from the assignment, never authored independently, and are TimeFields. It is a reasonable place to also persist a driver-authored start/end record, but the assignment must stay the authority since autofill reads from it, not vice versa.

6. Auto-completion & end-of-day
Auto-complete exists only via mark_completed_if_all_cps_collected() (bins, all stops Collected/Missed) and via DailyTripLog.save() when the log flips to Submitted/Verified (bins and households).
"Skipped" (collect-later) stops block auto-completion permanently — daily_trip_assignment.py:301.
A trip with zero stops is never auto-completed by mark_completed_if_all_cps_collected (:299–300 returns False), though assignment_is_finished() returns True for it (helpers.py:208) — the two "is it done" definitions disagree.
app/utils/ has no trip-timing helper. Relevant utils are hierarchy.py (copy_flat_geo), roles.py (can_manage_trips), crew.py, audit_mixin.py, bin_qr.py.
No cron/management command closes trips at end of day. cron.sh/scheduler.sh only generate tomorrow's trips.
7. Breakdown / exception interaction
VehicleBreakdown (app/models/core_modules/daily_operations/vehicle_breakdown.py) — OneToOneField to the assignment (:80), own status (REPORTED / REPLACEMENT_ARRANGED / REJECTED, :42–49), own approval_status (APPROVED/REJECTED/…, :53–59), breakdown_time = TimeField :138, breakdown_lat/breakdown_lng :139–140, collected_weight_before_breakdown_kg :142, approved_at = DateTimeField :175.
Creation validation (vehicle_breakdown_serializer.py:100–125): cannot report a breakdown on a Completed/Cancelled trip; requires Scheduled or In Progress.
Approval (vehicle_breakdown_serializer.py:285–292) is the third start-site: it force-advances Scheduled → In Progress without setting actual_start_time. So an approved-breakdown trip can be In Progress with a null start time — any duration math must handle this.
There is NO pause/resume state. The STATUS_CHOICES list has no Paused/On Hold. A breakdown does not stop the clock.
TripExceptionLog — app/serializers/superadmin/audits/trip_exception_log_serializer.py imports app.models.superadmin.audits.trip_exception_log, but that model file does not exist (app/models/superadmin/audits/ contains only audit_log.py, login_audit.py, permission_audit.py, staff_audit.py, staff_template_audit_log.py). The serializer is dead/broken code; it validates that the trip is not Completed/Cancelled (:29). "TripExceptionLog" is also listed in app/middleware/module_permission_middleware.py:208.
Two other things require status == In Progress, i.e. they depend on the trip having been started:
app/serializers/masters/transport_masters/trip_attendance_serializer.py:59 — "Attendance allowed only for in-progress trips" (and trip_attendance_viewset.py:120–145 resolves the trip by status in [In Progress, Scheduled])
app/serializers/superadmin/audits/vehicle_trip_audit_serializer.py:67 — "GPS audit allowed only for in-progress trips"
⚠️ TimeField flag (the big one)
DailyTripAssignment.actual_start_time (:229), actual_end_time (:230), scheduled_time (:228), and the mirrored DailyTripLog.actual_start_time/actual_end_time (:182–183) are all TimeField — a bare wall-clock time with no date and no timezone. Consequences for real duration math:

Midnight-crossing trips are unrepresentable. A 22:30 → 01:15 night trip computes as a negative duration. daily_trip_log_serializer.py:425–428 literally raises "actual_end_time must be after actual_start_time" for such a trip, blocking the save.
Timezone inconsistency is already live in the data. scan_bin_viewset.py:192 and daily_trip_log.py:394 / daily_trip_assignment.py:312 use timezone.localtime().time() (IST), while daily_trip_assignment_viewset.py:197 uses timezone.now().time() (UTC). The same column therefore holds values 5h30m apart depending on which path stamped it. Any duration computed across those paths is wrong.
No DB-level duration is derivable in SQL without reconstructing a datetime from trip_date, which is unsound for case (1).
created_at/updated_at/verified_at/approved_at are correctly DateTimeField — so the schema already mixes the two conventions.
Recommendation: add actual_start_at / actual_end_at as DateTimeField(null=True) and keep the existing TimeFields populated as derived values for backward compatibility with the dashboards (dashboard_summary_viewset.py:826–827, 1023, 1044, staff_access_dashboard_viewset.py:1105–1112) and the mobile serializer (trip_today_serializer.py:97–98).

What is MISSING for an explicit driver-initiated start/end
No driver-facing start endpoint. Nothing under /operator-mobile/ writes status. The only start paths are (a) an implicit side-effect of the first bin scan — which does not exist at all for household/bulk trips — and (b) an admin PATCH /schedule-operations/daily-trip-assignments/{uid}/status/ that a driver token is not intended to hit.
No driver-facing end/complete endpoint. Completion is inferred from "all stops resolved" or from a DailyTripLog flipping to Submitted. A driver cannot end a trip with stops still Skipped/Pending (e.g. area flooded, vehicle full, shift over) — the trip is stuck In Progress forever with no cron to close it.
No datetime-precision timestamps — see TimeField flag. Duration math is not safely possible today.
No start/end capture payload: no odometer (start/end reading), no start/end latitude/longitude, no start/end photo, no start/end remarks fields anywhere on the assignment or the log. Geo is only captured per-bin on BinCollectionEvent.driver_latitude/longitude.
No idempotency/guard semantics for a real start: _ensure_assignment_in_progress silently no-ops if already In Progress; a dedicated action needs explicit 409-style responses (ALREADY_STARTED, ALREADY_ENDED, NOT_STARTED) consistent with OperatorFlowError (helpers.py:16–23).
No pre-start guards: nothing checks approval_status == Approved, trip_date == today, or that the requester is the effective crew, before a trip goes In Progress. _effective_staff_q (helpers.py:49–55) is the existing crew-identity predicate to reuse.
actual_start_time can be null while In Progress — the breakdown-approval path (vehicle_breakdown_serializer.py:289–291) sets status without a timestamp; a start action must backfill.
Trip history omits the times (trip_history_viewset.py:37–66), so even once written, the driver app can't display duration for past trips.
No paused/on-hold status for breakdowns — a breakdown neither stops the clock nor is subtractable from elapsed time.
Two conflicting "is finished" definitions — assignment_is_finished() (helpers.py:168, includes households, treats zero-stop trips as finished) vs mark_completed_if_all_cps_collected() (daily_trip_assignment.py:298, bins only, treats zero-stop trips as unfinished). An explicit end action should consolidate on one.
Best reuse candidates
DailyTripAssignmentStatusSerializer.VALID_TRANSITIONS (daily_trip_assignment_serializer.py:380–383) — already the correct state machine; extend it rather than writing a second one.
helpers.find_active_assignment_for_operator / find_all_active_assignments_for_operator / _effective_staff_q / OperatorFlowError / serialize_assignment_brief / progress_payload (helpers.py:16, 49, 64, 130, 366, 440) — the whole operator-mobile plumbing a start/end action needs.
scan_bin_viewset._ensure_assignment_in_progress (:184–194) — should be refactored to call a shared assignment.mark_started(...) model method rather than duplicating the flip.
mark_completed_if_all_cps_collected (daily_trip_assignment.py:298) — extend into a mark_completed(force=…) that the explicit end action can call.
IsOperatorRole (app/permissions/operator_permission.py) and AuditViewSetMixin / log_common_audit (app/utils/audit_mixin.py) for permissioning and audit trail.
You've hit your session limit · resets 1:50pm (Asia/Calcutta)