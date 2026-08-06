backend:
[05/Aug/2026 10:11:17] "POST /api/v1/login/ HTTP/1.1" 200 4931
Not Found: /api/v1/login/my-permissions/
[05/Aug/2026 10:11:17] "GET /api/v1/login/my-permissions/ HTTP/1.1" 404 226466
Forbidden: /api/v1/complaint-ticket/grievance-tickets/
[05/Aug/2026 10:11:18] "GET /api/v1/complaint-ticket/grievance-tickets/ HTTP/1.1" 403 110
Forbidden: /api/v1/schedule-setup/collection-points/
Forbidden: /api/v1/schedule-operations/vehicle-breakdowns/
[05/Aug/2026 10:11:18] "GET /api/v1/schedule-operations/vehicle-breakdowns/?approval_status=PENDING HTTP/1.1" 403 114
Forbidden: /api/v1/schedule-operations/staff-notifications/unread-count/
[05/Aug/2026 10:11:18] "GET /api/v1/schedule-setup/collection-points/ HTTP/1.1" 403 108
[05/Aug/2026 10:11:18] "GET /api/v1/schedule-operations/staff-notifications/unread-count/ HTTP/1.1" 403 115
Forbidden: /api/v1/schedule-operations/daily-trip-assignments/
[05/Aug/2026 10:11:18] "GET /api/v1/schedule-operations/daily-trip-assignments/?date=2026-08-05&mine=true HTTP/1.1" 403 117
[05/Aug/2026 10:11:18] "GET /api/v1/attendance/staff-profile/?staff_id_id=STC-658452dc8547430150 HTTP/1.1" 200 352


frontend:
flutter:  date: Wed, 05 Aug 2026 04:41:18 GMT
flutter:  vary: origin
flutter:  content-length: 114
flutter:  referrer-policy: same-origin
flutter:  cross-origin-opener-policy: same-origin
flutter:  content-type: application/json
flutter:  x-frame-options: DENY
flutter:  x-content-type-options: nosniff
flutter:  server: WSGIServer/0.2 CPython/3.14.3
flutter: Response Text:
flutter: {"detail":"Permission denied","module":"schedule-operations","resource":"VehicleBreakdown","action":"view"}
flutter: 
flutter: 
flutter: *** DioException ***:
flutter: uri: http://192.168.3.120:8000/api/v1/schedule-operations/staff-notifications/unread-count/
flutter: DioException [bad response]: This exception was thrown because the response has a status code of 403 and RequestOptions.validateStatus was configured to throw for this status code.
The status code of 403 has the following meaning: "Client error - the request contains bad syntax or cannot be fulfilled"
Read more about status codes at https://developer.mozilla.org/en-US/docs/Web/HTTP/Status
In order to resolve this exception you typically have either to verify and fix your request code or you have to fix the server code.
flutter: uri: http://192.168.3.120:8000/api/v1/schedule-operations/staff-notifications/unread-count/
flutter: statusCode: 403
flutter: headers:
flutter:  date: Wed, 05 Aug 2026 04:41:18 GMT
flutter:  vary: origin
flutter:  content-length: 115
flutter:  referrer-policy: same-origin
flutter:  cross-origin-opener-policy: same-origin
flutter:  content-type: application/json
flutter:  x-frame-options: DENY
flutter:  x-content-type-options: nosniff
flutter:  server: WSGIServer/0.2 CPython/3.14.3
flutter: Response Text:
flutter: {"detail":"Permission denied","module":"schedule-operations","resource":"StaffNotification","action":"view"}
flutter: 
flutter: 
flutter: *** DioException ***:
flutter: uri: http://192.168.3.120:8000/api/v1/schedule-operations/daily-trip-assignments/?date=2026-08-05&mine=true
flutter: DioException [bad response]: This exception was thrown because the response has a status code of 403 and RequestOptions.validateStatus was configured to throw for this status code.
The status code of 403 has the following meaning: "Client error - the request contains bad syntax or cannot be fulfilled"
Read more about status codes at https://developer.mozilla.org/en-US/docs/Web/HTTP/Status
In order to resolve this exception you typically have either to verify and fix your request code or you have to fix the server code.
flutter: uri: http://192.168.3.120:8000/api/v1/schedule-operations/daily-trip-assignments/?date=2026-08-05&mine=true
flutter: statusCode: 403
flutter: headers:
flutter:  date: Wed, 05 Aug 2026 04:41:18 GMT
flutter:  vary: origin
flutter:  content-length: 117
flutter:  referrer-policy: same-origin
flutter:  cross-origin-opener-policy: same-origin
flutter:  content-type: application/json
flutter:  x-frame-options: DENY
flutter:  x-content-type-options: nosniff
flutter:  server: WSGIServer/0.2 CPython/3.14.3
flutter: Response Text:
flutter: {"detail":"Permission denied","module":"schedule-operations","resource":"DailyTripAssignment","action":"view"}
flutter: 
flutter: 
flutter: *** Response ***
flutter: uri: http://192.168.3.120:8000/api/v1/attendance/staff-profile/?staff_id_id=STC-658452dc8547430150
flutter: statusCode: 200
flutter: headers:
flutter:  date: Wed, 05 Aug 2026 04:41:18 GMT
flutter:  vary: Accept, origin
flutter:  content-length: 352
flutter:  referrer-policy: same-origin
flutter:  cross-origin-opener-policy: same-origin
flutter:  content-type: application/json
flutter:  x-frame-options: DENY
flutter:  x-content-type-options: nosniff
flutter:  server: WSGIServer/0.2 CPython/3.14.3
flutter:  allow: GET, HEAD, OPTIONS
flutter: Response Text:
flutter: {"status":"success","data":{"company_id":"CMP-658452d8da9ca70020","company_name":"Blue Planet","project_id":"PROJ-658452d8db40431226","project_name":"Noida BP","staff_unique_id":"STC-658452dc8547430150","emp_id":"26139982","employee_name":"Supervisor User","department":null,"designation":null,"site_name":null,"doj":null,"photo":null,"personal":null}}
flutter: 


