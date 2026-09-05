import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:iwms_private_app/core/di.dart';
import 'package:iwms_private_app/core/permissions/app_screens.dart';
import 'package:iwms_private_app/core/permissions/feature_access.dart';
import 'package:iwms_private_app/logic/auth/auth_bloc.dart';
import 'package:iwms_private_app/logic/auth/auth_event.dart';
import 'package:iwms_private_app/logic/auth/auth_state.dart';
import 'package:iwms_private_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_private_app/modules/module5_supervisor/logic/supervisor_bloc.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/attendance/supervisor_attendance_page.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_attendance_screen.dart'
    as attendance;
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_home_page.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_profile_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/screens/supervisor_trips_screen.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_private_app/modules/module5_supervisor/presentation/widgets/supervisor_animated_nav_bar.dart';

/// Tabs surfaced in the supervisor shell.
/// The 4 nav slots are: Dashboard / Trips / Attendance / Profile.
enum SupervisorNavTab { dashboard, trips, attendance, profile }

class MainSupervisorTabBar extends StatelessWidget {
  const MainSupervisorTabBar({
    super.key,
    this.initialTab = SupervisorNavTab.dashboard,
  });

  final SupervisorNavTab initialTab;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SupervisorBloc>(
      create: (_) => SupervisorBloc(repository: getIt<SupervisorRepository>())
        ..add(const SupervisorLoadRequested()),
      child: _SupervisorShell(initialTab: initialTab),
    );
  }
}

class _SupervisorShell extends StatefulWidget {
  const _SupervisorShell({required this.initialTab});

  final SupervisorNavTab initialTab;

  @override
  State<_SupervisorShell> createState() => _SupervisorShellState();
}

class _SupervisorShellState extends State<_SupervisorShell> {
  /// Every slot the shell can show, with the app screen that unlocks it.
  /// Profile is unconditional — a signed-in user can always reach their own
  /// profile and sign out, whatever else they were granted.
  static const _tabScreens = <SupervisorNavTab, String?>{
    SupervisorNavTab.dashboard: AppScreens.supervisorDashboard,
    SupervisorNavTab.trips: AppScreens.supervisorTrips,
    SupervisorNavTab.attendance: AppScreens.supervisorAttendance,
    SupervisorNavTab.profile: null,
  };

  late SupervisorNavTab _activeTab = widget.initialTab;

  /// Always the full 4 tabs. [SupervisorAnimatedNavBar] is a fixed 4-slot
  /// layout with a hard assertion on that count, not a list that can shrink —
  /// filtering it by grant used to crash the shell outright the moment one
  /// screen (e.g. Attendance) wasn't granted. [_buildTab] shows a "no access"
  /// placeholder in the body instead of hiding the slot.
  List<SupervisorNavTab> get _slotTabs => _tabScreens.keys.toList();

  void _setTab(SupervisorNavTab tab) {
    if (_activeTab == tab) return;
    setState(() => _activeTab = tab);
  }

  void _logout() {
    context.read<AuthBloc>().add(AuthLogoutRequested());
  }

  void _openTeam() {
    // Push the read-only team roster, sharing the existing SupervisorBloc.
    final bloc = context.read<SupervisorBloc>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider<SupervisorBloc>.value(
          value: bloc,
          child: Scaffold(
            backgroundColor: SupervisorTheme.background,
            appBar: AppBar(
              backgroundColor: SupervisorTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              title: const Text('Team on duty'),
            ),
            body: const attendance.SupervisorAttendanceScreen(),
          ),
        ),
      ),
    );
  }

  String _identityName() {
    final state = context.read<AuthBloc>().state;
    if (state is AuthStateAuthenticated) {
      return state.userName.trim().isNotEmpty ? state.userName : 'Supervisor';
    }
    return 'Supervisor';
  }

  /// Supervisor's staff unique id (STC-...), used to fetch the registered
  /// attendance face for the header avatar.
  String? _identityEmpId() {
    final state = context.read<AuthBloc>().state;
    if (state is AuthStateAuthenticated) {
      return state.emp_id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final name = _identityName();

    final slots = _slotTabs;
    final navItems = slots.map(_navItemFor).toList();

    // A tab the user has lost access to (permissions changed while they were
    // signed in) must not leave the shell pointing at nothing.
    if (!slots.contains(_activeTab)) {
      _activeTab = slots.first;
    }
    final activeSlot = slots.indexOf(_activeTab).clamp(0, slots.length - 1);

    return WillPopScope(
      onWillPop: () async {
        final home = slots.first;
        if (_activeTab != home) {
          _setTab(home);
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: SupervisorTheme.background,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) {
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<SupervisorNavTab>(_activeTab),
              child: _buildTab(name),
            ),
          ),
        ),
        bottomNavigationBar: SupervisorAnimatedNavBar(
          activeIndex: activeSlot,
          items: navItems,
          onTabSelected: (index) => _setTab(slots[index]),
        ),
      ),
    );
  }

  SupervisorNavItem _navItemFor(SupervisorNavTab tab) {
    switch (tab) {
      case SupervisorNavTab.dashboard:
        return const SupervisorNavItem(
          icon: Icons.dashboard_rounded,
          label: 'Dashboard',
        );
      case SupervisorNavTab.trips:
        return const SupervisorNavItem(
          icon: Icons.local_shipping_rounded,
          label: 'Trips',
        );
      case SupervisorNavTab.attendance:
        return const SupervisorNavItem(
          icon: Icons.fingerprint_rounded,
          label: 'Attendance',
        );
      case SupervisorNavTab.profile:
        return const SupervisorNavItem(
          icon: Icons.person_rounded,
          label: 'Profile',
          iconAsset: 'assets/icons/profile_s.png',
        );
    }
  }

  Widget _buildTab(String name) {
    final empId = _identityEmpId();
    final requiredScreen = _tabScreens[_activeTab];
    if (requiredScreen != null && !context.canSeeScreen(requiredScreen)) {
      return _NoAccessTab(tabLabel: _navItemFor(_activeTab).label);
    }

    switch (_activeTab) {
      case SupervisorNavTab.dashboard:
        return SupervisorHomePage(
          name: name,
          empId: empId,
          onLogout: _logout,
          onOpenTrips: () => _setTab(SupervisorNavTab.trips),
          onOpenTeam: _openTeam,
        );
      case SupervisorNavTab.trips:
        return const SupervisorTripsScreen();
      case SupervisorNavTab.attendance:
        return SupervisorAttendancePage(name: name);
      case SupervisorNavTab.profile:
        return SupervisorProfileScreen(
          name: name,
          empId: empId,
          onLogout: _logout,
        );
    }
  }
}

/// Shown in place of a tab's real content when the signed-in supervisor has
/// not been granted the screen behind it. The nav slot itself always stays —
/// [SupervisorAnimatedNavBar] is a fixed 4-slot layout — so only the body
/// changes.
class _NoAccessTab extends StatelessWidget {
  const _NoAccessTab({required this.tabLabel});

  final String tabLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SupervisorTheme.background,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 40,
            color: SupervisorTheme.mutedText,
          ),
          const SizedBox(height: 12),
          Text(
            "You don't have access to $tabLabel.",
            textAlign: TextAlign.center,
            style: TextStyle(color: SupervisorTheme.mutedText, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Ask your administrator to grant it in Staff Access Configuration.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: SupervisorTheme.mutedText.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
