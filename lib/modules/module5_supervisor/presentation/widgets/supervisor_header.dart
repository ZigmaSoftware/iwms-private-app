import 'package:flutter/material.dart';
import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/env.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// Supervisor header.
class SupervisorHeader extends StatefulWidget {
  const SupervisorHeader({
    super.key,
    required this.name,
    required this.onLogout,
    this.empId,
    this.designation = 'Supervisor',
    this.zoneLabel = '',
    this.zoneCount = 0,
    this.onNotificationsTap,
    this.unreadNotificationCount = 0,
  });

  final String name;
  // Staff unique id (STC-...). Used to fetch the registered attendance face so
  // the avatar shows it instead of the placeholder. Null → placeholder only.
  final String? empId;
  final String designation;
  final String zoneLabel;
  final int zoneCount;
  final VoidCallback onLogout;

  /// When provided, renders a bell icon (in-app notifications + push) next
  /// to the logout button.
  final VoidCallback? onNotificationsTap;
  final int unreadNotificationCount;

  @override
  State<SupervisorHeader> createState() => _SupervisorHeaderState();
}

class _SupervisorHeaderState extends State<SupervisorHeader> {
  static const String _baseUrl = kOperatorProfileBaseUrl;
  String? _imageName;

  @override
  void initState() {
    super.initState();
    _fetchProfileImage();
  }

  @override
  void didUpdateWidget(covariant SupervisorHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empId != widget.empId) {
      _fetchProfileImage();
    }
  }

  Future<void> _fetchProfileImage() async {
    final empId = widget.empId?.trim() ?? '';
    if (empId.isEmpty) return;
    try {
      final dio = await authorizedDio();
      final response = await dio.get(
        '${ApiConfig.attendanceBase}staff-profile/',
        queryParameters: {'staff_id_id': empId},
      );
      final json = response.data;
      if (json is Map && json['status'] == 'success') {
        final data = json['data'];
        // Prefer the face registered for attendance; fall back to an
        // admin-uploaded staff photo.
        final registered = data?['attendance_reg_image']?.toString() ?? '';
        final staffPhoto = data?['photo']?.toString() ?? '';
        final resolved = registered.isNotEmpty ? registered : staffPhoto;
        if (!mounted) return;
        setState(() => _imageName = resolved.isNotEmpty ? resolved : null);
      }
    } catch (_) {
      // Non-fatal: keep the placeholder avatar.
    }
  }

  String _convertToUrl(String path) {
    final clean = path.replaceAll('\\', '/');
    // Already an absolute URL → use as-is.
    if (clean.startsWith('http')) return clean;
    // The API serializes ImageFields to their `.url` (e.g. "/media/..."), so it
    // already carries the /media/ prefix — just join to the origin. Only a bare
    // relative path (no leading slash) needs /media/ added.
    if (clean.startsWith('/')) return '$_baseUrl$clean';
    return '$_baseUrl/media/$clean';
  }

  String _toTitleCase(String s) => s
      .split(' ')
      .map((w) => w.isEmpty
          ? ''
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');

  // String _greeting() {
  //   final hour = DateTime.now().hour;
  //   if (hour < 12) return 'Good morning';
  //   if (hour < 17) return 'Good afternoon';
  //   return 'Good evening';
  // }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: SupervisorTheme.surface,
        boxShadow: SupervisorTheme.softShadow,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _avatar(),
                  const SizedBox(width: 12),
                  Expanded(child: _identitySection()),
                  if (widget.onNotificationsTap != null) _notificationsButton(),
                  _logoutButton(),
                ],
              ),
              const SizedBox(height: 10),
              _zoneStrip(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar() {
    final image = _imageName;
    return CircleAvatar(
      radius: 23,
      backgroundColor: SupervisorTheme.surface,
      child: ClipOval(
        child: (image != null && image.isNotEmpty)
            ? Image.network(
                _convertToUrl(image),
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                // Fall back to the placeholder if the image fails to load.
                errorBuilder: (_, __, ___) => _placeholderAvatar(),
              )
            : _placeholderAvatar(),
      ),
    );
  }

  Widget _placeholderAvatar() {
    return Image.asset(
      'assets/icons/profile_s.png',
      width: 46,
      height: 46,
      fit: BoxFit.cover,
    );
  }

  Widget _identitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _toTitleCase(widget.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 17,
            color: SupervisorTheme.strongText,
            fontWeight: FontWeight.w700,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            const Icon(Icons.shield_outlined,
                color: SupervisorTheme.warning, size: 12),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                widget.designation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SupervisorTheme.mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _notificationsButton() {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            tooltip: 'Notifications',
            onPressed: widget.onNotificationsTap,
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: SupervisorTheme.strongText,
              size: 22,
            ),
          ),
          if (widget.unreadNotificationCount > 0)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SupervisorTheme.surface, width: 1),
                ),
                child: Text(
                  widget.unreadNotificationCount > 9
                      ? '9+'
                      : '${widget.unreadNotificationCount}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _logoutButton() {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: 'Logout',
        onPressed: widget.onLogout,
        icon: const Icon(
          Icons.logout_rounded,
          color: SupervisorTheme.strongText,
          size: 22,
        ),
      ),
    );
  }

  Widget _zoneStrip() {
    final label = widget.zoneLabel.trim().isNotEmpty
        ? widget.zoneLabel
        : (widget.zoneCount > 0
            ? '${widget.zoneCount} zone${widget.zoneCount == 1 ? '' : 's'} assigned'
            : 'No zones assigned');
    return Row(
      children: [
        const Icon(Icons.map_outlined, color: SupervisorTheme.accent, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SupervisorTheme.strongText,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: SupervisorTheme.success,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'On Duty',
          style: TextStyle(
            color: SupervisorTheme.success,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}
