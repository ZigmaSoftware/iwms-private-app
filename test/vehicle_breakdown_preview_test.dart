import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iwms_private_app/data/repositories/vehicle_breakdown_repository.dart';

void main() {
  VehicleBreakdownRepository repository({
    required int previewStatus,
    int reportStatus = 200,
    required List<RequestOptions> requests,
  }) {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      final preview = request.path.endsWith('/verify-preview/');
      final status = preview ? previewStatus : reportStatus;
      final data = status == 200
          ? (preview
              ? <String, dynamic>{
                  'upcoming_trips': [],
                  'plans': [],
                  'substitute_from_date': '2026-10-31',
                }
              : <String, dynamic>{'unique_id': 'BD-1'})
          : <String, dynamic>{'detail': 'Request failed ($status)'};
      final response = Response<dynamic>(
        requestOptions: request,
        statusCode: status,
        data: data,
      );
      if (status == 200) {
        handler.resolve(response);
      } else {
        handler.reject(DioException(
          requestOptions: request,
          response: response,
          type: DioExceptionType.badResponse,
        ));
      }
    }));
    return VehicleBreakdownRepository(dioProvider: () async => dio);
  }

  test('successful replacement preview needs no compatibility check', () async {
    final requests = <RequestOptions>[];
    final repo = repository(previewStatus: 200, requests: requests);
    final preview =
        await repo.fetchVerifyPreview('BD-1', replacementVehicleId: 'VEH-2');
    expect(preview.substituteFromDate, '2026-10-31');
    expect(requests, hasLength(1));
    expect(requests.single.queryParameters['replacement_vehicle_id'], 'VEH-2');
  });

  test('filtered preview 404 checks report without replacement filter',
      () async {
    final requests = <RequestOptions>[];
    final repo = repository(previewStatus: 404, requests: requests);
    await expectLater(
      repo.fetchVerifyPreview('BD-1', replacementVehicleId: 'VEH-2'),
      throwsA(isA<VehicleBreakdownPreviewUnavailable>()),
    );
    expect(requests, hasLength(2));
    expect(requests.last.path, endsWith('/BD-1/'));
    expect(requests.last.queryParameters, isEmpty);
    expect(requests.every((r) => r.method == 'GET'), isTrue);
  });

  for (final reportStatus in [403, 404, 500]) {
    test('report failure $reportStatus remains a real error', () async {
      final requests = <RequestOptions>[];
      final repo = repository(
        previewStatus: 404,
        reportStatus: reportStatus,
        requests: requests,
      );
      await expectLater(
        repo.fetchVerifyPreview('BD-1', replacementVehicleId: 'VEH-2'),
        throwsA(isA<VehicleBreakdownException>()
            .having((e) => e is VehicleBreakdownPreviewUnavailable,
                'compatibility fallback', false)
            .having((e) => e.message, 'message', contains('$reportStatus'))),
      );
    });
  }

  for (final previewStatus in [403, 500]) {
    test('preview failure $previewStatus does not use fallback', () async {
      final requests = <RequestOptions>[];
      final repo = repository(previewStatus: previewStatus, requests: requests);
      await expectLater(
        repo.fetchVerifyPreview('BD-1', replacementVehicleId: 'VEH-2'),
        throwsA(isA<VehicleBreakdownException>().having(
            (e) => e is VehicleBreakdownPreviewUnavailable,
            'compatibility fallback',
            false)),
      );
      expect(requests, hasLength(1));
    });
  }
}
