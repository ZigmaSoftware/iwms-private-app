import 'package:flutter/material.dart';
import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/env.dart';
import 'package:iwms_private_app/core/network/authorized_dio.dart';
import 'package:iwms_private_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_private_app/modules/module3_operator/presentation/screens/attendance/profile.dart';

/// Captain header — a minimal identity bar.
///
/// Redesigned to the Captain look: a slim royal-navy gradient strip carrying
/// only the essentials — a tappable avatar (doubles as the face-registration
/// entry point), the driver's name, and a logout affordance. The old
/// "Good morning" greeting, designation line and ID badge were dropped to keep
/// it clean and give the screen below more room.
///
/// On the Map tab the header tucks into a razor-thin bar ([collapsed] = true)
/// so the map gets almost the full height; it animates back to full size on
/// every other tab.
class DriverHeader extends StatefulWidget {
  const DriverHeader({
    super.key,
    required this.name,
    required this.empId,
    required this.onLogout,
    this.displayId,
    this.designation,
    this.locationLabel,
    this.onProfileTap,
    this.onDangerTap,
    this.onNotificationsTap,
    this.unreadNotificationCount = 0,
    this.collapsed = false,
  });

  final String name;
  final String empId;
  final String? displayId;
  final String? designation;

  /// Service area for the driver's current trip (panchayat / ward / last
  /// geographic hierarchy level). Shown under the name when available.
  final String? locationLabel;
  final VoidCallback onLogout;
  final VoidCallback? onProfileTap;

  /// When provided, renders a danger/report button (vehicle breakdown, extra
  /// staff, emergency, ...) next to the logout button.
  final VoidCallback? onDangerTap;

  /// When provided, renders a notifications bell (vehicle replacement
  /// approval/rejection, team changes, substitutions) with an unread badge.
  final VoidCallback? onNotificationsTap;
  final int unreadNotificationCount;

  /// When true the header renders as a slim tucked bar (used on the Map tab
  /// to maximise map visibility).
  final bool collapsed;

  @override
  State<DriverHeader> createState() => _DriverHeaderState();
}

class _DriverHeaderState extends State<DriverHeader> {
  static const String _baseUrl = kOperatorProfileBaseUrl;
  bool hasProfile = false;
  bool imageLoading = true;
  String? imageName;

  @override
  void initState() {
    super.initState();
    _fetchEmployeeImage();
  }

  Future<void> _fetchEmployeeImage() async {
    if (widget.empId.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        hasProfile = false;
        imageLoading = false;
      });
      return;
    }
    try {
      final dio = await authorizedDio();
      final response = await dio.get(
        '${ApiConfig.attendanceBase}staff-profile/',
        queryParameters: {'staff_id_id': widget.empId},
      );
      final json = response.data;
      if (json is Map && json['status'] == 'success') {
        if (!mounted) return;
        final data = json['data'];
        // Prefer the face registered for attendance; fall back to an
        // admin-uploaded staff photo when no face has been registered.
        final registered = data?['attendance_reg_image']?.toString() ?? '';
        final staffPhoto = data?['photo']?.toString() ?? '';
        setState(() {
          imageName = registered.isNotEmpty ? registered : staffPhoto;
          hasProfile = imageName != null && imageName!.isNotEmpty;
          imageLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          hasProfile = false;
          imageLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        hasProfile = false;
        imageLoading = false;
      });
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

  String _toTitleCase(String s) {
    return s
        .split(' ')
        .map((w) => w.isEmpty
            ? ''
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: CaptainTheme.headerGradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
        boxShadow: CaptainTheme.softShadow,
      ),
      child: SafeArea(
        bottom: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          padding: widget.collapsed
              ? const EdgeInsets.fromLTRB(14, 6, 12, 6)
              : const EdgeInsets.fromLTRB(16, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _buildAvatarButton(compact: widget.collapsed),
                  const SizedBox(width: 11),
                  Expanded(child: _buildIdentity(compact: widget.collapsed)),
                  const SizedBox(width: 8),
                  if (widget.onNotificationsTap != null) ...[
                    _notificationsButton(compact: widget.collapsed),
                    const SizedBox(width: 8),
                  ],
                  if (widget.onDangerTap != null) ...[
                    _dangerButton(compact: widget.collapsed),
                    const SizedBox(width: 8),
                  ],
                  _logoutButton(compact: widget.collapsed),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentity({required bool compact}) {
    final location = widget.locationLabel?.trim();
    final hasLocation =
        location != null && location.isNotEmpty && location != '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact)
          Text(
            'Captain',
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        if (!compact) const SizedBox(height: 2),
        Text(
          _toTitleCase(widget.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 14 : 18,
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        if (hasLocation) ...[
          SizedBox(height: compact ? 1 : 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_rounded,
                size: compact ? 11 : 13,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10.5 : 12.5,
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _notificationsButton({required bool compact}) {
    final double d = compact ? 32 : 38;
    return SizedBox(
      width: d,
      height: d,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.12),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.notifications_none_rounded,
                  color: Colors.white, size: compact ? 16 : 18),
              onPressed: widget.onNotificationsTap,
              tooltip: 'Notifications',
            ),
          ),
          if (widget.unreadNotificationCount > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 1),
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

  Widget _dangerButton({required bool compact}) {
    final double d = compact ? 32 : 38;
    return SizedBox(
      width: d,
      height: d,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Image.asset(
            'assets/icons/warning.png',
            width: compact ? 16 : 18,
            height: compact ? 16 : 18,
          ),
          onPressed: widget.onDangerTap,
          tooltip: 'Report an issue',
        ),
      ),
    );
  }

  Widget _logoutButton({required bool compact}) {
    final double d = compact ? 32 : 38;
    return SizedBox(
      width: d,
      height: d,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(Icons.logout_rounded,
              color: Colors.white, size: compact ? 16 : 18),
          onPressed: widget.onLogout,
          tooltip: 'Logout',
        ),
      ),
    );
  }

  Widget _buildAvatarButton({required bool compact}) {
    final double outer = compact ? 34 : 50;
    final double radius = compact ? 15 : 23;
    return GestureDetector(
      onTap: () async {
        // Not registered yet: the avatar reads "Register", so open the employee
        // face-registration page — the same ProfilePage the (deprecated)
        // operator module opens from its Register avatar, which shows the
        // "Register Selfie" capture flow. Once a face/profile exists, continue
        // to the driver profile.
        if (!hasProfile && !imageLoading) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfilePage(empId: widget.empId),
            ),
          );
          await _fetchEmployeeImage();
          if (hasProfile && mounted && widget.onProfileTap != null) {
            widget.onProfileTap!();
          }
          return;
        }

        if (widget.onProfileTap != null) {
          widget.onProfileTap!();
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfilePage(empId: widget.empId),
          ),
        );
        _fetchEmployeeImage();
      },
      child: Container(
        width: outer,
        height: outer,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [CaptainTheme.accent, CaptainTheme.accentDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: CaptainTheme.accent.withValues(alpha: 0.28),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(2),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: Colors.white,
          backgroundImage: (hasProfile && imageName != null)
              ? NetworkImage(_convertToUrl(imageName!))
              : null,
          child: imageLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CaptainTheme.primary,
                  ),
                )
              : (!hasProfile)
                  ? (compact
                      ? Icon(Icons.person_rounded,
                          size: 16, color: CaptainTheme.primary)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add_alt_1_rounded,
                                size: 18, color: CaptainTheme.primary),
                            Text(
                              'Register',
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.w800,
                                color: CaptainTheme.primary,
                              ),
                            ),
                          ],
                        ))
                  : null,
        ),
      ),
    );
  }
}
