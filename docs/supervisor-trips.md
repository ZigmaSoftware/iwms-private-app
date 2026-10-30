# Supervisor trips

The Trips section separates remaining work from completed and cancelled trips.
The existing supervisor colours and four navigation tabs are retained.

## Active

Active opens by default. It contains today's unstarted and running trips, plus
unfinished trips from earlier service dates under **Carried over**. It excludes
completed, cancelled and future assignments. Today is determined by the server,
not the device calendar. The app no longer substitutes yesterday for an empty day.

The Trips badge on the Dashboard and navigation bar counts distinct remaining
trips, including carried-over work. It disappears at zero. The daily summary
counts only today's assignments. Re-Trip requests and breakdown decisions have
separate counts and remain visible even when no active trips remain.

Search by trip, area, driver or vehicle. Filter by running, not started or needs
attention. Within each group, trips with reported issues, missing assignments,
pending approval, overdue starts or pending closure appear first. A scheduled
start that has passed is labelled overdue; this is not a prediction of a delay.

Collection progress distinguishes collected stops from unavailable/missed stops
and unresolved stops. Collect Later/Skipped stays unresolved. A trip whose stops
are resolved remains active until the server confirms completion.

### Actions

- Running trips provide **Track vehicle** and trip details.
- Granted staff-substitution actions use the existing substitution workflow.
- Pending breakdowns open the existing breakdown review and replacement flow.
- Users with assignment edit permission can approve/reject pending unstarted
  assignments or cancel an unstarted trip. Rejection and cancellation require a
  reason. Cancellation checks that the trip is still Scheduled on the server.
- Completed/cancelled trips provide **View trip summary**, without live tracking
  or operational edit buttons.

If no trips were scheduled, the app says so. If every trip completed and decision
checks succeeded, it shows **All today's trips completed** and a link to today's
history. Cancelled work is reported separately. If decisions remain, or their
fetch failed, the app does not claim that all work is done.

## History

History is available inside Trips and from the Dashboard's **Trip history**
shortcut. It opens to seven service dates and supports Today, Yesterday, Last
7 days and a custom range. Search and outcome, Re-Trip and exception filters are
applied on the server before pagination. **Load more trips** retrieves older rows
without interpreting the first page as the whole result.

History uses daily assignments, so a completed or cancelled assignment remains
visible even without a collection log. Summaries include recorded collection
outcomes/weights, actual start/end times, duration, run number, staff and vehicle,
log verification state, breakdown information, delay reports and Re-Trip events.
When available, the collection log's recorded staff/vehicle take precedence over
the current staff template. Completed is separate from Verified.

History covers non-deleted completed/cancelled assignments. Unfinished older
assignments stay in Active. Soft-deleted administrative records are not exposed.
A missing log is labelled explicitly, rather than rendered as a missing trip.

## Refresh and access

The shell refreshes while the Dashboard or Trips is visible every 30 seconds,
on app resume, on entering those tabs and after trip actions. Pull-to-refresh
waits for completion. Overlapping refresh requests share one fetch. Failed
refreshes retain the last confirmed snapshot with a warning and update time;
access-denied responses clear cached trips. History has independent refresh and
pagination, and ignores responses belonging to superseded filters.

## Backend rollout and boundaries

Deploy the matching private backend before using this app build. No model or
schema migration is introduced by these changes. The app requires the new
`trip_view` response metadata and reports unavailable data if it is absent.

Existing company/project permissions and current trip-plan supervisor ownership
continue to determine access. There is no new historical supervisor-ownership
snapshot, GPS replay, automatic cancellation/rescheduling, or automatic trip
closure. Current templates/logs do not supply a complete immutable substitution
audit. The screen only displays events and actuals that have been recorded.

## Verification

- App: `flutter test test/supervisor_trip_workbench_test.dart`
- Backend: `.venv/bin/python -m pytest tests/schedule_setup/test_supervisor_trip_workbench.py`

Also verify on a deployed test environment with a supervisor account: complete
one trip while the app is open; approve a Re-Trip; switch dates; load more history;
disconnect/reconnect; and confirm server permissions for trip actions.
