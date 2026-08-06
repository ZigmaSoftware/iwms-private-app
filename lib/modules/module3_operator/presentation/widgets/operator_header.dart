import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iwms_private_app/core/api_config.dart';
import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/core/env.dart';
import 'package:iwms_private_app/data/repositories/auth_repository.dart';
import 'package:iwms_private_app/modules/module3_operator/presentation/screens/attendance/profile.dart';
import 'package:iwms_private_app/modules/module3_operator/presentation/theme/operator_theme.dart';

/// Operator header — charcoal slate top section with the avatar/Register
/// button anchored on the LEFT and identity (name, ID, designation, ward)
/// stacked to its right. Designed to be compact and information-dense:
/// no wasted gradient real estate, no floating subtitle.
class OperatorHeader extends StatefulWidget {
  const OperatorHeader({
    super.key,
    required this.name,
    required this.empId,
    this.displayId,
    required this.badge,
    required this.ward,
    required this.zone,
    required this.onLogout,
    this.onMenuTap,
    this.subtitle,
    this.designation,
    this.showAvatar = false,
  });

  final String name;
  final String badge;
  final String ward;
  final String zone;
  final String empId;
  final String? displayId;
  final String? subtitle;
  final String? designation;
  final VoidCallback onLogout;
  final VoidCallback? onMenuTap;
  final bool showAvatar;

  @override
  State<OperatorHeader> createState() => _OperatorHeaderState();
}

class _OperatorHeaderState extends State<OperatorHeader> {
  static const String _baseUrl = kOperatorProfileBaseUrl;
  bool hasProfile = false;
  bool imageLoading = true;
  String? imageName;

  @override
  void initState() {
    super.initState();
    fetchEmployeeImage();
  }

  Future<void> fetchEmployeeImage() async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(
            Uri.parse('${ApiConfig.attendanceBase}staff-profile/').replace(
              queryParameters: {'staff_id_id': widget.empId},
            ),
          )
          .timeout(const Duration(seconds: 5));
      final token = await _getAuthToken();
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);

      if (json["status"] == "success") {
        if (!mounted) return;
        setState(() {
          imageName = json["data"]["photo"] ?? "";
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
    } finally {
      client.close(force: true);
    }
  }

  String _convertToUrl(String path) {
    final clean = path.replaceAll("\\", "/");
    return "$_baseUrl/media/$clean";
  }

  String _toTitleCase(String s) {
    return s
        .split(" ")
        .map((w) => w.isEmpty
            ? ""
            : "${w[0].toUpperCase()}${w.substring(1).toLowerCase()}")
        .join(" ");
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<String?> _getAuthToken() async {
    final authRepo = getIt<AuthRepository>();
    final user = await authRepo.getAuthenticatedUser();
    final token = user?.authToken?.trim();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  @override
  Widget build(BuildContext context) {
    final displayId =
        (widget.displayId != null && widget.displayId!.trim().isNotEmpty)
            ? widget.displayId!
            : widget.empId;
    final designation = (widget.designation?.trim().isNotEmpty == true)
        ? widget.designation!
        : 'Field Operator';

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: OperatorTheme.headerGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 30, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildAvatarButton(),
                  const SizedBox(width: 11),
                  Expanded(
                      child: _buildIdentitySection(displayId, designation)),
                  const SizedBox(width: 8),
                  _greetingPill(),
                ],
              ),
              if (widget.ward.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                _wardStrip(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _greetingPill() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wb_sunny_rounded,
                  color: OperatorTheme.accent, size: 12),
              const SizedBox(width: 4),
              Text(
                _greeting(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _logoutButton(),
      ],
    );
  }

  Widget _logoutButton() {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.logout_rounded,
            color: Colors.white, size: 18),
        onPressed: widget.onLogout,
        tooltip: 'Logout',
      ),
    );
  }

  Widget _buildIdentitySection(String displayId, String designation) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _toTitleCase(widget.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1.12,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            const Icon(Icons.work_outline_rounded,
                color: Color.fromARGB(255, 242, 158, 31), size: 11),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                designation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: OperatorTheme.accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(7),
            border:
                Border.all(color: OperatorTheme.accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.badge_outlined,
                  color: OperatorTheme.accent, size: 10),
              const SizedBox(width: 4),
              Text(
                displayId,
                style: const TextStyle(
                  color: OperatorTheme.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wardStrip() {
    final parts = <String>[
      if (widget.ward.trim().isNotEmpty) widget.ward,
      if (widget.zone.trim().isNotEmpty) widget.zone,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded,
              color: OperatorTheme.accent, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join('  •  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: OperatorTheme.success,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'On Duty',
            style: TextStyle(
              color: OperatorTheme.success,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarButton() {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfilePage(empId: widget.empId),
          ),
        );
        fetchEmployeeImage();
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [OperatorTheme.accent, OperatorTheme.accentDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: OperatorTheme.accent.withValues(alpha: 0.28),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(2),
        child: CircleAvatar(
          radius: 23,
          backgroundColor: Colors.white,
          backgroundImage: (hasProfile && imageName != null)
              ? NetworkImage(_convertToUrl(imageName!))
              : null,
          child: imageLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: OperatorTheme.primary,
                  ),
                )
              : (!hasProfile)
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.person_add_alt_1_rounded,
                            size: 18, color: OperatorTheme.primary),
                        Text(
                          'Register',
                          style: TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w800,
                            color: OperatorTheme.primary,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    )
                  : null,
        ),
      ),
    );
  }
}
