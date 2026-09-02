import 'package:permission_handler/permission_handler.dart';

class BluetoothPermissions {
  static Future<bool> requestAll() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    final location = await Permission.location.request(); // for older BT APIs

    return scan.isGranted && connect.isGranted && location.isGranted;
  }

  /// The runtime grant that must exist before ANY adapter call on Android 12+
  /// (`isEnabled`, `requestEnable`, `getBondedDevices`, connecting).
  ///
  /// Declaring BLUETOOTH_CONNECT in the manifest is NOT sufficient there: it
  /// is a runtime permission, and calling `requestEnable()` without it throws
  /// a SecurityException inside flutter_bluetooth_serial. That plugin then
  /// replies to the same MethodChannel call twice ("Reply already submitted"),
  /// which is an unhandled Java exception on the main thread and kills the
  /// whole process. Always gate adapter calls on this.
  ///
  /// Location is deliberately NOT required: it is only needed for discovery on
  /// pre-Android-12 devices, and demanding it here would disable the scale for
  /// drivers who declined location.
  static Future<bool> ensureConnect() async {
    final connect = await Permission.bluetoothConnect.request();
    if (!connect.isGranted) return false;
    await Permission.bluetoothScan.request();
    return true;
  }

  static Future<bool> isGranted() async {
    return await Permission.bluetoothScan.isGranted &&
        await Permission.bluetoothConnect.isGranted;
  }
}
