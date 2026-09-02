import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../services/bluetooth_permissons.dart';

/// Owns the Bluetooth weigh-scale connection for the whole app session.
///
/// Deliberately app-scoped, not screen-scoped: this used to be connected and
/// reconnected entirely from inside `household_collect_sheet.dart`, so the
/// socket was only ever as alive as the sheet that last opened it. A dropped
/// connection (out of range for a moment, the phone's Bluetooth stack idling,
/// the HC-05 module resetting) then surfaced as "asks me to connect" the next
/// time a driver opened a collect sheet, because nothing was trying to
/// reconnect in the meantime.
///
/// This class now:
///   * is started once, early (see `ensureConnected` called from
///     `DriverHomePage.initState`), so the scale is usually already connected
///     by the time any collect sheet opens;
///   * watches app lifecycle itself (it is its own `WidgetsBindingObserver`,
///     not borrowed from whichever screen happens to be mounted) and
///     reconnects on resume;
///   * auto-reconnects in the background on an unexpected drop, with a capped
///     backoff, WITHOUT ever popping a permission or "enable Bluetooth"
///     dialog out of nowhere — those only ever appear from a deliberate
///     foreground trigger (resume, the sheet's own Connect button), never
///     from the silent retry timer.
///
/// `weightStream` stays a broadcast stream that anyone can subscribe to, but
/// in practice only `household_collect_sheet.dart` ever does — so weight
/// readings are still only ever CONSUMED while a collect sheet is open, even
/// though the underlying socket is connected for the whole app session.
class BluetoothService with WidgetsBindingObserver {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;

  BluetoothService._internal() {
    if (isSupported) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  /// Classic SPP is Android-only (the HC-05 / AEBT scale modules are not
  /// Apple-MFi) — every method below is a no-op on iOS.
  static bool get isSupported => Platform.isAndroid;

  final _weightCtrl = StreamController<String>.broadcast();
  Stream<String> get weightStream => _weightCtrl.stream;

  /// Broadcasts every time [connected] actually changes, so a UI (the collect
  /// sheet's scale bar) can reflect connection state reactively instead of
  /// polling it once at the moment it happened to call a method.
  final _connectionCtrl = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionCtrl.stream;

  BluetoothConnection? _conn;
  // The input listener owned by [connect]. Kept so a reconnect can cancel the
  // previous one instead of stacking a second listener on a dead socket.
  StreamSubscription<Uint8List>? _inputSub;
  bool get connected => _conn != null && _conn!.isConnected;

  String latestWeight = "--";

  // ── Background auto-reconnect ────────────────────────────────────────────
  // Set once anything asks this service to connect, and never cleared by a
  // drop — it only becomes false via an explicit [disconnect] call (nothing
  // in the app makes one today). Gates the silent retry timer: without a
  // standing "I should be connected" intent, an unrelated screen touching
  // this singleton must not spin up a reconnect loop.
  bool _wantsConnection = false;
  Timer? _reconnectTimer;
  static const _initialRetryDelay = Duration(seconds: 5);
  static const _maxRetryDelay = Duration(seconds: 30);
  Duration _nextRetryDelay = _initialRetryDelay;

  // ✅ Called when a new weight reading arrives
  void updateWeight(String weight) {
    latestWeight = weight;
    _weightCtrl.add(weight); // pushes to StreamBuilder
  }

  /// The one entry point every caller should use — the app-startup hook, the
  /// collect sheet's own "Connect" button, and the silent background retry
  /// all go through this.
  ///
  /// [allowPrompt] controls whether this call may pop OS dialogs (the
  /// permission request, "turn on Bluetooth"): true for anything triggered by
  /// the driver being in the app right now (app resumed, a sheet opened, the
  /// Connect button tapped), false for the unattended background retry timer,
  /// which must never surprise the driver with a system dialog while they are
  /// doing something unrelated.
  Future<void> ensureConnected({bool allowPrompt = true}) async {
    if (!isSupported) return;
    _wantsConnection = true;
    if (connected) return;

    if (!allowPrompt) {
      // Silent path: only proceed if everything is already in place. Never
      // request a permission or the adapter here.
      if (!await BluetoothPermissions.isGranted()) return;
      final enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
      if (!enabled) return;
      await _connectQuietly();
      return;
    }

    // Prompting path — runtime BLUETOOTH_CONNECT MUST be granted before any
    // adapter call on Android 12+. This must run BEFORE isEnabled/
    // requestEnable(): calling those without the grant throws a
    // SecurityException inside flutter_bluetooth_serial, which then replies
    // to the same MethodChannel call twice ("Reply already submitted") — a
    // FATAL main-thread exception that kills the app outright.
    final granted = await BluetoothPermissions.ensureConnect();
    if (!granted) return;

    final enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
    if (!enabled) {
      try {
        await FlutterBluetoothSerial.instance.requestEnable();
      } catch (_) {
        // Driver declined the enable prompt, or the OEM blocked it. Never
        // let this escape — see the note above on how it ends the process.
        return;
      }
    }
    await _connectQuietly();
  }

  Future<void> _connectQuietly() async {
    try {
      await connect();
    } catch (_) {
      // connect() already throws on anything from "no bonded devices" to a
      // socket error — this is the unattended path, so swallow it and let
      // the reconnect timer (armed from connect()'s own failure/drop path)
      // try again rather than surfacing an exception nobody is watching for.
    }
  }

  Future<void> connect() async {
    // Already on a live socket — reuse it. Without this guard every caller
    // (each collect sheet open, every app resume) opened ANOTHER native
    // BluetoothConnection while the previous one was still held, leaking a
    // socket + its listener each time until Android killed the process for
    // memory. This is a singleton, so those leaks accumulate app-wide.
    if (connected) return;
    _wantsConnection = true;

    // A half-dead connection (socket closed but object retained) must be torn
    // down before we replace it, or its input subscription outlives it.
    await _teardown();

    // 🔒 Mandatory permission check. Uses ensureConnect (not requestAll) so a
    // driver who declined LOCATION can still use the scale — location is only
    // needed for discovery on pre-Android-12 devices, and we connect to an
    // already-bonded device.
    final ok = await BluetoothPermissions.ensureConnect();
    if (!ok) {
      throw Exception("Bluetooth permissions not granted");
    }

    // 🔄 Prevent plugin crash
    try {
      await FlutterBluetoothSerial.instance.cancelDiscovery();
    } catch (e) {
      print("⚠️ cancelDiscovery skipped: $e");
    }

    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (devices.isEmpty) {
        throw Exception('No bonded devices found.');
      }

      final dev = devices.firstWhere(
        (d) => (d.name ?? '').toUpperCase().contains('HC'),
        orElse: () => devices.first,
      );

      _conn = await BluetoothConnection.toAddress(dev.address);

      String buffer = '';
      _inputSub = _conn!.input?.listen((Uint8List data) {
        buffer += utf8.decode(data);
        int idx;
        while ((idx = buffer.indexOf('\n')) != -1) {
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);
          if (line.isNotEmpty) updateWeight(line);
        }
      });
      // onDone returns void, so it is registered on the subscription rather
      // than chained onto the assignment.
      _inputSub?.onDone(() {
        _conn = null;
        _inputSub = null;
        _connectionCtrl.add(false);
        // An unexpected drop, not a deliberate disconnect() — try to get
        // back on the socket without anyone having to reopen a screen.
        _scheduleReconnect();
      });

      // Connected: reset backoff for the next time this drops, and tell
      // anyone listening (the collect sheet's scale bar).
      _nextRetryDelay = _initialRetryDelay;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _connectionCtrl.add(true);
    } catch (e) {
      // Connection attempt itself failed (no bonded devices, socket refused,
      // ...) — still worth retrying in the background rather than only on
      // the next explicit call.
      _scheduleReconnect();
      rethrow;
    }
  }

  /// Schedules exactly one silent retry with capped exponential backoff.
  /// Safe to call repeatedly — always cancels any timer already pending.
  void _scheduleReconnect() {
    if (!_wantsConnection || !isSupported) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_nextRetryDelay, () {
      _nextRetryDelay = Duration(
        seconds:
            (_nextRetryDelay.inSeconds * 2).clamp(0, _maxRetryDelay.inSeconds),
      );
      // Silent: a background timer must never pop a permission/adapter
      // dialog on its own.
      unawaited(ensureConnected(allowPrompt: false));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _wantsConnection && !connected) {
      // Foreground, deliberate trigger — may prompt, matching what the
      // collect sheet itself used to do here.
      unawaited(ensureConnected(allowPrompt: true));
    }
  }

  Future<void> _teardown() async {
    try {
      await _inputSub?.cancel();
    } catch (_) {}
    _inputSub = null;
    try {
      _conn?.dispose();
    } catch (_) {}
    _conn = null;
  }

  /// Deliberate disconnect. Nothing in the app calls this today — it exists
  /// so a future "forget this scale" action has somewhere to go — but calling
  /// it DOES stop the background auto-reconnect (unlike an unexpected drop).
  Future<void> disconnect() async {
    _wantsConnection = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _teardown();
    _connectionCtrl.add(false);
  }

  void dispose() {
    _reconnectTimer?.cancel();
    if (isSupported) {
      WidgetsBinding.instance.removeObserver(this);
    }
    unawaited(_teardown());
    _weightCtrl.close();
    _connectionCtrl.close();
  }
}
