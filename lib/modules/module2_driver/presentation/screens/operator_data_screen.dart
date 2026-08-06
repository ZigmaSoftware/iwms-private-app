// operator_data_screen.dart
// 🚀 FIXED: Prevents UI from disappearing if API returns empty list
// ✅ Retains the 1-second Bluetooth delay you added
// ✅ Keeps Customer Details visible at all times

import 'dart:convert';
import 'dart:io';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/core/theme/app_colors.dart';
import 'package:iwms_private_app/core/theme/app_text_styles.dart';
import 'package:iwms_private_app/core/ui/app_flash.dart';
import 'package:iwms_private_app/router/route_observer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:iwms_private_app/shared/models/collection_history.dart';
import 'package:iwms_private_app/shared/services/collection_history_service.dart';
import 'package:iwms_private_app/modules/module3_operator/offline/pending_finalize_dao.dart';
import 'package:iwms_private_app/modules/module3_operator/offline/pending_finalize_record.dart';
import 'package:iwms_private_app/modules/module3_operator/offline/offline_sync_service.dart';
import 'package:iwms_private_app/modules/module3_operator/offline/pending_record.dart';
import 'package:iwms_private_app/modules/module3_operator/offline/pending_record_dao.dart';
import 'package:iwms_private_app/modules/module3_operator/services/bluetoothservices.dart';
import 'package:iwms_private_app/modules/module3_operator/services/generateunique_id.dart';
import 'package:iwms_private_app/modules/module3_operator/services/image_compress_service.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';
import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/data/repositories/auth_repository.dart';
import 'package:iwms_private_app/modules/module3_operator/utils/assignment_status_store.dart';

const BorderRadius _kOperatorCardRadius = BorderRadius.all(Radius.circular(18));

class OperatorDataScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String contactNo;
  final String latitude;
  final String longitude;
  final bool skipBluetoothInit;
  final String? assignmentId;

  const OperatorDataScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.contactNo,
    required this.latitude,
    required this.longitude,
    this.skipBluetoothInit = false,
    this.assignmentId,
  });

  @override
  State<OperatorDataScreen> createState() => _OperatorDataScreenState();
}

class _OperatorDataScreenState extends State<OperatorDataScreen>
    with WidgetsBindingObserver, RouteAware {
  final ImagePicker _picker = ImagePicker();
  late String screenUniqueId;
  final PendingFinalizeDao _finalizeDao = PendingFinalizeDao();
  final bluetooth = BluetoothService();
  bool connected = false;
  String latestWeight = "--";
  bool _isSubmitting = false;
  BluetoothConnection? _connection;
  // Classic Bluetooth SPP (flutter_bluetooth_serial) is Android-only. On iOS we
  // hide the scale UI and use manual entry. The scale modules (HC-05 / AEBT)
  // are not Apple-MFi, so iOS classic SPP is not possible.
  bool get _bluetoothSupported => Platform.isAndroid;
  bool _btConnecting = false;
  String? _connectedDeviceName;
  String? activeType; // currently selected waste type
  late final OfflineSyncService _syncService;
  final PendingRecordDao _pendingDao = PendingRecordDao();
  late final CollectionHistoryService _historyService;
  bool _collectionSubmitted = false;
  bool _routeObserverSubscribed = false;
  final ScrollController _scrollController = ScrollController();
  final Map<String, TextEditingController> _manualWeightControllers = {};
  final Map<String, GlobalKey> _wasteSectionKeys = {};
  final DateTime _sessionStartedAt = DateTime.now();
  bool _loadingContextDetails = false;
  String _customerAddress = '';
  String _collectionArea = '';
  String _scheduledCollectionTime = '';
  String _collectionDateLabel = '';

  List<Map<String, dynamic>> wasteTypes = [];
  Map<String, Map<String, dynamic>> _wasteData = {};

  bool _canApplyLiveWeight(String type) {
    final item = _wasteData[type];
    if (item == null) return false;
    return item['isAdded'] != true || item['finalWeight'] == null;
  }

  // ✅ Define defaults as final so we can reuse them safely
  final List<Map<String, dynamic>> defaultWasteTypes = [
    {"id": 1, "waste_type_name": "Wet"},
    {"id": 2, "waste_type_name": "Dry"},
    {"id": 3, "waste_type_name": "Mixed"},
  ];

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  /// Bearer token for the logged-in operator. The `/api/v1/waste/...`
  /// endpoints are auth-only on the backend, so every request must carry it.
  Future<Map<String, String>> _authHeaders() async {
    try {
      final user = await getIt<AuthRepository>().getAuthenticatedUser();
      final token = user?.authToken?.trim();
      if (token != null && token.isNotEmpty) {
        return {'Authorization': 'Bearer $token'};
      }
    } catch (_) {}
    return const {};
  }

  String _stringify(dynamic value) => value?.toString().trim() ?? '';

  String _readDisplayName(dynamic value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      return _stringify(
        map['name'] ??
            map['ward_name'] ??
            map['panchayat_name'] ??
            map['display_code'] ??
            map['title'] ??
            map['label'] ??
            map['unique_id'] ??
            map['id'],
      );
    }
    return _stringify(value);
  }

  /// First ward from the assignment's `wards_detail` list (the daily-trip-
  /// assignments endpoint carries ward as a list, not a nested single map).
  String _readWardName(dynamic wardsDetail) {
    if (wardsDetail is List && wardsDetail.isNotEmpty) {
      return _readDisplayName(wardsDetail.first);
    }
    return '';
  }

  String _normalizeAddress(Map<String, dynamic> map) {
    final direct = _stringify(map['address']);
    if (direct.isNotEmpty) return direct;
    final parts = [
      map['building_no'],
      map['street'],
      map['area'],
      map['landmark'],
      map['pincode'],
    ].map(_stringify).where((part) => part.isNotEmpty).toList();
    return parts.join(', ');
  }

  String _formatClock(String raw, {String? fallback}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return fallback ?? '—';
    try {
      final parsed = DateFormat('HH:mm:ss').parseStrict(trimmed);
      return DateFormat('hh:mm a').format(parsed);
    } catch (_) {}
    try {
      final parsed = DateFormat('HH:mm').parseStrict(trimmed);
      return DateFormat('hh:mm a').format(parsed);
    } catch (_) {}
    return trimmed;
  }

  String _formatCollectionDate(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return DateFormat('dd MMM yyyy').format(_sessionStartedAt);
    }
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(trimmed));
    } catch (_) {
      return trimmed;
    }
  }

  Future<void> _loadCollectionContext() async {
    _safeSetState(() => _loadingContextDetails = true);

    var address = '';
    var area = '';
    var scheduledTime = '';
    var collectionDate = DateFormat('dd MMM yyyy').format(_sessionStartedAt);

    try {
      final customerUri = Uri.parse('${ApiConfig.desktopBase}waste/customer/')
          .replace(queryParameters: {'unique_id': widget.customerId});
      final customerResp = await http
          .get(customerUri, headers: await _authHeaders())
          .timeout(const Duration(seconds: 8));
      if (customerResp.statusCode == 200) {
        final payload = jsonDecode(customerResp.body);
        if (payload is Map && payload['status'] == 'success') {
          final data = payload['data'];
          if (data is Map) {
            final customer = Map<String, dynamic>.from(data);
            final fetchedAddress = _normalizeAddress(customer);
            if (fetchedAddress.isNotEmpty) address = fetchedAddress;
          }
        }
      }
    } catch (_) {}

    final assignmentId = widget.assignmentId?.trim() ?? '';
    if (assignmentId.isNotEmpty) {
      try {
        final dio = await authorizedDio();
        final response =
            await dio.get('${ApiConfig.assignments}$assignmentId/');
        final data = response.data;
        if (data is Map) {
          final assignmentMap = Map<String, dynamic>.from(data);
          area = _readWardName(assignmentMap['wards_detail']);
          area = area.isNotEmpty
              ? area
              : _readDisplayName(assignmentMap['ward']);
          area = area.isNotEmpty
              ? area
              : _readDisplayName(assignmentMap['panchayat']);
          area = area.isNotEmpty
              ? area
              : _stringify(
                  assignmentMap['ward_name'] ??
                      assignmentMap['panchayat_name'] ??
                      assignmentMap['area_name'],
                );

          scheduledTime = _formatClock(
            _stringify(assignmentMap['scheduled_time']),
            fallback: DateFormat('hh:mm a').format(_sessionStartedAt),
          );
          collectionDate =
              _formatCollectionDate(_stringify(assignmentMap['trip_date']));
        }
      } catch (_) {}
    }

    _safeSetState(() {
      _customerAddress = address;
      _collectionArea = area;
      _scheduledCollectionTime = scheduledTime;
      _collectionDateLabel = collectionDate;
      _loadingContextDetails = false;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    screenUniqueId = UniqueIdService.generateScreenUniqueId();
    _wasteData.clear();

    latestWeight = "--";
    _historyService = getIt<CollectionHistoryService>();

    // ✅ Initialize with defaults immediately so UI is never empty
    _applyWasteTypes(defaultWasteTypes);

    if (_bluetoothSupported && !widget.skipBluetoothInit) {
      // 🔁 Bluetooth adapter re-init with 1s Delay (Android only)
      Future.delayed(const Duration(seconds: 1), () async {
        if (!await _ensureBluetoothPermissions()) return;
        debugPrint("♻️ Reinitializing Bluetooth adapter...");
        await FlutterBluetoothSerial.instance.cancelDiscovery();
        final isEnabled =
            await FlutterBluetoothSerial.instance.isEnabled ?? false;
        if (!isEnabled) {
          try {
            await FlutterBluetoothSerial.instance.requestEnable();
          } catch (e) {
            debugPrint("⚠️ Unable to prompt for Bluetooth enable: $e");
          }
        }
        await _resetBluetooth();
        await _initBluetooth();
      });
    }

    _syncService = OfflineSyncService(
      recordDao: _pendingDao,
      finalizeDao: _finalizeDao,
      baseUrl: '${ApiConfig.desktopBase}waste',
    )..start();

    // Fetch latest types from API
    _fetchWasteTypes();
    _loadCollectionContext();
  }

  // ==================== FETCH WASTE TYPES ====================
  Future<void> _fetchWasteTypes() async {
    // Start with defaults. We only overwrite if API gives valid NON-EMPTY data.
    List<Map<String, dynamic>> resolvedTypes = defaultWasteTypes;

    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.desktopBase}waste/get-waste-types/',
            ).replace(queryParameters: {'customer_id': widget.customerId}),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 5));

      final data = json.decode(response.body);

      if (data['status'] == 'success' && data['data'] != null) {
        final fetched = List<Map<String, dynamic>>.from(data['data']);

        // ✅ CRITICAL FIX: Only use API data if it's NOT empty.
        // If API returns [], we keep the defaults.
        if (fetched.isNotEmpty) {
          resolvedTypes = fetched;
        } else {
          debugPrint(
              '⚠️ API returned empty waste types list. Keeping defaults.');
        }
      }
    } catch (e) {
      debugPrint('⚠ Waste type API failed, using fallback defaults: $e');
      // resolvedTypes remains defaultWasteTypes
    }

    if (!mounted) return;
    _applyWasteTypes(resolvedTypes);
    _safeSetState(() {});

    // Load offline data after the first paint to keep the screen responsive.
    Future.microtask(_loadOfflineForScreen);
  }

  Future<void> _loadOfflineForScreen() async {
    debugPrint("🔄 Loading offline records for screen: $screenUniqueId");

    final offlineRecords = await _pendingDao.getByScreen(screenUniqueId);

    // nothing to load → just refresh UI
    if (offlineRecords.isEmpty) {
      _safeSetState(() {});
      return;
    }

    for (var r in offlineRecords) {
      // only records for this screen
      if (r.screenId != screenUniqueId) continue;

      final type = wasteTypes.firstWhere(
        (w) => w['id'].toString() == r.wasteTypeId,
        orElse: () => {},
      );
      if (type.isEmpty) continue;

      final typeKey = type['waste_type_name'].toString().trim().toLowerCase();

      if (!_wasteData.containsKey(typeKey)) continue;

      // Build updated map
      final updated = Map<String, dynamic>.from(_wasteData[typeKey]!);

      // UID must never be null for UI logic
      final safeUid = r.uniqueId;

      updated['isAdded'] = true;
      updated['unique_id'] = safeUid;

      updated['weight'] = r.weight;
      updated['finalWeight'] = r.weight; // always override stale values
      updated['image'] = File(r.imagePath);

      _wasteData = {..._wasteData, typeKey: updated};
      _syncManualWeightController(typeKey, r.weight.toString());

      debugPrint(
          "📌 Loaded offline → $typeKey | weight=${r.weight} | uid=$safeUid");
    }

    _safeSetState(() {});
  }

  void _syncManualWeightController(String type, String? value) {
    final controller = _manualWeightControllers[type];
    if (controller == null) return;
    final text = value?.toString() ?? '';
    if (controller.text != text) {
      controller.text = text;
    }
  }

  String _weightTextFor(String type) {
    final item = _wasteData[type];
    if (item == null) return '';
    final value = item['finalWeight'] ?? item['weight'];
    return value == '--' || value == null ? '' : value.toString();
  }

  void _updateManualWeight(String type, String raw) {
    final trimmed = raw.trim();
    if (!_wasteData.containsKey(type)) return;
    final updated = Map<String, dynamic>.from(_wasteData[type]!);
    updated['weight'] = trimmed.isEmpty ? '--' : trimmed;
    updated['finalWeight'] = trimmed.isEmpty ? null : trimmed;
    _wasteData = {
      ..._wasteData,
      type: updated,
    };
    if (trimmed.isNotEmpty) {
      latestWeight = trimmed;
    }
  }

  List<double> _quickWeightsFor(String type) {
    if (type.contains('wet') || type.contains('dry')) {
      return const [10, 25, 50];
    }
    return const [5, 10, 25];
  }

  String _formatQuickWeight(double value) {
    return value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
  }

  void _setQuickWeight(String type, double value) {
    final text = _formatQuickWeight(value);
    _syncManualWeightController(type, text);
    setState(() => _updateManualWeight(type, text));
  }

  void _startEditingAddedWeight(String type) {
    if (!_wasteData.containsKey(type)) return;
    final current = _wasteData[type]!;
    if (current['isAdded'] != true) return;

    final updated = Map<String, dynamic>.from(current);
    updated['finalWeight'] = null;
    if (latestWeight != '--') {
      updated['weight'] = latestWeight;
    }

    _wasteData = {
      ..._wasteData,
      type: updated,
    };
    activeType = type;
    _syncManualWeightController(type, _weightTextFor(type));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_routeObserverSubscribed && route is PageRoute) {
      routeObserver.subscribe(this, route);
      _routeObserverSubscribed = true;
    }
  }

  Future<void> _resetBluetooth() async {
    try {
      if (_connection != null) {
        await _connection!.close();
        _connection = null;
        connected = false;
        _connectedDeviceName = null;
        debugPrint("🔌 Bluetooth connection reset successfully");
      }
    } catch (e) {
      debugPrint("⚠️ Error while resetting Bluetooth: $e");
    }
  }

  @override
  void dispose() {
    if (_routeObserverSubscribed) {
      routeObserver.unsubscribe(this);
      _routeObserverSubscribed = false;
    }
    WidgetsBinding.instance.removeObserver(this);
    try {
      _connection?.dispose();
      connected = false;
    } catch (_) {}
    _scrollController.dispose();
    for (final controller in _manualWeightControllers.values) {
      controller.dispose();
    }
    _syncService.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    debugPrint("🔄 Returned → reconnecting");
    if (_bluetoothSupported && !connected) {
      _reconnectBluetoothWithRetry();
    }
  }

  Future<void> _reconnectBluetoothWithRetry({int retries = 3}) async {
    for (int i = 0; i < retries; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        await _resetBluetooth();
        await _initBluetooth();
        if (connected) {
          debugPrint("✅ Reconnected on attempt ${i + 1}");
          return;
        }
      } catch (e) {
        debugPrint("⚠️ Retry ${i + 1} failed: $e");
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_bluetoothSupported &&
        state == AppLifecycleState.resumed &&
        !connected) {
      _initBluetooth();
    }
  }

  /// Orders waste types so household collection always shows the two primary
  /// segregated streams first — Wet, then Dry — followed by every other type
  /// in its original (API) order. Uses a stable sort via the original index so
  /// the "others" keep their relative order.
  List<Map<String, dynamic>> _prioritizeWasteTypes(
    List<Map<String, dynamic>> types,
  ) {
    int rank(Map<String, dynamic> t) {
      final name = (t['waste_type_name'] ?? '').toString().toLowerCase();
      if (name.contains('wet')) return 0;
      if (name.contains('dry')) return 1;
      return 2;
    }

    final indexed = types.asMap().entries.toList()
      ..sort((a, b) {
        final byRank = rank(a.value).compareTo(rank(b.value));
        if (byRank != 0) return byRank;
        return a.key.compareTo(b.key); // preserve original order within a rank
      });
    return indexed.map((e) => e.value).toList();
  }

  void _applyWasteTypes(List<Map<String, dynamic>> types) {
    wasteTypes = _prioritizeWasteTypes(types);
    _wasteData = {
      for (var item in wasteTypes)
        item['waste_type_name'].toString().trim().toLowerCase(): {
          'waste_type_id': item['id'],
          'label': item['waste_type_name'],
          'unique_id': null,
          'image': null,
          'weight': '--',
          'finalWeight': null,
          'isAdded': false,
        }
    };

    for (final controller in _manualWeightControllers.values) {
      controller.dispose();
    }
    _manualWeightControllers.clear();
    _wasteSectionKeys.clear();
    for (final type in _wasteData.keys) {
      _manualWeightControllers[type] =
          TextEditingController(text: _weightTextFor(type));
      _wasteSectionKeys[type] = GlobalKey();
    }
  }

  Future<void> _fetchWasteRecord(String type) async {
    try {
      final uri = Uri.parse('${ApiConfig.desktopBase}waste/get-latest-waste/');
      final response =
          await http.post(uri, headers: await _authHeaders(), body: {
        'screen_unique_id': screenUniqueId,
        'customer_id': widget.customerId,
        'waste_type': _wasteData[type]!['waste_type_id'].toString(),
        'waste_type_id': _wasteData[type]!['waste_type_id'].toString(),
      });

      final data = json.decode(response.body);
      if (data['status'] == 'success' && data['data'] != null) {
        final record = data['data'];

        _safeSetState(() {
          final updated = Map<String, dynamic>.from(_wasteData[type]!);
          updated['unique_id'] = record['unique_id'];
          updated['waste_type_id'] = _wasteData[type]!['waste_type_id'];
          updated['weight'] = record['weight'] ?? '--';
          updated['finalWeight'] = record['weight'] ?? '--';
          updated['isAdded'] = true;

          _wasteData = {..._wasteData, type: updated};
          _syncManualWeightController(type, updated['weight']?.toString());
        });

        debugPrint('✅ Backend weight for $type: ${record['weight']}');
      } else {
        debugPrint('⚠️ No record found for $type: ${data['message']}');
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching record for $type: $e');
    }
  }

  Future<void> _handleAdd(String type) async {
    final data = _wasteData[type]!;
    final image = data['image'] as File?;
    final wasteTypeId = data['waste_type_id']?.toString() ?? '';

    if (image == null) {
      AppFlash.warning(context, 'Capture image for $type first');
      return;
    }

    if (wasteTypeId.isEmpty || wasteTypeId == 'null') {
      AppFlash.warning(context, 'Missing waste type for $type');
      return;
    }

    final weightValue = data['weight']?.toString() ?? '--';
    if (weightValue.isEmpty || weightValue == "--") {
      AppFlash.warning(context, 'Please ensure weight is recorded for $type');
      return;
    }

    final weight = weightValue;
    final isUpdate = data['isAdded'] == true;
    final uniqueId = data['unique_id']?.toString();

    _safeSetState(() => _isSubmitting = true);

    try {
      final uri = Uri.parse(
        isUpdate
            ? '${ApiConfig.desktopBase}waste/update-waste-sub/'
            : '${ApiConfig.desktopBase}waste/insert-waste-sub/',
      );

      debugPrint(
          "▶️ _handleAdd($type) → isUpdate=$isUpdate, unique_id=$uniqueId");

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(await _authHeaders())
        ..fields['screen_unique_id'] = screenUniqueId
        ..fields['customer_id'] = widget.customerId
        ..fields['waste_type'] = wasteTypeId
        ..fields['waste_type_id'] = wasteTypeId
        ..fields['weight'] = weight
        ..fields['latitude'] = widget.latitude
        ..fields['longitude'] = widget.longitude;

      if (isUpdate && uniqueId != null) {
        request.fields['unique_id'] = uniqueId;
      }

      request.files.add(await http.MultipartFile.fromPath('image', image.path));

      final streamed = await request.send();

      if (streamed.statusCode >= 400) {
        throw Exception("Server error ${streamed.statusCode}");
      }

      final response = await http.Response.fromStream(streamed);
      dynamic result;
      try {
        result = json.decode(response.body);
      } catch (_) {
        throw Exception("Invalid JSON from backend");
      }

      if (result['status'] != 'success') {
        throw Exception(result['message'] ?? "Unknown server error");
      }

      final backendUnique = result['unique_id']?.toString();

      _safeSetState(() {
        final updated = Map<String, dynamic>.from(data);
        updated['isAdded'] = true;
        updated['finalWeight'] = weight;

        if (backendUnique != null) {
          updated['unique_id'] = backendUnique;
        }

        _wasteData[type] = updated;
        if (activeType == type) {
          activeType = null;
        }
      });

      await _fetchWasteRecord(type);

      if (!mounted) return;
      AppFlash.success(
        context,
        isUpdate ? "$type updated successfully" : "$type added successfully",
      );

      return;
    } catch (err) {
      debugPrint("⚠️ _handleAdd offline mode triggered: $err");

      final record = PendingRecord(
        screenId: screenUniqueId,
        customerId: widget.customerId,
        customerName: widget.customerName,
        contactNo: widget.contactNo,
        wasteTypeId: data['waste_type_id'].toString(),
        weight: weight,
        latitude: double.tryParse(widget.latitude),
        longitude: double.tryParse(widget.longitude),
        imagePath: image.path,
        isUpdate: isUpdate,
        uniqueId: uniqueId ?? "uid_${DateTime.now().millisecondsSinceEpoch}",
      );

      final existing = await _pendingDao.findByTypeAndScreen(
        wasteTypeId: data['waste_type_id'].toString(),
        screenId: screenUniqueId,
      );

      if (existing != null) {
        await _pendingDao.update(
          existing.copyWith(
            weight: weight,
            imagePath: image.path,
            isUpdate: true,
            uniqueId: existing.uniqueId,
          ),
        );
      } else {
        await _pendingDao.insert(record);
      }

      await _loadOfflineForScreen();
      if (activeType == type) {
        _safeSetState(() => activeType = null);
      }

      if (!mounted) return;
      AppFlash.info(context, "$type saved offline — will sync automatically");
    } finally {
      _safeSetState(() => _isSubmitting = false);
    }
  }

  Future<void> _resetUI() async {
    _safeSetState(() {
      latestWeight = "--";
      activeType = null;
      screenUniqueId = UniqueIdService.generateScreenUniqueId();

      _wasteData = {
        for (var item in wasteTypes)
          item['waste_type_name'].toString().trim().toLowerCase(): {
            'waste_type_id': item['id'],
            'label': item['waste_type_name'],
            'unique_id': null,
            'image': null,
            'weight': '--',
            'finalWeight': null,
            'isAdded': false,
          }
      };
    });
    debugPrint("🔄 UI reset completed. Ready for next customer.");
  }

  // ==================== SUBMIT MAIN FORM ====================
  Future<void> _submitForm() async {
    _safeSetState(() => _isSubmitting = true);

    final totalWeight = _calculateTotalWeight();
    final summary = _buildSummarySnapshot();
    Future<void> syncLog(String status) async {
      if (!ApiConfig.legacyRoleAssignEnabled) return;
      if (widget.assignmentId == null || widget.assignmentId!.trim().isEmpty) {
        return;
      }
      try {
        final dio = await authorizedDio();
        final latitude = widget.latitude.trim();
        final longitude = widget.longitude.trim();
        await dio.post(
          ApiConfig.assignmentCustomerStatuses,
          data: {
            'assignment': widget.assignmentId,
            'customer': widget.customerId,
            'status': status == 'collection_completed' ? 'collected' : status,
            if (latitude.isNotEmpty) 'latitude': latitude,
            if (longitude.isNotEmpty) 'longitude': longitude,
          },
        );
      } catch (_) {
        // best-effort; ignore
      }
    }

    try {
      final uri = Uri.parse('${ApiConfig.desktopBase}waste/finalize-waste/');

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(await _authHeaders())
        ..fields['screen_unique_id'] = screenUniqueId
        ..fields['customer_id'] = widget.customerId
        ..fields['entry_type'] = 'app'
        // Scope the collection to this trip so the backend marks the correct
        // household stop collected (a driver may have a bin + a household trip).
        ..fields['assignment_id'] = widget.assignmentId ?? ''
        ..fields['total_waste_collected'] = totalWeight.toString();

      final response = await request.send();
      final result =
          json.decode((await http.Response.fromStream(response)).body);

      if (result['status'] != 'success') {
        // The server ANSWERED and refused (e.g. "No waste records found" when
        // nothing was saved). That is a business rejection, not a connectivity
        // problem — queueing it as an offline finalize would mark the household
        // collected on a request the server has already rejected. Surface it and
        // leave the visit open.
        if (!mounted) return;
        AppFlash.warning(
          context,
          result['message']?.toString() ?? 'Could not submit this collection',
        );
        return;
      }

      await _recordCollectionHistory(totalWeight);
      _collectionSubmitted = true;
      if (widget.assignmentId != null &&
          widget.assignmentId!.trim().isNotEmpty) {
        await AssignmentStatusStore.setStatusForAssignment(
          widget.assignmentId!,
          widget.customerId,
          'collected',
        );
        await syncLog('collection_completed');
        await _maybeCompleteAssignmentFromStore(widget.assignmentId!);
      }
      await _showSuccessSheet(totalWeight, summary);
      _resetUI();
      // Fetch types again just in case, but keep defaults if fail
      _fetchWasteTypes();
    } catch (e) {
      debugPrint("⚠️ Finalize failed, storing offline: $e");

      final pendingFinalize = PendingFinalizeRecord(
        screenId: screenUniqueId,
        customerId: widget.customerId,
        totalWeight: _calculateTotalWeight(),
        entryType: "app",
      );

      await _finalizeDao.insert(pendingFinalize);
      _collectionSubmitted = true;

      try {
        if (await _syncService.hasInternet()) {
          await _syncService.syncAll();
        }
      } catch (err) {
        debugPrint("⚠️ Sync attempt failed: $err");
      }

      await _recordCollectionHistory(totalWeight);
      if (widget.assignmentId != null &&
          widget.assignmentId!.trim().isNotEmpty) {
        await AssignmentStatusStore.setStatusForAssignment(
          widget.assignmentId!,
          widget.customerId,
          'collected',
        );
        await syncLog('collection_completed');
        await _maybeCompleteAssignmentFromStore(widget.assignmentId!);
      }
      await _showSuccessSheet(totalWeight, summary, offline: true);
      _resetUI();
      _fetchWasteTypes();
    } finally {
      _safeSetState(() => _isSubmitting = false);
    }
  }

  double _calculateTotalWeight() {
    return _wasteData.values.fold<double>(0, (sum, e) {
      final w = double.tryParse(
              e['finalWeight']?.toString() ?? e['weight'].toString()) ??
          0;
      return sum + w;
    });
  }

  Future<void> _maybeCompleteAssignmentFromStore(String assignmentId) async {
    final trimmedId = assignmentId.trim();
    if (trimmedId.isEmpty) return;
    final alreadyCompleted =
        await AssignmentStatusStore.isAssignmentCompleted(trimmedId);
    if (alreadyCompleted) return;

    final customerIds = await _fetchAssignmentCustomerIds(trimmedId);
    if (customerIds.isEmpty) return;

    final statuses =
        await AssignmentStatusStore.getStatusesFor(trimmedId, customerIds);
    final allDone = customerIds.every((id) {
      final status = statuses[id]?.toLowerCase();
      return status == 'collected' || status == 'skipped';
    });
    if (!allDone) return;

    await AssignmentStatusStore.setAssignmentCompleted(trimmedId);
    await _markAssignmentComplete(trimmedId);
  }

  Future<List<String>> _fetchAssignmentCustomerIds(String assignmentId) async {
    if (!ApiConfig.legacyRoleAssignEnabled) return [];

    try {
      final dio = await authorizedDio();
      final assignmentResp =
          await dio.get('${ApiConfig.assignments}$assignmentId/');
      final assignmentData = assignmentResp.data;
      String wardId = '';
      if (assignmentData is Map) {
        wardId = (assignmentData['ward'] ?? assignmentData['ward_id'] ?? '')
            .toString();
      }
      if (wardId.trim().isEmpty) return [];

      List<dynamic> list = [];

      Future<void> fetchWithParam(String paramKey) async {
        final resp = await dio.get(
          ApiConfig.customerList,
          queryParameters: {paramKey: wardId},
        );
        final decoded = resp.data;
        list = decoded is List
            ? decoded
            : (decoded is Map
                ? (decoded['results'] ?? decoded['data'] ?? [])
                : []);
      }

      try {
        await fetchWithParam('ward');
        if (list.isEmpty) {
          await fetchWithParam('ward_id');
        }
      } catch (_) {
        // ignore
      }

      final ids = <String>[];
      for (final entry in list) {
        if (entry is! Map) continue;
        final id =
            (entry['unique_id'] ?? entry['customer_id'] ?? '').toString();
        if (id.isEmpty) continue;
        ids.add(id);
      }
      return ids;
    } catch (_) {
      return [];
    }
  }

  Future<void> _markAssignmentComplete(String assignmentId) async {
    if (!ApiConfig.legacyRoleAssignEnabled) return;

    try {
      final dio = await authorizedDio();
      await dio.post('${ApiConfig.assignments}$assignmentId/complete/');
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _recordCollectionHistory(double totalWeight) async {
    final sections = _wasteData.entries
        .map((entry) {
          final resolvedWeight = _weightFromEntry(entry.value);
          if (resolvedWeight <= 0) return null;
          final label =
              entry.value['label']?.toString() ?? entry.key.toUpperCase();
          final image = entry.value['image'] as File?;
          return CollectionHistorySection(
            type: label,
            weight: resolvedWeight.toStringAsFixed(2),
            imagePath: image?.path,
          );
        })
        .whereType<CollectionHistorySection>()
        .toList();

    if (sections.isEmpty) return;

    final entry = CollectionHistoryEntry(
      customerId: widget.customerId,
      customerName: widget.customerName,
      collectedAt: DateTime.now(),
      sections: sections,
      totalWeight: totalWeight,
    );

    await _historyService.addEntry(entry);
  }

  double _weightFromEntry(Map<String, dynamic> entry) {
    final source = entry['finalWeight'] ?? entry['weight'];
    if (source == null) return 0;
    return double.tryParse(source.toString()) ?? 0;
  }

  Map<String, double> _buildSummarySnapshot() {
    final Map<String, double> totals = {'wet': 0, 'dry': 0, 'mixed': 0};

    _wasteData.forEach((key, value) {
      final weight = _weightFromEntry(value);

      if (key.contains('wet')) {
        totals['wet'] = (totals['wet'] ?? 0) + weight;
      } else if (key.contains('dry')) {
        totals['dry'] = (totals['dry'] ?? 0) + weight;
      } else {
        totals['mixed'] = (totals['mixed'] ?? 0) + weight;
      }
    });

    return totals;
  }

  Future<void> _showSuccessSheet(
    double totalWeight,
    Map<String, double> summary, {
    bool offline = false,
  }) async {
    if (!mounted) return;
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      showDragHandle: true,
      isScrollControlled: true, // Allow full height
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      offline ? Icons.cloud_off : Icons.check_circle,
                      color: offline ? Colors.orange : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      offline ? 'Saved offline' : 'Collection recorded',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Total: ${totalWeight.toStringAsFixed(2)} kg',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _pill('Wet', summary['wet'] ?? 0, Colors.blue),
                    _pill('Dry', summary['dry'] ?? 0, Colors.green),
                    _pill('Mixed', summary['mixed'] ?? 0, Colors.orange),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await WidgetsBinding.instance.endOfFrame;
                          await Future<void>.delayed(
                            const Duration(milliseconds: 120),
                          );
                          if (!mounted) return;
                          Navigator.of(context).pop(true);
                        },
                        icon: const Icon(Icons.home),
                        label: const Text('Back to home'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pill(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        '$label ${value.toStringAsFixed(2)} kg',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildCollectionHeader() {
    final dateLabel = _collectionDateLabel.isNotEmpty
        ? _collectionDateLabel
        : DateFormat('dd MMM yyyy').format(_sessionStartedAt);
    final timeLabel = _scheduledCollectionTime.isNotEmpty
        ? _scheduledCollectionTime
        : DateFormat('hh:mm a').format(_sessionStartedAt);
    // Date + time were two separate pills; a collection only ever has one
    // schedule, so one pill says as much in half the space. The customer's
    // phone number is deliberately never shown here (or anywhere else in the
    // driver app) — the internal assignment reference was dropped too, as
    // pure noise the driver never acts on.
    final scheduleLabel = '$dateLabel · $timeLabel';
    final details = <Widget>[
      if (_collectionArea.isNotEmpty)
        _detailPill(Icons.location_city_outlined, 'Ward', _collectionArea),
      _detailPill(Icons.badge_outlined, 'Customer ID', widget.customerId),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CaptainTheme.surface,
        borderRadius: CaptainTheme.cardRadius,
        border: Border.all(color: CaptainTheme.hairline),
        boxShadow: CaptainTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: CaptainTheme.accentSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.home_work_outlined,
                  color: CaptainTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.customerName.trim().isEmpty
                          ? 'Scanned household'
                          : widget.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.heading2.copyWith(
                        color: CaptainTheme.strongText,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _loadingContextDetails
                          ? 'Loading assignment details...'
                          : 'Household collection details',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: CaptainTheme.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _detailPill(Icons.event_outlined, 'Schedule', scheduleLabel,
              fullWidth: true),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: details,
          ),
          if (_customerAddress.isNotEmpty) ...[
            const SizedBox(height: 8),
            _detailPill(
              Icons.home_outlined,
              'Address',
              _customerAddress,
              fullWidth: true,
            ),
          ],
          // Only rendered while a scale is actually connecting/connected —
          // silent the rest of the time, so it never costs space it isn't
          // earning.
          if (_btConnecting || connected) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: CaptainTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: _buildBluetoothBar(inverted: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailPill(
    IconData icon,
    String label,
    String value, {
    bool fullWidth = false,
  }) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: CaptainTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: CaptainTheme.accent),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: CaptainTheme.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.trim().isEmpty ? '—' : value,
                  maxLines: fullWidth ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: CaptainTheme.strongText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (fullWidth) return SizedBox(width: double.infinity, child: card);
    return SizedBox(width: 164, child: card);
  }

  Widget _buildWasteSectionHeader() {
    final addedCount =
        _wasteData.values.where((item) => item['isAdded'] == true).length;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Waste Items',
                style: AppTextStyles.heading2.copyWith(
                  color: CaptainTheme.strongText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Record weight and photo for each stream.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: CaptainTheme.mutedText,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: CaptainTheme.accentSoft,
            borderRadius: CaptainTheme.chipRadius,
          ),
          child: Text(
            '$addedCount/${wasteTypes.length} saved',
            style: AppTextStyles.bodyMedium.copyWith(
              color: CaptainTheme.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  /// Bluetooth scale status + connect control. Android only — on iOS the scale
  /// uses classic SPP which Apple does not allow, so operators enter weight
  /// manually (the manual field stays available on every platform).
  Widget _buildBluetoothBarContent({required bool inverted}) {
    if (!_bluetoothSupported) {
      return Row(
        children: [
          Icon(
            Icons.edit,
            size: 18,
            color: inverted
                ? Colors.white.withValues(alpha: 0.82)
                : CaptainTheme.mutedText,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Enter weight manually below.',
              style: TextStyle(
                color: inverted
                    ? Colors.white.withValues(alpha: 0.82)
                    : CaptainTheme.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    }

    final Color statusColor = connected
        ? (inverted ? const Color(0xFF7EF59F) : CaptainTheme.success)
        : (_btConnecting
            ? CaptainTheme.warning
            : (inverted ? const Color(0xFFFFB4B4) : CaptainTheme.danger));
    final String statusText = connected
        ? 'Scale connected${_connectedDeviceName != null ? ' · $_connectedDeviceName' : ''}'
        : (_btConnecting ? 'Connecting...' : 'Scale not connected');

    return Row(
      children: [
        Icon(
          connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
          size: 18,
          color: statusColor,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            statusText,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
          ),
        ),
        if (_btConnecting)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: inverted ? Colors.white : CaptainTheme.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: connected ? _disconnectScale : _connectScalePressed,
            icon: Icon(connected ? Icons.link_off : Icons.bluetooth_searching,
                size: 18),
            label: Text(connected ? 'Disconnect' : 'Connect'),
          ),
      ],
    );
  }

  Widget _buildBluetoothBar({bool inverted = false}) {
    return _buildBluetoothBarContent(inverted: inverted);
  }

  /// Manual Connect tap: ensure adapter on, then auto-match or show picker.
  Future<void> _connectScalePressed() async {
    if (!_bluetoothSupported) return;
    if (!await _ensureBluetoothPermissions()) return;
    try {
      await FlutterBluetoothSerial.instance.cancelDiscovery();
      final isEnabled =
          await FlutterBluetoothSerial.instance.isEnabled ?? false;
      if (!isEnabled) {
        await FlutterBluetoothSerial.instance.requestEnable();
      }
    } catch (e) {
      debugPrint("⚠️ Adapter enable skipped: $e");
    }
    await _resetBluetooth();
    await _initBluetooth();
  }

  Future<void> _disconnectScale() async {
    await _resetBluetooth();
    _safeSetState(() {
      connected = false;
      _connectedDeviceName = null;
    });
  }

  Color _wasteAccent(String type) {
    if (type.contains('wet')) return CaptainTheme.success;
    if (type.contains('dry')) return CaptainTheme.info;
    return CaptainTheme.warning;
  }

  IconData _wasteIcon(String type) {
    if (type.contains('wet')) return Icons.eco_outlined;
    if (type.contains('dry')) return Icons.recycling_outlined;
    return Icons.delete_sweep_outlined;
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: CaptainTheme.chipRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: AppTextStyles.bodyMedium.copyWith(
            color: CaptainTheme.strongText,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (required)
          Text(
            ' *',
            style: AppTextStyles.bodyMedium.copyWith(
              color: CaptainTheme.danger,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }

  Future<void> _captureWastePhoto(
      String type, Map<String, dynamic> item) async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;

    final original = File(picked.path);
    final compressed = await ImageCompressService.compress(original);

    _safeSetState(() {
      final updated = Map<String, dynamic>.from(item);
      updated['image'] = compressed;
      if (_canApplyLiveWeight(type)) {
        updated['weight'] = latestWeight;
      }

      _wasteData = {
        ..._wasteData,
        type: updated,
      };

      if (_canApplyLiveWeight(type)) {
        activeType = type;
      }
      _syncManualWeightController(type, _weightTextFor(type));
    });
  }

  Widget _buildWasteSection(int index, String type, String displayName) {
    final item = _wasteData[type]!;
    final image = item['image'] as File?;
    final isAdded = item['isAdded'] as bool;
    final accent = _wasteAccent(type);
    final isEditingAdded =
        isAdded && activeType == type && item['finalWeight'] == null;
    final sectionKey = _wasteSectionKeys[type] ?? GlobalKey();
    final displayWeight =
        item['finalWeight'] != null && item['finalWeight'] != '--'
            ? item['finalWeight']
            : item['weight'];
    final hasWeight = displayWeight != null && displayWeight != '--';
    final quickWeights = _quickWeightsFor(type);

    return Container(
      key: sectionKey,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: CaptainTheme.surface,
        borderRadius: _kOperatorCardRadius,
        border: Border.all(
          color: (type == activeType) ? accent : CaptainTheme.hairline,
          width: (type == activeType) ? 1.6 : 1,
        ),
        boxShadow: CaptainTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(_wasteIcon(type), size: 20, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.heading2.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (image != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '1 Photo',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                _statusChip(
                  icon: isAdded ? Icons.check_circle : Icons.schedule,
                  label: isAdded ? 'Saved' : 'Pending',
                  color: isAdded ? CaptainTheme.success : CaptainTheme.warning,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final photoSize =
                        constraints.maxWidth < 390 ? 112.0 : 124.0;
                    final weightPanel = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Weight (kg)', required: true),
                        const SizedBox(height: 8),
                        Container(
                          height: 54,
                          decoration: BoxDecoration(
                            color: CaptainTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: CaptainTheme.hairline),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _manualWeightControllers[type],
                                  cursorColor: CaptainTheme.accent,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,2}$'),
                                    ),
                                  ],
                                  style: AppTextStyles.heading2.copyWith(
                                    color: CaptainTheme.strongText,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '0.00',
                                    filled: true,
                                    fillColor: CaptainTheme.surface,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    hintStyle: AppTextStyles.heading2.copyWith(
                                      color: CaptainTheme.mutedText,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  onChanged: (value) => setState(
                                    () => _updateManualWeight(type, value),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: 14,
                                  left: 8,
                                ),
                                child: Text(
                                  'kg',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: CaptainTheme.mutedText,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final quickWeight in quickWeights)
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: accent,
                                  side: BorderSide(
                                    color: accent.withValues(alpha: 0.3),
                                  ),
                                  backgroundColor:
                                      accent.withValues(alpha: 0.04),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  minimumSize: const Size(0, 38),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                onPressed: () =>
                                    _setQuickWeight(type, quickWeight),
                                child: Text(
                                    '${_formatQuickWeight(quickWeight)} kg'),
                              ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: accent,
                                side: BorderSide(
                                  color: accent.withValues(alpha: 0.3),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                minimumSize: const Size(0, 38),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              onPressed: () {},
                              child: const Text('Other'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.monitor_weight_outlined,
                              size: 16,
                              color: accent,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                hasWeight
                                    ? '$displayWeight kg ready'
                                    : 'Weight not set yet',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: CaptainTheme.strongText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                    final imagePanel = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Capture Image', required: true),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => image != null
                              ? _showPreview(image)
                              : _captureWastePhoto(type, item),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: photoSize,
                            height: photoSize,
                            decoration: BoxDecoration(
                              color: CaptainTheme.surfaceMuted,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.28),
                              ),
                              image: image != null
                                  ? DecorationImage(
                                      image: FileImage(image),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: image == null
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.camera_alt_outlined,
                                        size: 28,
                                        color: accent,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Add Photo',
                                        style:
                                            AppTextStyles.bodyMedium.copyWith(
                                          color: accent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  )
                                : Container(
                                    alignment: Alignment.bottomCenter,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withValues(alpha: 0.45),
                                        ],
                                      ),
                                    ),
                                    child: Text(
                                      'View / Retake',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    );

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: weightPanel),
                        const SizedBox(width: 12),
                        SizedBox(width: photoSize, child: imagePanel),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      isAdded ? 'Saved for submit' : 'Not saved yet',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isAdded
                            ? CaptainTheme.success
                            : CaptainTheme.mutedText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAdded
                              ? CaptainTheme.warning
                              : CaptainTheme.accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          if (isAdded && !isEditingAdded) {
                            setState(() => _startEditingAddedWeight(type));
                            return;
                          }
                          _handleAdd(type);
                        },
                        icon: Icon(
                          isAdded
                              ? (isEditingAdded ? Icons.save : Icons.refresh)
                              : Icons.add,
                          size: 18,
                        ),
                        label: Text(
                          isAdded
                              ? (isEditingAdded ? 'Save changes' : 'Edit item')
                              : 'Save item',
                          style: AppTextStyles.labelLarge.copyWith(
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPreview(File image) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.file(image),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  // ==================== MAIN UI ====================
  @override
  Widget build(BuildContext context) {
    final totalWeight = _calculateTotalWeight();
    final addedCount =
        _wasteData.values.where((item) => item['isAdded'] == true).length;

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_collectionSubmitted);
        return false;
      },
      child: Scaffold(
        backgroundColor: CaptainTheme.background,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: CaptainTheme.primary,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: DecoratedBox(
            decoration: BoxDecoration(gradient: CaptainTheme.headerGradient),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(_collectionSubmitted),
          ),
          title: const Text(
            "Household Collection",
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          centerTitle: false,
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCollectionHeader(),
                    const SizedBox(height: 18),
                    _buildWasteSectionHeader(),
                    const SizedBox(height: 10),
                    if (wasteTypes.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: CaptainTheme.surface,
                          borderRadius: CaptainTheme.cardRadius,
                          border: Border.all(color: CaptainTheme.hairline),
                        ),
                        child: Text(
                          "No waste types configured.",
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: CaptainTheme.mutedText,
                          ),
                        ),
                      )
                    else
                      ...wasteTypes.asMap().entries.map((entry) {
                        final index = entry.key;
                        final w = entry.value;
                        final type = w['waste_type_name']
                            .toString()
                            .trim()
                            .toLowerCase();
                        final name = w['waste_type_name'].toString();
                        return KeyedSubtree(
                          key: ValueKey("wastecard_${index}_$type"),
                          child: _buildWasteSection(index, type, name),
                        );
                      }),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: CaptainTheme.surface,
                        borderRadius: CaptainTheme.cardRadius,
                        border: Border.all(color: CaptainTheme.hairline),
                        boxShadow: CaptainTheme.softShadow,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: CaptainTheme.success
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.list_alt_rounded,
                                    color: CaptainTheme.success,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total items',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: CaptainTheme.mutedText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '$addedCount',
                                      style: AppTextStyles.heading2.copyWith(
                                        color: CaptainTheme.strongText,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: CaptainTheme.accent
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.scale_rounded,
                                    color: CaptainTheme.accent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total weight',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: CaptainTheme.mutedText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${totalWeight.toStringAsFixed(2)} kg',
                                      style: AppTextStyles.heading2.copyWith(
                                        color: CaptainTheme.strongText,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              color: CaptainTheme.surface,
              border: Border(top: BorderSide(color: CaptainTheme.hairline)),
              boxShadow: CaptainTheme.softShadow,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total waste',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: CaptainTheme.mutedText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${totalWeight.toStringAsFixed(2)} kg',
                        style: AppTextStyles.heading2.copyWith(
                          color: CaptainTheme.strongText,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CaptainTheme.accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: CaptainTheme.hairline,
                      disabledForegroundColor: CaptainTheme.mutedText,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    // Finalize only totals what "Save item" already uploaded, so
                    // submitting with nothing saved would close the visit at
                    // 0 kg with no photos. Stay disabled until at least one
                    // stream is saved.
                    onPressed: (_isSubmitting || addedCount == 0)
                        ? null
                        : _submitForm,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline, size: 20),
                    label: Text(
                      _isSubmitting ? 'Submitting' : 'Submit',
                      style: AppTextStyles.labelLarge.copyWith(
                        fontSize: 14,
                        // An explicit white would stay white on the disabled
                        // grey fill; let the button's own foreground win.
                        color: addedCount == 0 && !_isSubmitting
                            ? CaptainTheme.mutedText
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== BLUETOOTH INIT ====================

  /// Small, non-alarming floating banner reminding the operator to connect the
  /// Bluetooth scale. Replaces the verbose red error snackbars.
  void _showBluetoothNotice([
    String message = 'Connect the Bluetooth scale to record weight.',
  ]) {
    if (!mounted) return;
    AppFlash.info(context, message);
  }

  Future<bool> _ensureBluetoothPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();

    final granted = statuses.values.every((status) => status.isGranted);
    if (!granted) {
      _showBluetoothNotice(
        'Bluetooth permission is needed to connect the scale.',
      );
    }
    return granted;
  }

  // Known name fragments for the weighing-scale serial modules used in the
  // field (HC-05 / HC-06 / AEBT, plus generic scale labels). Matched
  // case-insensitively against the bonded device name.
  static const List<String> _scaleNameHints = [
    "AEBT",
    "HC-05",
    "HC-06",
    "HC05",
    "HC06",
    "HC",
    "WEIGH",
    "SCALE",
    "BT",
  ];

  BluetoothDevice? _pickScaleDevice(List<BluetoothDevice> devices) {
    for (final hint in _scaleNameHints) {
      for (final d in devices) {
        if ((d.name ?? "").toUpperCase().contains(hint)) {
          return d;
        }
      }
    }
    return null;
  }

  /// Auto-connect to the weighing scale (Android only). Tries to match a known
  /// scale module by name; if none matches, prompts the operator to pick the
  /// paired device manually so it works with any module label.
  Future<void> _initBluetooth() async {
    if (!_bluetoothSupported || connected || _btConnecting) return;

    if (!await _ensureBluetoothPermissions()) return;

    final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    if (devices.isEmpty) {
      debugPrint("⚠️ No bonded Bluetooth devices found.");
      _showBluetoothNotice(
        'No paired scale found. Pair the weighing machine, then tap Connect.',
      );
      return;
    }

    final device = _pickScaleDevice(devices);
    if (device == null) {
      // No confident auto-match — let the operator choose.
      await _promptDevicePicker(devices);
      return;
    }
    await _connectToDevice(device);
  }

  /// Bottom sheet listing the paired devices so the operator can select the
  /// exact weighing machine when auto-detect can't identify it.
  Future<void> _promptDevicePicker(List<BluetoothDevice> devices) async {
    if (!mounted) return;
    final selected = await showModalBottomSheet<BluetoothDevice>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Select weighing scale',
                  style: AppTextStyles.heading2,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Choose the paired Bluetooth weighing machine.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
              ...devices.map(
                (d) => ListTile(
                  leading: const Icon(Icons.scale, color: AppColors.primary),
                  title: Text(d.name ?? 'Unknown device'),
                  subtitle: Text(d.address),
                  onTap: () => Navigator.of(sheetContext).pop(d),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      await _connectToDevice(selected);
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (connected || _btConnecting) return;
    _safeSetState(() => _btConnecting = true);
    try {
      debugPrint("🔌 Connecting to ${device.name}...");
      final conn = await BluetoothConnection.toAddress(device.address);
      _safeSetState(() {
        _connection = conn;
        connected = true;
        _btConnecting = false;
        _connectedDeviceName = device.name ?? device.address;
      });

      String buffer = "";
      conn.input?.listen((Uint8List data) {
        final text = utf8.decode(data);
        buffer += text;
        if (buffer.contains('\n')) {
          final parts = buffer.split('\n');
          for (var line in parts.take(parts.length - 1)) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;

            bluetooth.updateWeight(trimmed);

            _safeSetState(() {
              latestWeight = trimmed;

              if (activeType != null &&
                  _wasteData.containsKey(activeType) &&
                  _canApplyLiveWeight(activeType!)) {
                final current = _wasteData[activeType!]!;
                final updated = Map<String, dynamic>.from(current);
                updated['weight'] = trimmed;
                updated['finalWeight'] = null;
                _wasteData = {
                  ..._wasteData,
                  activeType!: updated,
                };
                _syncManualWeightController(activeType!, trimmed);
              }
            });
          }
          buffer = parts.last;
        }
      }).onDone(() {
        _safeSetState(() {
          connected = false;
          _connectedDeviceName = null;
        });
      });
    } catch (e) {
      debugPrint("⚠️ Bluetooth connection error: $e");
      _safeSetState(() => _btConnecting = false);
      _showBluetoothNotice(
          'Couldn\'t connect to the scale. Tap Connect to retry.');
    }
  }
}
