/// ALOQA — go_router configuration.
///
/// Routes (TZ §7.2): splash, onboarding, login, home, lobby, conference,
/// settings, profile. Auth status gates protected routes; the router refreshes
/// when auth changes via a ChangeNotifier bridge.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/billing/billing_screen.dart';
import '../../features/contacts/contacts_screen.dart';
import '../../features/employees/employees_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/meeting/join_meeting_screen.dart';
import '../../features/meeting/lobby_screen.dart';
import '../../features/meeting/meeting_manage_screen.dart';
import '../../features/meeting/new_meeting_screen.dart';
import '../../features/meeting/schedule_screen.dart';
import '../../features/messages/messages_screen.dart';
import '../../features/recordings/recordings_screen.dart';
import '../../features/settings/profile_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/webinar/webinar_registration_screen.dart';

/// Bridges Riverpod auth state into a Listenable for go_router refresh.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;

      // While auth is unknown, keep the user on splash.
      if (auth.status == AuthStatus.unknown) {
        return loc == '/splash' ? null : '/splash';
      }

      final loggedIn = auth.status == AuthStatus.authenticated;
      final isPublic = loc == '/splash' ||
          loc == '/onboarding' ||
          loc == '/login' ||
          loc == '/register' ||
          loc == '/forgot' ||
          loc.startsWith('/w/');

      // Logged-in user shouldn't sit on auth/splash screens.
      if (loggedIn && isPublic) return '/home';

      // Guests can't reach protected screens.
      if (!loggedIn && !isPublic) return '/onboarding';

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/new',
        builder: (_, __) => const NewMeetingScreen(),
      ),
      GoRoute(
        path: '/join',
        builder: (_, __) => const JoinMeetingScreen(),
      ),
      GoRoute(
        path: '/schedule',
        builder: (_, __) => const ScheduleScreen(),
      ),
      GoRoute(
        path: '/recordings',
        builder: (_, __) => const RecordingsScreen(),
      ),
      GoRoute(
        path: '/messages',
        builder: (_, __) => const MessagesScreen(),
      ),
      GoRoute(
        path: '/contacts',
        builder: (_, __) => const ContactsScreen(),
      ),
      GoRoute(
        path: '/billing',
        builder: (_, __) => const BillingScreen(),
      ),
      GoRoute(
        path: '/employees',
        builder: (_, __) => const EmployeesScreen(),
      ),
      GoRoute(
        path: '/meeting/:id',
        builder: (_, state) =>
            MeetingManageScreen(meetingId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/lobby/:id',
        builder: (_, state) =>
            LobbyScreen(meetingId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/forgot',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/w/:code',
        builder: (_, state) =>
            WebinarRegistrationScreen(code: state.pathParameters['code'] ?? ''),
      ),
    ],
  );
});
