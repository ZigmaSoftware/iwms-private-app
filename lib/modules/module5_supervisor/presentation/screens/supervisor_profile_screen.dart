import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:iwms_citizen_app/core/api_config.dart';
import 'package:iwms_citizen_app/core/network/authorized_dio.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/logic/supervisor_bloc.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_cards.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_header.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_visuals.dart';

class SupervisorProfileScreen extends StatefulWidget {
  const SupervisorProfileScreen({
    super.key,
    required this.name,
    required this.onLogout,
    this.empId,
  });

  final String name;
  final String? empId;
  final VoidCallback onLogout;

  @override
  State<SupervisorProfileScreen> createState() =>
      _SupervisorProfileScreenState();
}

class _SupervisorProfileScreenState extends State<SupervisorProfileScreen> {
  bool _loading = true;
  String? _designation;
  String? _department;
  String? _mobile;
  String? _email;
  String? _employeeId;
  String? _joinedOn;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void didUpdateWidget(covariant SupervisorProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empId != widget.empId) {
      _fetchProfile();
    }
  }

  Future<void> _fetchProfile() async {
    if ((widget.empId ?? '').trim().isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final dio = await authorizedDio();
      final response = await dio.get(
        '${ApiConfig.attendanceBase}staff-profile/',
        queryParameters: {'staff_id_id': widget.empId},
      );
      final json = response.data;
      if (!mounted) return;
      if (json is Map && json['status'] == 'success') {
        final data = json['data'] as Map?;
        final personal = data?['personal'] as Map?;
        setState(() {
          _designation = data?['designation']?.toString();
          _department = data?['department']?.toString();
          _mobile = personal?['contact_mobile']?.toString();
          _email = personal?['contact_email']?.toString();
          _employeeId = data?['emp_id']?.toString();
          _joinedOn = data?['doj']?.toString();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SupervisorTheme.background,
      child: BlocBuilder<SupervisorBloc, SupervisorState>(
        builder: (context, state) {
          return Column(
            children: [
              SupervisorHeader(
                name: widget.name,
                empId: widget.empId,
                onLogout: widget.onLogout,
                zoneLabel: state.scopeLabel,
                zoneCount: state.scope.zoneIds.length,
              ),
              Expanded(
                child: SupervisorPatternBackground(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      20,
                      16,
                      20,
                      MediaQuery.viewPaddingOf(context).bottom + 200,
                    ),
                    children: [
                      _profileCard(),
                      const SizedBox(height: 16),
                      _zoneCard(state),
                      const SizedBox(height: 16),
                      _logoutButton(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _profileCard() {
    return SupervisorInfoCard(
      title: 'Profile',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: CircularProgressIndicator(
                  color: SupervisorTheme.accent,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow(
                    Icons.badge_outlined,
                    'Employee ID',
                    _employeeId?.trim().isNotEmpty == true
                        ? _employeeId!
                        : 'Not available'),
                _detailRow(
                    Icons.shield_outlined,
                    'Designation',
                    _designation?.trim().isNotEmpty == true
                        ? _designation!
                        : 'Supervisor'),
                _detailRow(
                    Icons.apartment_rounded,
                    'Department',
                    _department?.trim().isNotEmpty == true
                        ? _department!
                        : 'Not available'),
                _detailRow(
                    Icons.phone_outlined,
                    'Mobile',
                    _mobile?.trim().isNotEmpty == true
                        ? _mobile!
                        : 'Not available'),
                _detailRow(
                    Icons.mail_outline_rounded,
                    'Email',
                    _email?.trim().isNotEmpty == true
                        ? _email!
                        : 'Not available'),
                _detailRow(
                    Icons.calendar_today_outlined,
                    'Joined on',
                    _joinedOn?.trim().isNotEmpty == true
                        ? _joinedOn!
                        : 'Not available'),
              ],
            ),
    );
  }

  Widget _zoneCard(SupervisorState state) {
    final scopeLabel = state.scopeLabel;
    return SupervisorInfoCard(
      title: 'Area scope',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow(Icons.map_outlined, 'Area',
              scopeLabel.isNotEmpty ? scopeLabel : 'Not assigned'),
          if (state.scope.zoneIds.isNotEmpty)
            _detailRow(
              Icons.tag_rounded,
              'Zone IDs',
              state.scope.zoneIds.join(', '),
            ),
          _detailRow(Icons.route_rounded, 'Trips today', '${state.kpis.total}'),
          _detailRow(
            Icons.local_shipping_outlined,
            'In progress',
            '${state.kpis.inProgress}',
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: SupervisorTheme.mutedText),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: SupervisorTheme.mutedText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: SupervisorTheme.strongText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: widget.onLogout,
        style: ElevatedButton.styleFrom(
          backgroundColor: SupervisorTheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: SupervisorTheme.cardRadius,
          ),
        ),
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
