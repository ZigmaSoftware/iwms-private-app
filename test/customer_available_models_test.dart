import 'package:flutter_test/flutter_test.dart';
import 'package:iwms_private_app/data/models/citizen_pickup_model.dart';
import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';

void main() {
  group('CitizenPickupToday', () {
    test('no-collection service notice survives when there is no stop', () {
      final payload = {
        'stop': null,
        'service_notice': {
          'unique_id': 'DSN-1',
          'reason_label': 'Flooding',
          'reason_text': 'Access roads are closed',
        }
      };
      expect(CitizenPickupToday.fromResponse(payload), isNull);
      final notice = CitizenServiceNotice.fromResponse(payload)!;
      expect(notice.explanation, 'Access roads are closed');
    });
    test('no stop today parses to null', () {
      expect(CitizenPickupToday.fromResponse({'stop': null}), isNull);
    });

    test('collect later offers "I\'m home now" until flagged', () {
      final open = CitizenPickupToday.fromResponse({
        'stop': {'unique_id': 'S1', 'status': 'Collect Later'}
      })!;
      expect(open.canSayImHome, isTrue);

      final flagged = CitizenPickupToday.fromResponse({
        'stop': {
          'unique_id': 'S1',
          'status': 'Collect Later',
          'customer_available_at': '2026-10-14T10:42:00+05:30',
        }
      })!;
      expect(flagged.canSayImHome, isFalse);
      expect(flagged.customerAvailableAt, isNotNull);
    });

    test('not available carries the auto ticket number', () {
      final s = CitizenPickupToday.fromResponse({
        'stop': {
          'unique_id': 'S1',
          'status': 'Not Available',
          'missed_pickup_ticket_no': 'IWMS-000042',
        }
      })!;
      expect(s.isNotAvailable, isTrue);
      expect(s.missedPickupTicketNo, 'IWMS-000042');
    });

    test('collected pickup parses proof image and waste breakdown', () {
      final pickup = CitizenPickupToday.fromResponse({
        'stop': {
          'unique_id': 'S1',
          'status': 'Collected',
          'collection_image_url': 'https://iwms.example/media/proof.jpg',
          'waste_breakdown': [
            {'waste_type': 'Mixed Waste', 'weight_kg': 2.5},
          ],
        }
      })!;

      expect(pickup.collectionImageUrl, 'https://iwms.example/media/proof.jpg');
      expect(pickup.wasteDescription, 'Mixed Waste');
      expect(pickup.wasteBreakdown.single.weightKg, 2.5);
    });

    test('exception status uses its evidence image as pickup proof', () {
      final pickup = CitizenPickupToday.fromResponse({
        'stop': {
          'unique_id': 'S1',
          'status': 'Collect Later',
          'status_evidence_image_url':
              'https://iwms.example/media/status-proof.jpg',
        }
      })!;

      expect(
          pickup.proofImageUrl, 'https://iwms.example/media/status-proof.jpg');
    });
  });

  test('driver stop is waiting only while unresolved', () {
    OperatorTripHouseholdStop stop(String status, {bool collected = false}) =>
        OperatorTripHouseholdStop.fromJson({
          'unique_id': 'S1',
          'status': status,
          'is_collected': collected,
          'customer_available_at': '2026-10-14T10:42:00Z',
          'customer': {'unique_id': 'C1', 'name': 'A'},
        });
    expect(stop('Collect Later').customerWaiting, isTrue);
    expect(stop('Collected', collected: true).customerWaiting, isFalse);
    expect(stop('Not Available').customerWaiting, isFalse);
  });

  test('supervisor plan option exposes understandable operational states', () {
    final plan = SupervisorPlanOption.fromJson({
      'trip_plan_id': 'TPLAN-1',
      'display_code': 'WARD-B-01',
      'collection_type': 'household_collection',
      'scheduled_time': '06:00',
      'state': 'NO_COLLECTION',
      'ward_names': ['B'],
      'notice': {
        'unique_id': 'DSN-1',
        'reason_code': 'FLOOD',
        'reason_label': 'Flooding',
        'reason_text': '',
      }
    });
    expect(plan.noCollection, isTrue);
    expect(plan.areaName, 'Ward B');
    expect(plan.notice?.explanation, 'Flooding');
  });

  test('supervisor assignment counts waiting customers and flags attention',
      () {
    final a = SupervisorAssignment.fromJson({
      'unique_id': 'T1',
      'status': 'In Progress',
      'approval_status': 'Approved',
      'trip_date': '2026-10-14',
      'scheduled_time': '08:00:00',
      'effective_staff': {'driver': 'D'},
      'vehicle': {'vehicle_no': 'KL01'},
      'collection_types': {'has_household': true},
      'household_collection_points': [
        {
          'unique_id': 'H1',
          'status': 'Collect Later',
          'customer_available_at': '2026-10-14T10:42:00Z',
        },
        {'unique_id': 'H2', 'status': 'Collect Later'},
      ],
    });
    expect(a.customersWaitingCount, 1);
    final alerts = a.alerts(DateTime(2026, 10, 14, 11));
    final waiting =
        alerts.singleWhere((x) => x.kind == TripAlertKind.customersWaiting);
    expect(waiting.count, 1);
    expect(waiting.severity, TripAlertSeverity.info);
    expect(a.attentionLabels(DateTime(2026, 10, 14, 11)),
        contains('Customer waiting for pickup'));
  });
}
