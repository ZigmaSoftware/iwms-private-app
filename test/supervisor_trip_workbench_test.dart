import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iwms_private_app/data/models/trip_retrip_models.dart';
import 'package:iwms_private_app/data/models/vehicle_breakdown_models.dart';
import 'package:iwms_private_app/data/repositories/trip_retrip_repository.dart';
import 'package:iwms_private_app/data/repositories/vehicle_breakdown_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_trip_workbench.dart';
import 'package:iwms_private_app/modules/module5_supervisor/logic/supervisor_bloc.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_assignment_card.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_today_operations.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_trips_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_history_screen.dart';

final day = DateTime(2026, 9, 9);
Map<String, dynamic> tripJson(String id, String status,
        {String date = '2026-09-09',
        List<Map<String, dynamic>> stops = const []}) =>
    {
      'unique_id': id,
      'status': status,
      'approval_status': 'Approved',
      'trip_date': date,
      'scheduled_time': '08:00:00',
      'panchayat': {'panchayat_name': 'Test area'},
      'effective_staff': {'driver': 'Test driver', 'operator': 'Test operator'},
      'vehicle': {'vehicle_no': 'KL 01 1234'},
      'collection_types': {'has_bin': true},
      'collection_points': stops,
    };
SupervisorAssignment trip(String id, String status,
        {String date = '2026-09-09',
        List<Map<String, dynamic>> stops = const []}) =>
    SupervisorAssignment.fromJson(
        tripJson(id, status, date: date, stops: stops));
SupervisorTripWorkbench board(List<SupervisorAssignment> items) =>
    SupervisorTripWorkbench(
        serviceDate: day,
        serverNow: DateTime(2026, 9, 9, 10),
        assignments: items);

class FakeTrips extends SupervisorRepository {
  FakeTrips(this.snapshot);
  SupervisorTripWorkbench snapshot;
  Object? failure;
  Completer<void>? gate;
  int calls = 0;
  List<SupervisorPlanOption> todayPlans = const [];

  @override
  Future<List<SupervisorPlanOption>> fetchTodayPlanOptions() async =>
      todayPlans;
  @override
  Future<SupervisorTripWorkbench> fetchTripWorkbench() async {
    calls++;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return snapshot;
  }

  @override
  Future<SupervisorTripHistoryPage> fetchTripHistoryPage(
      {DateTime? from,
      DateTime? to,
      String? status,
      String search = '',
      bool retripOnly = false,
      bool exceptionsOnly = false,
      int offset = 0}) async {
    if (failure != null) throw failure!;
    return SupervisorTripHistoryPage(
        items: snapshot.assignments.where((a) => !a.isRemaining).toList(),
        count: snapshot.assignments.where((a) => !a.isRemaining).length,
        hasMore: false,
        serviceDate: day);
  }
}

class FakeRetrips extends TripRetripRepository {
  bool fail = false;
  List<TripRetripRequest> items = [];
  @override
  Future<List<TripRetripRequest>> fetchRequests(
      {String? status, bool mine = true}) async {
    if (fail) throw Exception('offline');
    return items;
  }
}

class FakeBreakdowns extends VehicleBreakdownRepository {
  @override
  Future<List<VehicleBreakdownReport>> fetchBreakdowns(
          {String? approvalStatus, bool mine = false}) async =>
      [];
}

SupervisorBloc makeBloc(FakeTrips repo, {FakeRetrips? retrips}) =>
    SupervisorBloc(
        repository: repo,
        retripRepository: retrips ?? FakeRetrips(),
        breakdownRepository: FakeBreakdowns());

Future<void> showTrips(WidgetTester tester, SupervisorBloc bloc,
    {double scale = 1}) async {
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
          data: MediaQueryData(
              size: const Size(320, 700), textScaler: TextScaler.linear(scale)),
          child: BlocProvider.value(
              value: bloc,
              child: const Scaffold(body: SupervisorTripsScreen())))));
  await tester.pumpAndSettle();
}

void main() {
  test(
      'remaining work excludes terminal and future trips but keeps old unresolved',
      () {
    final data = board([
      trip('done', 'Completed'),
      trip('cancelled', 'Cancelled'),
      trip('today', 'Scheduled'),
      trip('old', 'In Progress', date: '2026-08-01'),
      trip('future', 'Scheduled', date: '2026-09-10'),
    ]);
    expect(data.remaining.map((a) => a.uniqueId), ['today', 'old']);
    expect(data.today.length, 3);
    expect(data.carriedOver.single.uniqueId, 'old');
  });
  test('service wall time preserves server date across UTC offset', () {
    final time = parseServiceWallTime('2026-09-09T00:15:00+05:30');
    expect(time.day, 9);
    expect(time.hour, 0);
  });
  test('resolved stops keep trip active until server closes it', () {
    final a = trip('ready', 'In Progress', stops: [
      {'unique_id': 'a', 'is_collected': true, 'status': 'Collected'},
      {'unique_id': 'b', 'is_collected': false, 'status': 'Missed'},
    ]);
    expect(a.awaitingClosure, isTrue);
    expect(a.isRemaining, isTrue);
    expect(a.collectedCount, 1);
    expect(a.unavailableCount, 1);
  });
  test('collect later is unresolved and not collected', () {
    final a = trip('later', 'In Progress', stops: [
      {'status': 'Skipped', 'is_collected': false}
    ]);
    expect(a.unresolvedCount, 1);
    expect(a.deferredCount, 1);
    expect(a.awaitingClosure, isFalse);
  });
  test('history preserves recorded staff, real duration and stop details', () {
    final a = SupervisorAssignment.fromJson({
      ...tripJson('done', 'Completed', stops: [
        {
          'status': 'Collected',
          'is_collected': true,
          'collected_weight_kg': '12.5'
        },
      ]),
      'trip_log_summary': {
        'driver': 'Recorded driver',
        'vehicle_no': 'Old vehicle',
        'status': 'Unverified'
      },
      'total_trip_time_seconds': 9000,
      'trip_count': 2
    });
    expect(a.driverName, 'Recorded driver');
    expect(a.vehicleNo, 'Old vehicle');
    expect(a.totalCollectedWeightKg, 12.5);
    expect(a.totalTripTimeSeconds, 9000);
    expect(a.tripCount, 2);
  });
  test('repository follows workbench pages before returning totals', () async {
    final dio = Dio();
    final offsets = <int>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      final offset = request.queryParameters['offset'] as int;
      offsets.add(offset);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'results': [tripJson(offset == 0 ? 'one' : 'two', 'Scheduled')],
        'count': 2,
        'next': offset == 0 ? 'next' : null,
        'service_date': '2026-09-09',
        'as_of': '2026-09-09T10:00:00+05:30',
      }));
    }));
    final data = await SupervisorRepository(dioProvider: () async => dio)
        .fetchTripWorkbench();
    expect(offsets, [0, 1]);
    expect(data.remaining.length, 2);
  });
  test('malformed or old backend responses cannot become no-trips', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (r, h) => h.resolve(Response(
              requestOptions: r, data: {'results': []}, statusCode: 200))));
    await expectLater(
        SupervisorRepository(dioProvider: () async => dio).fetchTripWorkbench(),
        throwsA(isA<SupervisorException>()));
  });
  test('history sends all filters and server pagination', () async {
    final dio = Dio();
    RequestOptions? sent;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      sent = r;
      h.resolve(Response(requestOptions: r, statusCode: 200, data: {
        'results': [],
        'count': 31,
        'next': null,
        'service_date': '2026-09-09',
        'as_of': '2026-09-09T10:00:00+05:30',
      }));
    }));
    await SupervisorRepository(dioProvider: () async => dio)
        .fetchTripHistoryPage(
            from: day,
            to: day,
            status: 'Cancelled',
            search: 'KL01',
            retripOnly: true,
            exceptionsOnly: true,
            offset: 30);
    expect(sent!.queryParameters, containsPair('trip_view', 'history'));
    expect(sent!.queryParameters, containsPair('offset', 30));
    expect(sent!.queryParameters, containsPair('status', 'Cancelled'));
    expect(sent!.queryParameters, containsPair('from_date', '2026-09-09'));
  });
  test('completion updates counts; refresh failure retains confirmed trips',
      () async {
    final repo = FakeTrips(board([trip('one', 'In Progress')]));
    final bloc = makeBloc(repo);
    await bloc.refresh();
    expect(bloc.state.activeTrips.length, 1);
    repo.failure = Exception('offline');
    await bloc.refresh();
    expect(bloc.state.activeTrips.length, 1);
    expect(bloc.state.errorMessage, isNotNull);
    repo.failure = null;
    repo.snapshot = board([trip('one', 'Completed')]);
    await bloc.refresh();
    expect(bloc.state.activeTrips, isEmpty);
    expect(bloc.state.completed.length, 1);
    await bloc.close();
  });
  test('loss of access clears cached trips', () async {
    final repo = FakeTrips(board([trip('one', 'In Progress')]));
    final bloc = makeBloc(repo);
    await bloc.refresh();
    repo.failure = SupervisorException('Forbidden', code: 'FORBIDDEN');
    await bloc.refresh();
    expect(bloc.state.assignments, isEmpty);
    expect(bloc.state.workbench, isNull);
    await bloc.close();
  });
  test('overlapping refreshes share the request and await its completion',
      () async {
    final repo = FakeTrips(board([]))..gate = Completer<void>();
    final bloc = makeBloc(repo);
    final first = bloc.refresh();
    final second = bloc.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(repo.calls, 1);
    repo.gate!.complete();
    await Future.wait([first, second]);
    expect(bloc.state.refreshing, isFalse);
    await bloc.close();
  });
  testWidgets('completed day shows success and no active completed cards',
      (tester) async {
    final bloc = makeBloc(FakeTrips(board([trip('done', 'Completed')])));
    final refreshing = bloc.refresh();
    await tester.pump();
    await refreshing;
    await showTrips(tester, bloc);
    expect(find.text('Active · 0'), findsOneWidget);
    expect(find.text('All today’s trips completed.'), findsOneWidget);
    expect(find.text('View today’s history'), findsOneWidget);
    expect(find.text('Track vehicle'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    // Deliberately not closing the bloc here: `Bloc.close()` deadlocks inside
    // `testWidgets` once an event has gone through an `on<Event>` handler —
    // reproduced even with a trivial bloc that has nothing to do with this
    // feature, so it's an environment/package interaction, not an app bug.
    // The bloc is process-scoped and this test process exits right after the
    // file finishes, so nothing actually leaks. A plain (non-widget) `test()`
    // closes a bloc fine — see the `test()` cases above.
  });
  testWidgets('unknown decision state does not claim all work is done',
      (tester) async {
    final retrips = FakeRetrips()..fail = true;
    final bloc = makeBloc(FakeTrips(board([trip('done', 'Completed')])),
        retrips: retrips);
    final refreshing = bloc.refresh();
    await tester.pump();
    await refreshing;
    await showTrips(tester, bloc);
    expect(find.text('All today’s trips completed.'), findsNothing);
    expect(
        find.textContaining('Decisions may still be pending.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    // See the note in the previous test — bloc.close() is skipped here too.
  });
  testWidgets(
      'small screen and larger text render active cards without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bloc = makeBloc(FakeTrips(board([
      trip('old', 'In Progress', date: '2026-09-08', stops: [
        {'status': 'Pending', 'is_collected': false},
      ])
    ])));
    final refreshing = bloc.refresh();
    await tester.pump();
    await refreshing;
    await showTrips(tester, bloc, scale: 1.5);
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('From earlier days'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    // See the note above — bloc.close() is skipped here too.
  });
  testWidgets('history exposes cancelled assignments and summary action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: SupervisorHistoryScreen(
            repository: FakeTrips(board([trip('cancelled', 'Cancelled')])),
            serviceDate: day)));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(SupervisorAssignmentCard),
            matching: find.text('Cancelled')),
        findsOneWidget);
    expect(find.text('View trip summary'), findsOneWidget);
    expect(find.text('Track vehicle'), findsNothing);
  });
  testWidgets('home route card keeps both supervisor actions visible',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeTrips(board([]))
      ..todayPlans = const [
        SupervisorPlanOption(
          tripPlanId: 'plan-1',
          displayCode: 'PLAN-1',
          collectionType: 'household_collection',
          scheduledTime: '08:00 AM',
          state: 'NEEDS_ASSIGNMENT',
          vehicleNo: 'KL 01 1234',
          teamCode: 'Team 1',
          driverName: 'Test driver',
          operatorName: 'Test operator',
          areaName: 'Ward B',
        ),
      ];
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 700),
          textScaler: TextScaler.linear(1.35),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SupervisorTodayOperations(
              updatedAt: null,
              assignments: const [],
              repository: repo,
              onChanged: () async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Today\'s operations'), findsNothing);
    expect(find.text('Review and assign the routes under your supervision'),
        findsNothing);
    expect(find.text('Assign trip'), findsOneWidget);
    // The rarely used, customer-notifying action lives in the ⋯ menu.
    expect(find.text('No collection today'), findsNothing);
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('No collection today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alerts collapse into one row that opens a grouped sheet',
      (tester) async {
    final json = tripJson('t-alerts', 'In Progress')
      ..['collection_types'] = {'has_household': true}
      ..['breakdown_info'] = {
        'approval_status': 'PENDING',
        'breakdown_reason': 'Flat tyre',
      }
      ..['household_collection_points'] = [
        for (var i = 0; i < 12; i++)
          {
            'unique_id': 'h$i',
            'sequence': i,
            'status': 'Collect Later',
            'customer': {'customer_name': 'Customer $i'},
            'customer_available_at': '2026-09-09T09:${10 + i}:00',
          },
      ];
    final a = SupervisorAssignment.fromJson(json);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SupervisorAssignmentCard(
            assignment: a,
            serverNow: DateTime(2026, 9, 9, 10),
            onTap: () {},
          ),
        ),
      ),
    ));
    // One breakdown + 12 customers waiting = 13, led by the critical one.
    expect(find.text('Vehicle breakdown · +12 more'), findsOneWidget);
    expect(find.text('13 alerts'), findsOneWidget);
    expect(find.textContaining('home now'), findsNothing);

    await tester.tap(find.text('13 alerts'));
    await tester.pumpAndSettle();
    expect(find.text('Needs your action · 1'), findsOneWidget);
    expect(find.text('For your info · 12'), findsOneWidget);
    expect(find.text('Customers waiting (12)'), findsOneWidget);
    expect(find.text('Customer 0'), findsNothing);
    await tester.tap(find.text('Customers waiting (12)'));
    await tester.pumpAndSettle();
    expect(find.text('Customer 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan card shows the team as faces plus its code',
      (tester) async {
    final plan = SupervisorPlanOption.fromJson({
      'trip_plan_id': 'plan-2',
      'collection_type': 'household_collection',
      'scheduled_time': '14:28',
      'state': 'NEEDS_ASSIGNMENT',
      'vehicle_no': 'UP16KT1912',
      'team_code': 'ASHI-CHRE-01',
      'driver_name': 'ASHISH KASANA',
      'operator_name': 'Chren Singh',
      'ward_names': ['B'],
      'team_members': [
        {'unique_id': 's1', 'name': 'Ashish Kasana', 'role': 'Driver'},
        {'unique_id': 's2', 'name': 'Chren Singh', 'role': 'Operator'},
        {'unique_id': 's3', 'name': 'Ravi Kumar', 'role': 'Operator'},
        {'unique_id': 's4', 'name': 'Imran Khan', 'role': 'Operator'},
      ],
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SupervisorPlanCard(plan: plan, onAssign: () {}),
      ),
    ));
    expect(find.text('Team:'), findsOneWidget);
    expect(find.textContaining('Suggested'), findsNothing);
    expect(find.textContaining('ASHI\u2011CHRE\u201101'), findsOneWidget);
    // Four members: two faces, then "+2".
    expect(find.text('AK'), findsOneWidget);
    expect(find.text('CS'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a completed trip collapses to one summary row',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SupervisorAssignmentCard(
          assignment: trip('t-done', 'Completed'),
          serverNow: DateTime(2026, 9, 9, 10),
          onTap: () {},
        ),
      ),
    ));
    expect(find.text('View trip'), findsNothing);
    expect(find.byTooltip('More actions'), findsNothing);
    expect(find.textContaining('Completed'), findsOneWidget);
  });
}
