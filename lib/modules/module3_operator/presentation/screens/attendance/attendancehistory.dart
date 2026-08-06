import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/env.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:table_calendar/table_calendar.dart';

const Color _kHistoryBg = Color(0xFFF6F7FB);
const Color _kHistorySurface = Colors.white;
const Color _kHistorySurfaceAlt = Color(0xFFF1F4FA);
const Color _kHistoryPrimary = Color(0xFF14224A);
const Color _kHistoryText = Color(0xFF0B1F3A);
const Color _kHistoryMuted = Color(0xFF6B7C93);
const Color _kHistoryBorder = Color(0xFFDCE3EF);

const Color _kStatusPresent = Color(0xFF1D4ED8);
const Color _kStatusPending = Color(0xFFD97706);
const Color _kStatusAbsent = Color(0xFFDC2626);
const Color _kStatusLeave = Color(0xFF7C3AED);
const Color _kStatusPermission = Color(0xFF0F8A58);

enum AttendanceStatusType {
  present,
  pendingOut,
  absent,
  leave,
  permission,
  none
}

class AttendanceDayRecord {
  const AttendanceDayRecord({
    required this.date,
    required this.statusLabel,
    required this.statusType,
    required this.inTime,
    required this.outTime,
    required this.checkInLatitude,
    required this.checkInLongitude,
    required this.checkOutLatitude,
    required this.checkOutLongitude,
    required this.checkInImage,
    required this.checkOutImage,
    required this.workedDuration,
    required this.checkInAt,
    required this.checkOutAt,
  });

  final DateTime date;
  final String statusLabel;
  final AttendanceStatusType statusType;
  final String inTime;
  final String outTime;
  final String checkInLatitude;
  final String checkInLongitude;
  final String checkOutLatitude;
  final String checkOutLongitude;
  final String checkInImage;
  final String checkOutImage;
  final String workedDuration;
  final String checkInAt;
  final String checkOutAt;

  bool get hasPunchData => inTime.isNotEmpty || outTime.isNotEmpty;

  bool get hasCoordinates {
    final inLat = double.tryParse(checkInLatitude) ?? 0;
    final inLng = double.tryParse(checkInLongitude) ?? 0;
    final outLat = double.tryParse(checkOutLatitude) ?? 0;
    final outLng = double.tryParse(checkOutLongitude) ?? 0;
    return (inLat != 0 || inLng != 0) || (outLat != 0 || outLng != 0);
  }

  static AttendanceDayRecord fromJson(Map<String, dynamic> json) {
    final parsedDate =
        DateFormat('dd/MMMM/yyyy', 'en_US').parseStrict('${json['date']}');
    final statusText = (json['day_status'] ?? '').toString().trim();
    return AttendanceDayRecord(
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
      statusLabel: statusText.isEmpty ? 'Absent' : statusText,
      statusType: _statusTypeForLabel(statusText),
      inTime: (json['in_time'] ?? '').toString(),
      outTime: (json['out_time'] ?? '').toString(),
      checkInLatitude: (json['in_latitude'] ?? '').toString(),
      checkInLongitude: (json['in_longitude'] ?? '').toString(),
      checkOutLatitude: (json['out_latitude'] ?? '').toString(),
      checkOutLongitude: (json['out_longitude'] ?? '').toString(),
      checkInImage:
          (json['in_image_path'] ?? '').toString().replaceAll('\\', '/'),
      checkOutImage:
          (json['out_image_path'] ?? '').toString().replaceAll('\\', '/'),
      workedDuration: (json['worked_duration'] ?? '').toString(),
      checkInAt: (json['check_in_at'] ?? '').toString(),
      checkOutAt: (json['check_out_at'] ?? '').toString(),
    );
  }
}

AttendanceStatusType _statusTypeForLabel(String raw) {
  final status = raw.trim().toLowerCase();
  switch (status) {
    case 'present':
      return AttendanceStatusType.present;
    case 'pending out':
      return AttendanceStatusType.pendingOut;
    case 'leave':
    case 'on leave':
      return AttendanceStatusType.leave;
    case 'permission':
      return AttendanceStatusType.permission;
    case 'absent':
      return AttendanceStatusType.absent;
    default:
      return AttendanceStatusType.none;
  }
}

Color _statusColor(AttendanceStatusType type) {
  switch (type) {
    case AttendanceStatusType.present:
      return _kStatusPresent;
    case AttendanceStatusType.pendingOut:
      return _kStatusPending;
    case AttendanceStatusType.absent:
      return _kStatusAbsent;
    case AttendanceStatusType.leave:
      return _kStatusLeave;
    case AttendanceStatusType.permission:
      return _kStatusPermission;
    case AttendanceStatusType.none:
      return _kHistoryBorder;
  }
}

String _statusLabel(AttendanceStatusType type) {
  switch (type) {
    case AttendanceStatusType.present:
      return 'Present';
    case AttendanceStatusType.pendingOut:
      return 'Pending Out';
    case AttendanceStatusType.absent:
      return 'Absent';
    case AttendanceStatusType.leave:
      return 'Leave';
    case AttendanceStatusType.permission:
      return 'Permission';
    case AttendanceStatusType.none:
      return 'No record';
  }
}

class AttendanceDetailPage extends StatefulWidget {
  const AttendanceDetailPage({
    super.key,
    required this.record,
    required this.selectedDate,
  });

  final AttendanceDayRecord record;
  final DateTime selectedDate;

  @override
  State<AttendanceDetailPage> createState() => _AttendanceDetailPageState();
}

class _AttendanceDetailPageState extends State<AttendanceDetailPage> {
  String _checkInLocation = 'Location unavailable';
  String _checkOutLocation = 'Location unavailable';
  String? _checkInResolved;
  String? _checkOutResolved;

  late final LatLng _checkInLatLng;
  late final LatLng _checkOutLatLng;
  late final LatLng _mapCenter;

  @override
  void initState() {
    super.initState();
    final inLat = double.tryParse(widget.record.checkInLatitude) ?? 0;
    final inLng = double.tryParse(widget.record.checkInLongitude) ?? 0;
    final outLat = double.tryParse(widget.record.checkOutLatitude) ?? 0;
    final outLng = double.tryParse(widget.record.checkOutLongitude) ?? 0;

    _checkInLatLng = LatLng(inLat, inLng);
    _checkOutLatLng = LatLng(outLat, outLng);
    _mapCenter = _resolveCenter(inLat, inLng, outLat, outLng);

    _resolveImages();
    _fetchLocation();
  }

  LatLng _resolveCenter(
      double inLat, double inLng, double outLat, double outLng) {
    if (inLat != 0 && outLat != 0) {
      return LatLng((inLat + outLat) / 2, (inLng + outLng) / 2);
    }
    if (inLat != 0 || inLng != 0) {
      return LatLng(inLat, inLng);
    }
    if (outLat != 0 || outLng != 0) {
      return LatLng(outLat, outLng);
    }
    return const LatLng(11.1271, 78.6569);
  }

  Future<void> _resolveImages() async {
    _checkInResolved =
        await _resolveAttendanceImage(widget.record.checkInImage);
    _checkOutResolved =
        await _resolveAttendanceImage(widget.record.checkOutImage);
    if (mounted) setState(() {});
  }

  Future<String?> _resolveAttendanceImage(String rawPath) async {
    if (rawPath.isEmpty) return null;
    final normalized = rawPath.replaceAll('\\', '/');
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return normalized;
    }
    if (normalized.startsWith('/media/')) {
      return '$kOperatorProfileBaseUrl$normalized';
    }
    if (normalized.startsWith('media/')) {
      return '$kOperatorProfileBaseUrl/$normalized';
    }
    return '$kOperatorProfileBaseUrl/$normalized';
  }

  Future<void> _fetchLocation() async {
    await _fetchSingleLocation(_checkInLatLng, isCheckIn: true);
    await _fetchSingleLocation(_checkOutLatLng, isCheckIn: false);
  }

  Future<void> _fetchSingleLocation(
    LatLng point, {
    required bool isCheckIn,
  }) async {
    if (point.latitude == 0.0 && point.longitude == 0.0) return;
    final url =
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}';
    try {
      final response = await http.get(Uri.parse(url));
      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final address = jsonData['address'] as Map<String, dynamic>?;
      final formatted = address != null
          ? '${address['suburb'] ?? ''} ${address['city'] ?? address['town'] ?? ''}'
              .trim()
          : (jsonData['display_name']?.toString() ?? 'Unknown');
      if (!mounted) return;
      setState(() {
        if (isCheckIn) {
          _checkInLocation = formatted.isEmpty ? 'Unknown' : formatted;
        } else {
          _checkOutLocation = formatted.isEmpty ? 'Unknown' : formatted;
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(widget.record.statusType);
    return Scaffold(
      backgroundColor: _kHistoryBg,
      appBar: AppBar(
        backgroundColor: _kHistoryPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Attendance details'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _HistorySurface(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _StatusDot(
                  color: statusColor,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('dd').format(widget.selectedDate),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        DateFormat('EEE')
                            .format(widget.selectedDate)
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('dd MMMM yyyy').format(widget.selectedDate),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _kHistoryText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.record.statusLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (widget.record.hasCoordinates)
            _HistorySurface(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 220,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: _mapCenter,
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom |
                            InteractiveFlag.drag |
                            InteractiveFlag.doubleTapZoom,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                      ),
                      MarkerLayer(
                        markers: [
                          if (_checkInLatLng.latitude != 0 ||
                              _checkInLatLng.longitude != 0)
                            Marker(
                              point: _checkInLatLng,
                              width: 44,
                              height: 44,
                              child: _MapPin(color: _kStatusPresent),
                            ),
                          if (_checkOutLatLng.latitude != 0 ||
                              _checkOutLatLng.longitude != 0)
                            Marker(
                              point: _checkOutLatLng,
                              width: 44,
                              height: 44,
                              child: _MapPin(color: _kStatusPending),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.record.hasCoordinates) const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HistoryMetricCard(
                  title: 'Clock In',
                  value: widget.record.inTime.isEmpty
                      ? '--:--'
                      : widget.record.inTime,
                  subtitle: _checkInLocation,
                  imageUrl: _checkInResolved,
                  accent: _kStatusPresent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HistoryMetricCard(
                  title: 'Clock Out',
                  value: widget.record.outTime.isEmpty
                      ? '--:--'
                      : widget.record.outTime,
                  subtitle: _checkOutLocation,
                  imageUrl: _checkOutResolved,
                  accent: _kStatusPending,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _HistorySurface(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _InfoPill(
                    label: 'Worked',
                    value: widget.record.workedDuration.isEmpty
                        ? '--:--:--'
                        : widget.record.workedDuration,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoPill(
                    label: 'Status',
                    value: widget.record.statusLabel,
                    accent: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AttendanceHistory extends StatefulWidget {
  const AttendanceHistory({
    super.key,
    required this.empId,
  });

  final String empId;

  @override
  State<AttendanceHistory> createState() => _AttendanceHistoryState();
}

class _AttendanceHistoryState extends State<AttendanceHistory> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isLoading = false;
  final Map<DateTime, AttendanceDayRecord> _attendanceMap = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = DateUtils.dateOnly(DateTime.now());
    _fetchAttendanceData();
  }

  DateTime _normalizeDate(DateTime date) => DateUtils.dateOnly(date);

  Future<void> _fetchAttendanceData() async {
    setState(() => _isLoading = true);
    try {
      final dio = await authorizedDio();
      final response = await dio.get(
        '${ApiConfig.attendanceBase}daily-attendance/',
        queryParameters: {
          'emp_id': widget.empId,
          'month': _focusedDay.month,
          'year': _focusedDay.year,
        },
      );
      final data = response.data;
      final parsed = <DateTime, AttendanceDayRecord>{};
      if (data is Map && data['records'] is List) {
        for (final item in (data['records'] as List).whereType<Map>()) {
          final record =
              AttendanceDayRecord.fromJson(Map<String, dynamic>.from(item));
          parsed[_normalizeDate(record.date)] = record;
        }
      }
      if (!mounted) return;
      setState(() {
        _attendanceMap
          ..clear()
          ..addAll(parsed);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  AttendanceDayRecord? _recordFor(DateTime day) =>
      _attendanceMap[_normalizeDate(day)];

  AttendanceStatusType _statusFor(DateTime day) {
    final normalized = _normalizeDate(day);
    final record = _recordFor(normalized);
    if (record != null) return record.statusType;

    final today = _normalizeDate(DateTime.now());
    if (normalized.isBefore(today)) return AttendanceStatusType.absent;
    return AttendanceStatusType.none;
  }

  String _labelForDay(DateTime day) {
    final record = _recordFor(day);
    if (record != null) return record.statusLabel;
    return _statusLabel(_statusFor(day));
  }

  int _daysInFocusedMonth() =>
      DateUtils.getDaysInMonth(_focusedDay.year, _focusedDay.month);

  int _countStatus(AttendanceStatusType type) {
    var count = 0;
    for (var i = 1; i <= _daysInFocusedMonth(); i++) {
      final day = DateTime(_focusedDay.year, _focusedDay.month, i);
      if (_statusFor(day) == type) count++;
    }
    return count;
  }

  List<AttendanceDayRecord> get _sortedRecords {
    final list = _attendanceMap.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  AttendanceDayRecord? get _selectedRecord =>
      _selectedDay == null ? null : _recordFor(_selectedDay!);

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = _normalizeDate(selectedDay);
      _focusedDay = focusedDay;
    });
  }

  void _onPageChanged(DateTime focusedDay) {
    setState(() {
      _focusedDay = focusedDay;
      final candidate = DateTime(focusedDay.year, focusedDay.month, 1);
      _selectedDay = _selectedDay != null &&
              _selectedDay!.year == focusedDay.year &&
              _selectedDay!.month == focusedDay.month
          ? _selectedDay
          : candidate;
    });
    _fetchAttendanceData();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedDay ?? _normalizeDate(DateTime.now());
    final selectedStatus = _statusFor(selected);
    final selectedRecord = _selectedRecord;

    return Scaffold(
      backgroundColor: _kHistoryBg,
      appBar: AppBar(
        backgroundColor: _kHistoryPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Attendance History'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _kHistoryPrimary))
          : RefreshIndicator(
              color: _kHistoryPrimary,
              onRefresh: _fetchAttendanceData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  _HistorySurface(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: const [
                        _LegendItem(color: _kStatusPresent, label: 'Present'),
                        _LegendItem(
                            color: _kStatusPending, label: 'Pending Out'),
                        _LegendItem(color: _kStatusAbsent, label: 'Absent'),
                        _LegendItem(color: _kStatusLeave, label: 'Leave'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryStat(
                          label: 'Present',
                          value:
                              '${_countStatus(AttendanceStatusType.present)}',
                          color: _kStatusPresent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SummaryStat(
                          label: 'Absent',
                          value: '${_countStatus(AttendanceStatusType.absent)}',
                          color: _kStatusAbsent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SummaryStat(
                          label: 'Leave',
                          value: '${_countStatus(AttendanceStatusType.leave)}',
                          color: _kStatusLeave,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _HistorySurface(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    child: TableCalendar<void>(
                      focusedDay: _focusedDay,
                      firstDay: DateTime(2020, 1, 1),
                      lastDay: DateTime(
                          DateTime.now().year, DateTime.now().month + 6, 0),
                      calendarFormat: CalendarFormat.month,
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDay, day),
                      headerStyle: HeaderStyle(
                        titleCentered: true,
                        formatButtonVisible: false,
                        titleTextStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _kHistoryText,
                        ),
                        leftChevronIcon: const Icon(Icons.chevron_left_rounded,
                            color: _kHistoryPrimary),
                        rightChevronIcon: const Icon(
                            Icons.chevron_right_rounded,
                            color: _kHistoryPrimary),
                      ),
                      daysOfWeekStyle: const DaysOfWeekStyle(
                        weekdayStyle: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _kHistoryMuted,
                        ),
                        weekendStyle: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _kHistoryMuted,
                        ),
                      ),
                      calendarStyle: const CalendarStyle(
                        outsideDaysVisible: false,
                        isTodayHighlighted: false,
                        cellMargin: EdgeInsets.all(5),
                      ),
                      calendarBuilders: CalendarBuilders(
                        defaultBuilder: (context, day, focusedDay) =>
                            _buildCalendarCell(day, false),
                        todayBuilder: (context, day, focusedDay) =>
                            _buildCalendarCell(day, false),
                        selectedBuilder: (context, day, focusedDay) =>
                            _buildCalendarCell(day, true),
                        outsideBuilder: (context, day, focusedDay) =>
                            const SizedBox.shrink(),
                      ),
                      onDaySelected: _onDaySelected,
                      onPageChanged: _onPageChanged,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SelectedDayCard(
                    date: selected,
                    statusType: selectedStatus,
                    statusLabel: _labelForDay(selected),
                    record: selectedRecord,
                    onOpenDetail: selectedRecord == null
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AttendanceDetailPage(
                                  record: selectedRecord,
                                  selectedDate: selected,
                                ),
                              ),
                            );
                          },
                  ),
                  const SizedBox(height: 14),
                  _HistorySurface(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recorded days this month',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _kHistoryText,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_sortedRecords.isEmpty)
                          const Text(
                            'No attendance records found for this month.',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _kHistoryMuted,
                            ),
                          )
                        else
                          ..._sortedRecords.map(
                            (record) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _MonthRecordRow(
                                record: record,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AttendanceDetailPage(
                                        record: record,
                                        selectedDate: record.date,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCalendarCell(DateTime day, bool selected) {
    final status = _statusFor(day);
    final color = _statusColor(status);
    final hasStatus = status != AttendanceStatusType.none;
    final isFuture =
        _normalizeDate(day).isAfter(_normalizeDate(DateTime.now()));

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              hasStatus ? color.withValues(alpha: selected ? 1 : 0.14) : null,
          border: Border.all(
            color: selected
                ? (hasStatus ? color : _kHistoryPrimary)
                : (hasStatus
                    ? color.withValues(alpha: 0.32)
                    : Colors.transparent),
            width: selected ? 1.8 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected
                ? (hasStatus ? Colors.white : _kHistoryPrimary)
                : isFuture
                    ? _kHistoryBorder
                    : hasStatus
                        ? color
                        : _kHistoryText,
          ),
        ),
      ),
    );
  }
}

class _SelectedDayCard extends StatelessWidget {
  const _SelectedDayCard({
    required this.date,
    required this.statusType,
    required this.statusLabel,
    required this.record,
    required this.onOpenDetail,
  });

  final DateTime date;
  final AttendanceStatusType statusType;
  final String statusLabel;
  final AttendanceDayRecord? record;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(statusType);
    final showDetail = record != null && record!.hasPunchData;

    return _HistorySurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusDot(
                color: color,
                size: 44,
                child: Text(
                  DateFormat('dd').format(date),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, dd MMM yyyy').format(date),
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: _kHistoryText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showDetail) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _InfoPill(
                    label: 'In',
                    value: record!.inTime.isEmpty ? '--:--' : record!.inTime,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoPill(
                    label: 'Out',
                    value: record!.outTime.isEmpty ? '--:--' : record!.outTime,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoPill(
                    label: 'Worked',
                    value: record!.workedDuration.isEmpty
                        ? '--:--:--'
                        : record!.workedDuration,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpenDetail,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kHistoryPrimary,
                  side: BorderSide(
                    color: _kHistoryPrimary.withValues(alpha: 0.24),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text(
                  'Open details',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              statusType == AttendanceStatusType.none
                  ? 'No attendance record on this day.'
                  : 'No punch details were recorded for this day.',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _kHistoryMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthRecordRow extends StatelessWidget {
  const _MonthRecordRow({
    required this.record,
    required this.onTap,
  });

  final AttendanceDayRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(record.statusType);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kHistorySurfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kHistoryBorder.withValues(alpha: 0.8)),
          ),
          child: Row(
            children: [
              _StatusDot(
                color: color,
                size: 42,
                child: Text(
                  DateFormat('dd').format(record.date),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEE, dd MMM yyyy').format(record.date),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: _kHistoryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.statusLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    record.inTime.isEmpty ? '--:--' : 'IN ${record.inTime}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _kHistoryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    record.outTime.isEmpty ? '--:--' : 'OUT ${record.outTime}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _kHistoryMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: _kHistoryText,
          ),
        ),
      ],
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _HistorySurface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: _kHistoryMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryMetricCard extends StatelessWidget {
  const _HistoryMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.imageUrl,
    required this.accent,
  });

  final String title;
  final String value;
  final String subtitle;
  final String? imageUrl;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _HistorySurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: accent.withValues(alpha: 0.12),
            backgroundImage: imageUrl != null && imageUrl!.isNotEmpty
                ? NetworkImage(imageUrl!)
                : const AssetImage('assets/images/default_user.png')
                    as ImageProvider,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: _kHistoryMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: _kHistoryMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.label,
    required this.value,
    this.accent = _kHistoryPrimary,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kHistorySurfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _kHistoryMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySurface extends StatelessWidget {
  const _HistorySurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _kHistorySurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kHistoryBorder.withValues(alpha: 0.85)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.color,
    required this.child,
    this.size = 52,
  });

  final Color color;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.24),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(
        Icons.place_rounded,
        color: Colors.white,
        size: 18,
      ),
    );
  }
}
