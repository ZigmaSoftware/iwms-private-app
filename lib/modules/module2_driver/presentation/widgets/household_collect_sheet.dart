import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/ui/app_flash.dart';
import 'package:iwms_private_app/data/models/operator_trip_models.dart';
import 'package:iwms_private_app/data/repositories/auth_repository.dart';
import 'package:iwms_private_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/state/scale_reading.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/waste_type_visuals.dart';
import 'package:iwms_private_app/modules/module3_operator/services/bluetoothservices.dart';
import 'package:iwms_private_app/modules/module3_operator/services/generateunique_id.dart';

/// In-drawer household collection.
///
/// Replaces the old full-screen `OperatorDataScreen` push for the household
/// "Collect" path: the driver scans a QR, and everything — waste selection,
/// weight, photo, submit — happens inside the same bottom sheet. No navigation.
///
/// Flow:
///   1. Customer name + ID at the top.
///   2. A vertical list of the waste types registered against this customer,
///      one full-width card per stream, all the same height.
///   3. Tapping a card expands it in place into a weight field with a camera
///      button. Capturing the photo **auto-submits** the row — there is no
///      manual "Add" button, because the photo is always the last step and a
///      separate tap was pure ceremony.
///   4. An added card collapses back showing its photo thumbnail, the recorded
///      weight, and Edit / Reset.
///   5. "Submit" finalizes the visit.
///
/// Backend contract is unchanged from the old screen — one
/// `waste/insert-waste-sub/` (or `update-waste-sub/`) multipart per waste type,
/// then a single `waste/finalize-waste/` keyed on the same `screen_unique_id`.
/// That matters: `finalize-waste` aggregates the sub-rows it finds for that
/// screen id, and the backend signal on the resulting WasteCollection is what
/// marks the household stop collected.
///
/// Returns `true` when a finalize succeeded, so the caller refreshes its list.
class HouseholdCollectSheet extends StatefulWidget {
  const HouseholdCollectSheet({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.latitude,
    required this.longitude,
    this.assignmentId,
    this.onSecondaryAction,
  });

  final String customerId;
  final String customerName;
  final String latitude;
  final String longitude;
  final String? assignmentId;

  /// Called with `'collect_later'` or `'not_available'` when the driver picks
  /// one of the bottom exception options. The caller closes this sheet and
  /// runs the reason capture + status POST. Omit to hide those options.
  final void Function(String action)? onSecondaryAction;

  @override
  State<HouseholdCollectSheet> createState() => _HouseholdCollectSheetState();
}

/// Per-waste-stream capture state. Kept as a small mutable object rather than
/// the old screen's `Map<String, dynamic>` bag so the fields are typed and a
/// typo is a compile error.
class _WasteEntry {
  _WasteEntry({required this.id, required this.name});

  final String id;
  final String name;

  final TextEditingController weight = TextEditingController();
  File? photo;

  /// Set once the row has been POSTed. Holds the backend's `unique_id` so a
  /// re-edit becomes an update instead of a duplicate insert.
  String? remoteUniqueId;

  /// The weight as accepted by the server, shown on the collapsed card.
  double? addedWeight;

  bool get isAdded => addedWeight != null;

  /// True once this row's weight must NOT be touched by further scale
  /// readings.
  ///
  /// This is the fix for the weight silently vanishing: the scale streams
  /// continuously, so while the camera was open the driver lifting the bag off
  /// the platform pushed a `0` reading straight into [weight], overwriting the
  /// number that had just been validated. `_add` then re-read the controller,
  /// got 0, and refused the row with "Enter a weight" — the capture was lost.
  ///
  /// Set the moment the driver taps "Capture photo to add" — NOT
  /// automatically when the scale settles. The weight is expected to keep
  /// moving right up until that tap (more waste added to the same load,
  /// the platform still stabilizing), so the field must keep tracking the
  /// live scale until the driver says it's done. Deliberately does not make
  /// the field read-only: typing over a locked weight releases the lock (see
  /// `_onWeightFieldChanged`).
  bool isLocked = false;

  /// Set while the camera is open / the row is being POSTed. Hard block on any
  /// stream write, independent of [isLocked] so unlocking mid-capture cannot
  /// reopen the hole above.
  bool isCapturing = false;

  /// True when the value in [weight] was typed by the driver rather than
  /// pushed by the scale. Manual weights are never auto-overwritten by a
  /// reading.
  bool isManual = false;

  /// Delegates to [ScaleReadingTracker.parseWeight] so the field, the settle
  /// check and the commit path all share one definition of a usable weight.
  double? get parsedWeight => ScaleReadingTracker.parseWeight(weight.text);

  void dispose() => weight.dispose();
}

class _HouseholdCollectSheetState extends State<HouseholdCollectSheet> {
  final ImagePicker _picker = ImagePicker();
  final BluetoothService _bluetooth = BluetoothService();

  late final String _screenUniqueId;

  List<_WasteEntry> _entries = const [];
  bool _loadingTypes = true;
  bool _loadError = false;

  /// Which card is currently expanded for entry. Null = all collapsed.
  String? _activeId;

  bool _submitting = false;
  String? _addingId;

  // ── Bluetooth scale ──────────────────────────────────────────────────────
  // The socket itself is owned app-wide by BluetoothService now (started from
  // DriverHomePage.initState, kept alive and auto-reconnected across the
  // whole driver session — see that class's docstring). This sheet only ever
  // does two things: SUBSCRIBES to its streams while open, and unsubscribes
  // on dispose. It never owns connecting/reconnecting the socket — that used
  // to live here, which is exactly why the scale looked "disconnected" every
  // time this sheet reopened after a drop: nothing was trying to reconnect in
  // between sheet visits. Weight readings are still only ever CONSUMED here,
  // even though the connection itself now outlives the sheet.
  //
  // Classic SPP is Android-only (the HC-05 / AEBT scale modules are not
  // Apple-MFi), so on iOS the scale UI is hidden and entry is manual.
  bool get _scaleSupported => BluetoothService.isSupported;
  // Must be cancelled in dispose: without it every open of this sheet (i.e.
  // every customer card tap) added another permanent listener that captured
  // this State — retaining the whole sheet, its controllers and any captured
  // photos for the life of the app. A handful of stops was enough to OOM a
  // low-RAM phone, which is why it only survived on high-RAM devices.
  StreamSubscription<String>? _weightSub;
  StreamSubscription<bool>? _connectionSub;
  bool _connected = false;
  bool _connecting = false;
  String? _deviceName;
  String _liveWeight = '--';

  // ── Settle detection ─────────────────────────────────────────────────────
  // The scale streams a reading several times a second and the value wobbles
  // while the load settles. A weight is treated as final once the SAME value
  // has arrived this many times in a row; at typical HC-05 output that is
  // roughly half a second of a steady platform.
  static const int _kStableReadingsRequired = 4;

  /// Normalizes raw scale lines (strips units, rejects zero/negative/junk).
  /// Its settle-detection is unused here on purpose — see `_onScaleReading`:
  /// the weight keeps tracking the live scale until the driver explicitly
  /// taps "Capture photo to add", it is never auto-locked or auto-captured.
  final ScaleReadingTracker _scaleTracker =
      ScaleReadingTracker(stableReadingsRequired: _kStableReadingsRequired);

  @override
  void initState() {
    super.initState();
    _screenUniqueId = UniqueIdService.generateScreenUniqueId();
    _loadWasteTypes();
    if (_scaleSupported) _initScale();
  }

  @override
  void dispose() {
    _weightSub?.cancel();
    _weightSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<void> _loadWasteTypes() async {
    try {
      final types = await GetIt.instance<OperatorTripRepository>()
          .fetchCustomerWasteTypes(widget.customerId);
      if (!mounted) return;
      setState(() {
        _entries = _prioritize(types)
            .map((t) => _WasteEntry(id: t.id, name: t.name))
            .toList();
        _loadingTypes = false;
      });
    } catch (e, st) {
      // Don't swallow silently — an empty list used to be indistinguishable
      // from "this customer genuinely has no waste types registered".
      debugPrint('household waste-type load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadingTypes = false;
        _loadError = true;
      });
    }
  }

  /// Wet first, then Dry, then everything else in API order — the two primary
  /// segregated streams are what the driver reaches for most.
  List<CustomerWasteType> _prioritize(List<CustomerWasteType> types) {
    int rank(CustomerWasteType t) {
      final k = t.name.toLowerCase();
      if (k.contains('wet')) return 0;
      if (k.contains('dry')) return 1;
      return 2;
    }

    final indexed = types.asMap().entries.toList()
      ..sort((a, b) {
        final byRank = rank(a.value).compareTo(rank(b.value));
        return byRank != 0 ? byRank : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  Future<Map<String, String>> _authHeaders() async {
    try {
      final user =
          await GetIt.instance<AuthRepository>().getAuthenticatedUser();
      final token = user?.authToken?.trim();
      if (token != null && token.isNotEmpty) {
        return {'Authorization': 'Bearer $token'};
      }
    } catch (_) {}
    return const {};
  }

  // ── Bluetooth ────────────────────────────────────────────────────────────
  // The socket is owned by BluetoothService app-wide (see the field comment
  // above). This sheet's job is now only: subscribe to what it needs, and ask
  // the service to connect if it somehow isn't already — it never runs the
  // permission/adapter/socket dance itself anymore.

  void _initScale() {
    if (!_scaleSupported) return;

    // Weight readings: only ever consumed while a collect sheet is open —
    // this is the "only receive weight in collect sheet" half of the ask. The
    // connection itself lives independently of this subscription.
    _weightSub = _bluetooth.weightStream.listen(_onScaleReading);

    // Connection status: seed from whatever the service already knows (very
    // likely already connected, since DriverHomePage starts it on login), then
    // stay in sync with it reactively for as long as this sheet is open.
    _connected = _bluetooth.connected;
    _deviceName = _connected ? 'Weighing scale' : null;
    _connectionSub = _bluetooth.connectionStream.listen((isConnected) {
      if (!mounted) return;
      setState(() {
        _connected = isConnected;
        _deviceName = isConnected ? 'Weighing scale' : null;
      });
    });

    // In case the app-level connect hasn't happened yet or was declined
    // earlier, opening a collect sheet is itself a deliberate, foreground
    // moment — safe to prompt for permission/adapter-enable here too.
    if (!_connected) _connectScale();
  }

  Future<void> _connectScale() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      await _bluetooth.ensureConnected(allowPrompt: true);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  /// A reading auto-fills the card the driver is currently on, and only while
  /// that card is still open for input.
  ///
  /// Deliberately keeps writing the live value right up until the driver taps
  /// "Capture photo to add" — the weight can keep moving (more waste added to
  /// the same load, the platform still settling), so nothing here freezes the
  /// number or opens the camera on its own. The camera is ALWAYS an explicit
  /// tap; see `_capturePhotoAndAdd`, which latches whatever is showing at that
  /// moment before it opens the camera — that latch is what stops the
  /// zero-reading-while-photographing bug, not locking the field early.
  ///
  /// Still defensive about NOT clobbering a good number:
  ///   * a non-positive / negative / junk reading is dropped entirely, so a
  ///     scale returning to zero can never wipe a captured weight;
  ///   * a locked (mid-capture/committed), capturing, added or manually-typed
  ///     entry is never written.
  void _onScaleReading(String raw) {
    if (!mounted) return;
    final reading = _scaleTracker.add(raw);
    final cleaned = reading.value;

    // Header readout always reflects the live platform, even when the value is
    // not eligible to be written into a card.
    setState(() => _liveWeight = cleaned ?? '--');
    if (cleaned == null) return;

    final activeId = _activeId;
    if (activeId == null) return;
    final entry = _entryFor(activeId);
    if (entry == null) return;
    // Any of these means the number on screen is not the stream's to change.
    if (entry.isAdded ||
        entry.isLocked ||
        entry.isCapturing ||
        entry.isManual) {
      return;
    }

    entry.weight.text = cleaned;
    setState(() {});
  }

  /// The driver typed in the weight field.
  ///
  /// Marks the row manual so the scale stops writing to it (a driver correcting
  /// a scale value must not have it snap back), and releases any lock. Manual
  /// entry deliberately never auto-opens the camera — the driver finishes with
  /// the button, which is the only reliable signal that they are done typing.
  void _onWeightFieldChanged(_WasteEntry entry, String value) {
    if (entry.isCapturing) return;
    final wasManual = entry.isManual;
    final wasLocked = entry.isLocked;
    entry.isManual = true;
    entry.isLocked = false;
    // Only rebuild when something the UI shows actually changed; the field
    // itself is driven by its own controller.
    if (!wasManual || wasLocked) setState(() {});
  }

  _WasteEntry? _entryFor(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _toggleCard(_WasteEntry entry) {
    FocusScope.of(context).unfocus();
    setState(() {
      if (_activeId == entry.id) {
        _activeId = null;
      } else {
        _activeId = entry.id;
        // Seed from the live scale so the driver usually just shoots the photo.
        if (!entry.isAdded &&
            entry.weight.text.trim().isEmpty &&
            _liveWeight != '--') {
          entry.weight.text = _liveWeight;
        }
      }
    });
    // Opening a card by hand restarts settle tracking, so the weight now on
    // the platform has to hold steady again before it locks/auto-captures for
    // THIS card. Otherwise a still platform would fire instantly on open.
    _scaleTracker.reset();
  }

  /// Re-open an already-added row for changes. The existing weight and photo
  /// stay in place, and `remoteUniqueId` is preserved so the next capture
  /// updates that row rather than inserting a second one.
  void _edit(_WasteEntry entry) {
    FocusScope.of(context).unfocus();
    setState(() => _activeId = entry.id);
  }

  /// Clear a row back to untouched. Local-only: the server row (if any) is left
  /// as-is and will simply be overwritten by `update-waste-sub` when the driver
  /// re-captures, so this never orphans a sub-row for `finalize-waste` to
  /// double-count.
  void _reset(_WasteEntry entry) {
    FocusScope.of(context).unfocus();
    setState(() {
      entry.weight.clear();
      entry.photo = null;
      entry.addedWeight = null;
      // Back to untouched means the scale owns this row again.
      entry.isLocked = false;
      entry.isManual = false;
      if (_activeId == entry.id) _activeId = null;
    });
  }

  /// Open the next waste type still waiting for a weight.
  ///
  /// Called after a row commits so the driver is dropped straight into the
  /// next stream instead of tapping a card open for every one — the scale
  /// still fills the field live for the new card, but the camera stays
  /// closed until "Capture photo to add" is tapped for it too. Returns false
  /// when nothing is left, which is the cue to leave every card collapsed
  /// and show the Submit CTA.
  bool _openNextPendingEntry() {
    for (final candidate in _entries) {
      if (!candidate.isAdded) {
        setState(() {
          _activeId = candidate.id;
          // A fresh card must be free for the scale to fill, even if a
          // previous visit to it left a stale lock behind.
          candidate.isLocked = false;
        });
        // Reset the tracker so a platform still holding the previous load
        // doesn't carry a stale "same value repeated N times" count into the
        // new card's normalized-reading state.
        _scaleTracker.reset();
        return true;
      }
    }
    return false;
  }

  /// Capture the photo and, on success, immediately commit the row. The photo
  /// is always the last input, so a separate "Add" tap was pure ceremony —
  /// shooting it *is* the confirmation.
  Future<void> _capturePhotoAndAdd(_WasteEntry entry) async {
    // LATCH the weight before anything async happens. `_add` used to re-read
    // entry.weight after the camera returned, by which point the scale had
    // pushed a fresh (usually zero) reading over it and the row was refused.
    // Everything downstream now uses this snapshot, so the number the driver
    // saw when they committed is the number that gets saved.
    final latchedWeight = entry.parsedWeight;
    if (latchedWeight == null) {
      AppFlash.warning(context, 'Enter a weight for ${entry.name} first');
      return;
    }
    if (entry.isCapturing) return;

    setState(() {
      entry.isCapturing = true;
      entry.isLocked = true;
    });
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        // A full-res camera frame is a ~12MP JPEG that decodes to tens of MB
        // of ARGB. This photo is only ever shown as a thumbnail and uploaded
        // as proof, so cap it at capture time — the single biggest memory
        // saving on low-RAM devices.
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (shot == null || !mounted) return;
      setState(() => entry.photo = File(shot.path));
      await _add(entry, weight: latchedWeight);
    } catch (e) {
      if (mounted) AppFlash.error(context, 'Could not open camera: $e');
    } finally {
      // Release the capture guard, but KEEP isLocked: the weight is committed
      // (or the driver cancelled the camera with the number still on screen)
      // and a stray reading must not rewrite it either way. Typing releases it.
      if (mounted) {
        setState(() => entry.isCapturing = false);
      } else {
        entry.isCapturing = false;
      }
    }
  }

  /// POSTs one waste row. Insert the first time, update on re-edit — the old
  /// screen's behaviour, so editing a weight never leaves a duplicate row
  /// behind for `finalize-waste` to double-count.
  /// [weight] is the value latched when the driver committed. It is passed in
  /// rather than re-read from `entry.weight` precisely because a live scale
  /// reading may have changed the controller in the meantime — see
  /// [_capturePhotoAndAdd].
  Future<void> _add(_WasteEntry entry, {double? weight}) async {
    final resolvedWeight = weight ?? entry.parsedWeight;
    if (resolvedWeight == null) {
      AppFlash.warning(context, 'Enter a weight for ${entry.name}');
      return;
    }
    if (entry.photo == null) {
      AppFlash.warning(context, 'Capture a photo for ${entry.name}');
      return;
    }

    setState(() => _addingId = entry.id);
    try {
      final isUpdate = entry.remoteUniqueId != null;
      final uri = Uri.parse(
        isUpdate
            ? '${ApiConfig.desktopBase}waste/update-waste-sub/'
            : '${ApiConfig.desktopBase}waste/insert-waste-sub/',
      );

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(await _authHeaders())
        ..fields['screen_unique_id'] = _screenUniqueId
        ..fields['customer_id'] = widget.customerId
        // Both keys are sent because the backend has read each at different
        // times; harmless and keeps older deployments working.
        ..fields['waste_type'] = entry.id
        ..fields['waste_type_id'] = entry.id
        ..fields['weight'] = resolvedWeight.toString()
        // Scopes the guard on the backend to this trip: insert-waste-sub
        // rejects a household that is not a stop on it.
        ..fields['assignment_id'] = widget.assignmentId ?? ''
        ..fields['latitude'] = widget.latitude
        ..fields['longitude'] = widget.longitude;

      if (isUpdate) request.fields['unique_id'] = entry.remoteUniqueId!;
      request.files.add(
        await http.MultipartFile.fromPath('image', entry.photo!.path),
      );

      final streamed = await request.send();
      if (streamed.statusCode >= 400) {
        throw Exception('Server error ${streamed.statusCode}');
      }
      final body = json.decode(
        (await http.Response.fromStream(streamed)).body,
      );
      if (body['status'] != 'success') {
        throw Exception(body['message'] ?? 'Could not save ${entry.name}');
      }

      if (!mounted) return;
      setState(() {
        entry.remoteUniqueId =
            body['unique_id']?.toString() ?? entry.remoteUniqueId;
        entry.addedWeight = resolvedWeight;
        // Keep the field showing exactly what was saved: the controller may
        // still hold a stale live reading from before the latch.
        entry.weight.text = _formatWeight(resolvedWeight);
        entry.isLocked = true;
        _activeId = null;
      });
      HapticFeedback.mediumImpact();
      // Straight into the next stream — see _openNextPendingEntry.
      _openNextPendingEntry();
    } catch (e) {
      if (mounted) {
        AppFlash.error(context, 'Could not add ${entry.name}: $e');
      }
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  double get _total => _entries.fold(
        0.0,
        (sum, e) => sum + (e.addedWeight ?? 0),
      );

  int get _addedCount => _entries.where((e) => e.isAdded).length;

  Future<void> _submit() async {
    if (_addedCount == 0) {
      AppFlash.warning(context, 'Add at least one waste weight first');
      return;
    }
    setState(() => _submitting = true);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.desktopBase}waste/finalize-waste/'),
      )
        ..headers.addAll(await _authHeaders())
        ..fields['screen_unique_id'] = _screenUniqueId
        ..fields['customer_id'] = widget.customerId
        ..fields['entry_type'] = 'app'
        // Scopes the collection to this trip, so the backend marks the right
        // household stop (a driver can hold a bin AND a household trip).
        ..fields['assignment_id'] = widget.assignmentId ?? ''
        ..fields['total_waste_collected'] = _total.toString();

      final response = await http.Response.fromStream(
        await request.send(),
      );
      final result = json.decode(response.body);

      if (result['status'] != 'success') {
        // A refusal the server actually answered (e.g. the trip isn't
        // started). Surface it and leave the visit open rather than pretending
        // the household was collected.
        if (mounted) {
          AppFlash.warning(
            context,
            result['message']?.toString() ?? 'Could not submit this collection',
          );
        }
        return;
      }

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) AppFlash.error(context, 'Could not submit: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 14),
            if (_scaleSupported) ...[
              _scaleBar(),
              const SizedBox(height: 14),
            ],
            if (_loadingTypes)
              _loadingBlock()
            else if (_entries.isEmpty)
              _emptyBlock()
            else
              _wasteList(),
            if (_addedCount > 0) ...[
              const SizedBox(height: 16),
              _totalBar(),
            ],
            const SizedBox(height: 16),
            _submitButton(),
            // Secondary outcomes live at the bottom of this same drawer, behind
            // a divider — collecting is the common case, these are exceptions.
            // Hidden once a weight has been added, since "not available" would
            // then contradict data already sent to the server.
            if (_addedCount == 0 && widget.onSecondaryAction != null) ...[
              const SizedBox(height: 18),
              Divider(color: CaptainTheme.hairline, height: 1),
              const SizedBox(height: 14),
              Text(
                "Can't collect right now?",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: CaptainTheme.mutedText,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CaptainTheme.strongText,
                        side: BorderSide(color: CaptainTheme.hairline),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: _submitting
                          ? null
                          : () => widget.onSecondaryAction!('collect_later'),
                      child: const Text('Collect later'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CaptainTheme.strongText,
                        side: BorderSide(color: CaptainTheme.hairline),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: _submitting
                          ? null
                          : () => widget.onSecondaryAction!('not_available'),
                      child: const Text('Not available'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.customerName.trim().isEmpty
              ? 'Household'
              : widget.customerName,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: CaptainTheme.strongText,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'ID: ${widget.customerId}',
          style: TextStyle(
            color: CaptainTheme.mutedText,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }

  Widget _scaleBar() {
    final connected = _connected;
    final color = connected ? CaptainTheme.success : CaptainTheme.mutedText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            connected
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_disabled_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected
                      ? (_deviceName ?? 'Scale connected')
                      : 'Scale not connected',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: CaptainTheme.strongText,
                  ),
                ),
                if (connected)
                  Text(
                    'Live: $_liveWeight kg',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: CaptainTheme.mutedText,
                    ),
                  )
                else
                  Text(
                    'You can still type weights manually',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: CaptainTheme.mutedText,
                    ),
                  ),
              ],
            ),
          ),
          if (_connecting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (!connected)
            TextButton(
              onPressed: _connectScale,
              child: const Text('Connect'),
            ),
        ],
      ),
    );
  }

  Widget _loadingBlock() {
    return Container(
      height: 92,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CaptainTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      ),
    );
  }

  Widget _emptyBlock() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CaptainTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CaptainTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _loadError
                ? "Couldn't load this customer's waste types. Check your "
                    'connection and try again.'
                : 'No waste types are registered for this customer. Ask your '
                    'supervisor to set them in Customer Creation.',
            style: TextStyle(
              color: CaptainTheme.mutedText,
              fontWeight: FontWeight.w600,
              height: 1.4,
              fontSize: 12.5,
            ),
          ),
          if (_loadError) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _loadingTypes = true;
                  _loadError = false;
                });
                _loadWasteTypes();
              },
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  /// Full-width vertical list, one card per stream. Every collapsed card is the
  /// same height ([_kRowHeight]) so the list reads as an even column the driver
  /// can thumb down; only the expanded card is taller.
  Widget _wasteList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          if (_entries[i].id == _activeId)
            _expandedCard(_entries[i])
          else
            _collapsedCard(_entries[i]),
        ],
      ],
    );
  }

  /// Fixed height for every collapsed row, so the list stays a tidy even column
  /// whether or not a row has been collected.
  static const double _kRowHeight = 76;

  Widget _collapsedCard(_WasteEntry entry) {
    final visual = WasteTypeVisual.forName(entry.name);
    final added = entry.isAdded;
    // Each stream keeps its own hue whether or not it's been collected — the
    // list should read as colour-coded waste types at a glance, with the
    // thumbnail and weight (not a colour change) signalling "done", so the
    // driver can still find "the green one" after adding it.
    final accent = visual.color;

    return _AnimatedCardShell(
      // An added row is opened via its explicit Edit button, so tapping the
      // body is reserved for rows still waiting on a weight.
      onTap: added ? null : () => _toggleCard(entry),
      accent: accent,
      filled: true,
      strongFill: added,
      height: _kRowHeight,
      child: Row(
        children: [
          // Leading plate: the captured photo once there is one, otherwise the
          // stream's solid colour chip. Same footprint either way, so the row
          // doesn't shift when a photo lands.
          _leadingPlate(entry, accent, visual),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: CaptainTheme.strongText,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  added ? '${_fmt(entry.addedWeight!)} kg' : 'Tap to add weight',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: added ? 16 : 12,
                    fontWeight: added ? FontWeight.w900 : FontWeight.w600,
                    color: added ? accent : CaptainTheme.mutedText,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (added)
            // Edit re-opens the row for changes (weight and/or a new photo);
            // Reset clears it back to untouched.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _rowAction(
                  icon: Icons.edit_rounded,
                  tooltip: 'Edit',
                  color: accent,
                  onTap: _submitting ? null : () => _edit(entry),
                ),
                const SizedBox(width: 6),
                _rowAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Reset',
                  color: CaptainTheme.mutedText,
                  onTap: _submitting ? null : () => _reset(entry),
                ),
              ],
            )
          else
            Icon(
              Icons.add_circle_outline_rounded,
              size: 22,
              color: accent.withValues(alpha: 0.55),
            ),
        ],
      ),
    );
  }

  /// Square leading plate — photo thumbnail when captured, coloured stream icon
  /// otherwise.
  Widget _leadingPlate(
    _WasteEntry entry,
    Color accent,
    WasteTypeVisual visual, {
    double size = 48,
  }) {
    final photo = entry.photo;
    final radius = BorderRadius.circular(12);
    if (photo != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.file(
          photo,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Decode to roughly the size actually painted (2x for crispness on
          // hi-dpi) instead of the full bitmap — without this every visible
          // thumbnail held a full-resolution decode in the image cache.
          cacheWidth: (size * 2).round(),
          cacheHeight: (size * 2).round(),
          // A picked file can disappear from the OS cache before the widget
          // rebuilds; fall back to the icon plate rather than a broken box.
          errorBuilder: (_, __, ___) => _iconPlate(accent, visual, size),
        ),
      );
    }
    return _iconPlate(accent, visual, size);
  }

  Widget _iconPlate(Color accent, WasteTypeVisual visual, double size) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(visual.icon, size: size * 0.44, color: Colors.white),
    );
  }

  Widget _rowAction({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }

  Widget _expandedCard(_WasteEntry entry) {
    final visual = WasteTypeVisual.forName(entry.name);
    final busy = _addingId == entry.id;
    final hasWeight = entry.parsedWeight != null;

    return _AnimatedCardShell(
      accent: visual.color,
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _leadingPlate(entry, visual.color, visual, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.name,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: CaptainTheme.strongText,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : () => _toggleCard(entry),
                icon: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: CaptainTheme.mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: entry.weight,
            autofocus: true,
            enabled: !busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            // Manual entry path: typing takes ownership of the value so the
            // scale stops writing over it, and never auto-opens the camera.
            onChanged: (value) => _onWeightFieldChanged(entry, value),
            // Keyboard "done" on a typed weight commits the row — the manual
            // equivalent of the scale settling, so a no-scale collection is
            // type → done → shoot, with no extra button hunt.
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (entry.parsedWeight != null && !busy) {
                _capturePhotoAndAdd(entry);
              }
            },
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: CaptainTheme.strongText,
            ),
            decoration: InputDecoration(
              hintText: '0.00',
              suffixText: 'kg',
              filled: true,
              fillColor: CaptainTheme.surfaceMuted,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: CaptainTheme.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: CaptainTheme.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: visual.color, width: 1.5),
              ),
            ),
          ),
          // Tells the driver, in one line, whose number is in the field and
          // whether it is frozen — the difference between "the scale is still
          // moving" and "this value is what will be saved".
          if (!entry.isAdded) _weightStatusStrip(entry, visual),
          const SizedBox(height: 12),
          // The camera button *is* the commit: capture and the row is saved.
          // Disabled until there's a weight, so the driver can't shoot a photo
          // that has nothing to attach to.
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: (!busy && hasWeight)
                  ? () => _capturePhotoAndAdd(entry)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: visual.color,
                foregroundColor: Colors.white,
                disabledBackgroundColor: CaptainTheme.surfaceMuted,
                disabledForegroundColor: CaptainTheme.mutedText,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.photo_camera_rounded, size: 19),
              label: Text(
                busy
                    ? 'Saving…'
                    : (hasWeight
                        ? (entry.isAdded
                            ? 'Retake photo to update'
                            : 'Capture photo to add')
                        : 'Enter weight first'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
            ),
          ),
          // Reset stays reachable while editing an already-added row, so the
          // driver isn't forced to commit a change to back out of one.
          if (entry.isAdded) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => _reset(entry),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CaptainTheme.mutedText,
                  side: BorderSide(color: CaptainTheme.hairline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text(
                  'Reset',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _totalBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CaptainTheme.accentSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CaptainTheme.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.scale_rounded, size: 18, color: CaptainTheme.accentDeep),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$_addedCount of ${_entries.length} added',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: CaptainTheme.strongText,
              ),
            ),
          ),
          Text(
            '${_fmt(_total)} kg',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: CaptainTheme.accentDeep,
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitButton() {
    final enabled = _addedCount > 0 && !_submitting;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: CaptainTheme.accentDeep,
          foregroundColor: Colors.white,
          disabledBackgroundColor: CaptainTheme.surfaceMuted,
          disabledForegroundColor: CaptainTheme.mutedText,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                _addedCount == 0 ? 'Add a weight to submit' : 'Submit',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }

  /// One-line state of the weight currently in [entry]'s field.
  Widget _weightStatusStrip(_WasteEntry entry, WasteTypeVisual visual) {
    final hasWeight = entry.parsedWeight != null;

    late final IconData icon;
    late final String text;
    late final Color color;

    if (entry.isLocked && hasWeight) {
      // Reached only via a cancelled camera: `_capturePhotoAndAdd` locks the
      // field the moment it's tapped and keeps that lock even if the driver
      // backs out of the camera without shooting, so a stray scale reading
      // can't quietly change the number under them. Re-tapping capture is
      // still available; typing releases the lock (see
      // `_onWeightFieldChanged`).
      icon = Icons.lock_rounded;
      text = 'Weight locked — tap capture to continue';
      color = visual.color;
    } else if (entry.isManual && hasWeight) {
      icon = Icons.keyboard_rounded;
      text = 'Typed manually — tap capture when done';
      color = CaptainTheme.mutedText;
    } else if (_scaleSupported && _connected) {
      // No auto-lock, no auto-camera: the field keeps tracking the live
      // scale — more waste can still be added to the same load — until the
      // driver explicitly taps "Capture photo to add".
      icon = Icons.scale_rounded;
      text = 'Weighing… tap capture when the weight is final';
      color = CaptainTheme.mutedText;
    } else {
      // No scale (not connected, or iOS): manual entry is the normal path and
      // must not look like a degraded state.
      icon = Icons.keyboard_rounded;
      text = 'Enter the weight, then capture';
      color = CaptainTheme.mutedText;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// Lossless rendering for writing a committed weight BACK into the input
  /// field. Deliberately not [_fmt], which rounds anything >= 10 kg to whole
  /// kilos for display — reusing it here would turn a saved 12.5 kg into a
  /// field reading "12".
  static String _formatWeight(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }
}

/// Shared card chrome with the expand/collapse animation.
///
/// Collapsed rows are given a fixed [height] so the list reads as an even
/// column; the expanded card sizes to its content instead.
class _AnimatedCardShell extends StatelessWidget {
  const _AnimatedCardShell({
    required this.child,
    required this.accent,
    this.onTap,
    this.filled = false,
    this.strongFill = false,
    this.expanded = false,
    this.height,
  });

  final Widget child;
  final Color accent;
  final VoidCallback? onTap;

  /// Tints the card with [accent] instead of the neutral surface.
  final bool filled;

  /// Deepens that tint and the border — used once a weight is recorded, so a
  /// completed card is obvious without losing its stream colour.
  final bool strongFill;
  final bool expanded;

  /// Fixed row height for collapsed cards. Null lets the card size to content
  /// (the expanded state).
  final double? height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(expanded ? 18 : 16);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: height,
      decoration: BoxDecoration(
        color: expanded
            ? CaptainTheme.surface
            : (filled
                ? accent.withValues(alpha: strongFill ? 0.18 : 0.10)
                : CaptainTheme.surfaceMuted),
        borderRadius: radius,
        border: Border.all(
          color: (filled || expanded)
              ? accent.withValues(
                  alpha: expanded ? 0.55 : (strongFill ? 0.7 : 0.32),
                )
              : CaptainTheme.hairline,
          width: expanded ? 1.5 : (strongFill ? 1.5 : 1),
        ),
        boxShadow: expanded ? CaptainTheme.softShadow : const [],
      ),
      // Material+InkWell inside the decorated box so the ripple is clipped to
      // the same rounded rect, without a Material fill painting over the tint.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 14 : 12,
              vertical: expanded ? 14 : 10,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
