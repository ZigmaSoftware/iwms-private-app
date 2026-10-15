import 'package:flutter_test/flutter_test.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_models.dart';

SupervisorAssignment assignmentWith({
  required String status,
  required String approvalStatus,
}) {
  return SupervisorAssignment(
    uniqueId: 'TRIP-1',
    areaName: 'B',
    zoneId: 'ZONE-1',
    zoneName: 'Zone 1',
    wardName: 'B',
    tripCode: 'TRIP-1',
    wasteTypeName: 'Mixed Waste',
    vehicleNo: 'UP16KT1912',
    driverName: 'ASHISH KASANA',
    operatorName: 'CHREN SINGH',
    status: status,
    approvalStatus: approvalStatus,
    tripDate: DateTime(2026, 10, 14),
    scheduledTime: '10:43:00',
    remarks: '',
  );
}

void main() {
  final serverNow = DateTime(2026, 10, 14, 10, 30);

  test('assignment approval is not shown on trip cards', () {
    final scheduled = assignmentWith(
      status: 'SCHEDULED',
      approvalStatus: 'PENDING',
    );
    final running = assignmentWith(
      status: 'IN_PROGRESS',
      approvalStatus: 'PENDING',
    );

    expect(
      scheduled.attentionLabels(serverNow),
      isNot(contains('Awaiting assignment approval')),
    );
    expect(
      running.attentionLabels(serverNow),
      isNot(contains('Awaiting assignment approval')),
    );
  });
}
