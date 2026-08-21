import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
import '../screens/account_loading_screen.dart';
import '../screens/client_dashboard_screen.dart';
import '../screens/client_invitation_acceptance_screen.dart';
import '../screens/client_financial_screens.dart';
import '../screens/client_notification_detail_screen.dart';
import '../screens/client_notification_list_screen.dart';
import '../screens/client_project_detail_screen.dart';
import '../screens/client_project_list_screen.dart';
import '../screens/financial_accounts_screen.dart';
import '../screens/financial_corrections_screen.dart';
import '../screens/inactive_account_screen.dart';
import '../screens/login_screen.dart';
import '../screens/password_reset_request_screen.dart';
import '../screens/password_update_screen.dart';
import '../screens/protected_shell_screen.dart';
import '../screens/owner_admin_documents_screen.dart';
import '../screens/owner_account_transfers_screen.dart';
import '../screens/opening_balances_screen.dart';
import '../screens/owner_client_payments_screen.dart';
import '../screens/owner_currency_exchanges_screen.dart';
import '../screens/owner_clients_projects_screen.dart';
import '../screens/photograph_gallery_screen.dart';
import '../screens/owner_payment_requests_screen.dart';
import '../screens/owner_project_expenses_screen.dart';
import '../screens/owner_activation_screen.dart';
import '../screens/role_home_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final initialLocation = ref.watch(routerInitialLocationProvider);
  final refresh = _RouterRefreshNotifier(ref);
  String? pendingLocation;
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refresh,
    redirect: (context, state) {
      final account = ref.read(currentAccountProvider);
      final redirect = authRedirect(
        ref.read(authSessionProvider),
        account,
        state.uri,
      );
      if (redirect == '/account-loading' &&
          state.uri.path != '/account-loading') {
        pendingLocation = state.uri.toString();
      } else if (state.uri.path == '/account-loading' &&
          redirect == null &&
          account.routeTarget != TrustedAccountRouteTarget.loading &&
          account.routeTarget != TrustedAccountRouteTarget.failure) {
        final target = pendingLocation;
        pendingLocation = null;
        if (target != null) return target;
      } else if (redirect != null && redirect != '/account-loading') {
        pendingLocation = null;
      }
      return redirect;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => rootRedirect(
          ref.read(authSessionProvider),
          ref.read(currentAccountProvider),
        ),
        builder: (context, state) => const AccountLoadingScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const PasswordResetRequestScreen(),
      ),
      GoRoute(
        path: '/update-password',
        builder: (context, state) => const PasswordUpdateScreen(),
      ),
      GoRoute(
        path: '/accept-invitation',
        builder: (context, state) => ClientInvitationAcceptanceScreen(
          token: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: '/owner/activate',
        builder: (context, state) => const OwnerActivationScreen(),
      ),
      GoRoute(
        path: '/inactive-account',
        builder: (context, state) => const InactiveAccountScreen(),
      ),
      GoRoute(
        path: '/account-loading',
        builder: (context, state) => const AccountLoadingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => ProtectedShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/staff',
            builder: (context, state) =>
                const RoleHomeScreen(role: AccountRole.staff),
          ),
          GoRoute(
            path: '/staff/clients',
            builder: (context, state) => const OwnerClientListScreen(),
          ),
          GoRoute(
            path: '/staff/clients/new',
            builder: (context, state) => const OwnerClientFormScreen(),
          ),
          GoRoute(
            path: '/staff/clients/:clientId',
            builder: (context, state) => OwnerClientDetailScreen(
              clientId: state.pathParameters['clientId']!,
            ),
          ),
          GoRoute(
            path: '/staff/clients/:clientId/edit',
            builder: (context, state) => OwnerClientFormScreen(
              clientId: state.pathParameters['clientId']!,
            ),
          ),
          GoRoute(
            path: '/staff/projects',
            builder: (context, state) => const OwnerProjectListScreen(),
          ),
          GoRoute(
            path: '/staff/projects/new',
            builder: (context, state) => OwnerProjectFormScreen(
              initialClientId: state.uri.queryParameters['clientId'],
            ),
          ),
          GoRoute(
            path: '/staff/projects/:projectId',
            builder: (context, state) => OwnerProjectDetailScreen(
              projectId: state.pathParameters['projectId']!,
            ),
          ),
          GoRoute(
            path: '/staff/projects/:projectId/edit',
            builder: (context, state) => OwnerProjectFormScreen(
              projectId: state.pathParameters['projectId']!,
            ),
          ),
          GoRoute(
            path: '/staff/documents',
            builder: (context, state) => const OwnerAdminDocumentsScreen(),
          ),
          GoRoute(
            path: '/staff/photographs',
            builder: (context, state) =>
                const PhotographGalleryScreen.ownerAdmin(),
          ),
          GoRoute(
            path: '/staff/financial-accounts',
            builder: (context, state) => const FinancialAccountsScreen(),
          ),
          GoRoute(
            path: '/staff/financial-accounts/:accountId',
            builder: (context, state) => FinancialAccountDetailScreen(
              accountId: state.pathParameters['accountId']!,
            ),
          ),
          GoRoute(
            path: '/staff/opening-balances',
            builder: (context, state) => const OpeningBalancesScreen(),
          ),
          GoRoute(
            path: '/staff/opening-balances/:eventId',
            builder: (context, state) => OpeningBalanceDetailScreen(
              financialEventId: state.pathParameters['eventId']!,
            ),
          ),
          GoRoute(
            path: '/staff/financial-approval-queue',
            builder: (context, state) => const FinancialApprovalQueueScreen(),
          ),
          GoRoute(
            path: '/staff/financial-reversals',
            builder: (context, state) => const FinancialReversalsScreen(),
          ),
          GoRoute(
            path: '/staff/financial-reversals/:reversalId',
            builder: (context, state) => FinancialReversalDetailScreen(
              financialEventId: state.pathParameters['reversalId']!,
            ),
          ),
          GoRoute(
            path: '/staff/financial-adjustments',
            builder: (context, state) => const FinancialAdjustmentsScreen(),
          ),
          GoRoute(
            path: '/staff/financial-adjustments/:adjustmentId',
            builder: (context, state) => FinancialAdjustmentDetailScreen(
              financialEventId: state.pathParameters['adjustmentId']!,
            ),
          ),
          GoRoute(
            path: '/staff/project-expenses',
            builder: (context, state) => const OwnerProjectExpensesScreen(),
          ),
          GoRoute(
            path: '/staff/project-expenses/:expenseId',
            builder: (context, state) => OwnerProjectExpenseDetailScreen(
              financialEventId: state.pathParameters['expenseId']!,
            ),
          ),
          GoRoute(
            path: '/staff/account-transfers',
            builder: (context, state) => const OwnerAccountTransfersScreen(),
          ),
          GoRoute(
            path: '/staff/account-transfers/:transferId',
            builder: (context, state) => OwnerAccountTransferDetailScreen(
              financialEventId: state.pathParameters['transferId']!,
            ),
          ),
          GoRoute(
            path: '/staff/currency-exchanges',
            builder: (context, state) => const OwnerCurrencyExchangesScreen(),
          ),
          GoRoute(
            path: '/staff/currency-exchanges/:exchangeId',
            builder: (context, state) => OwnerCurrencyExchangeDetailScreen(
              financialEventId: state.pathParameters['exchangeId']!,
            ),
          ),
          GoRoute(
            path: '/staff/client-payments',
            builder: (context, state) => const OwnerClientPaymentsScreen(),
          ),
          GoRoute(
            path: '/staff/client-payments/:paymentId',
            builder: (context, state) => OwnerClientPaymentDetailScreen(
              financialEventId: state.pathParameters['paymentId']!,
            ),
          ),
          GoRoute(
            path: '/staff/payment-requests',
            builder: (context, state) => const OwnerPaymentRequestsScreen(),
          ),
          GoRoute(
            path: '/staff/payment-requests/:requestId',
            builder: (context, state) => OwnerPaymentRequestDetailScreen(
              paymentRequestId: state.pathParameters['requestId']!,
            ),
          ),
          GoRoute(
            path: '/staff/documents/upload',
            builder: (context, state) => const OwnerAdminDocumentUploadScreen(),
          ),
          GoRoute(
            path: '/staff/documents/:documentId',
            builder: (context, state) => OwnerAdminDocumentDetailScreen(
              documentId: state.pathParameters['documentId']!,
            ),
          ),
          GoRoute(
            path: '/client',
            builder: (context, state) => const ClientDashboardScreen(),
          ),
          GoRoute(
            path: '/client/projects',
            builder: (context, state) => const ClientProjectListScreen(),
          ),
          GoRoute(
            path: '/client/projects/:projectId',
            builder: (context, state) => ClientProjectDetailScreen(
              projectId: state.pathParameters['projectId']!,
            ),
          ),
          GoRoute(
            path: '/client/notifications',
            builder: (context, state) => const ClientNotificationListScreen(),
          ),
          GoRoute(
            path: '/client/notifications/:notificationId',
            builder: (context, state) => ClientNotificationDetailScreen(
              notificationId: state.pathParameters['notificationId']!,
            ),
          ),
          GoRoute(
            path: '/client/payments',
            builder: (context, state) => const ClientPaymentsScreen(),
          ),
          GoRoute(
            path: '/client/payments/submit',
            builder: (context, state) => const ClientSubmitPaymentScreen(),
          ),
          GoRoute(
            path: '/client/payments/:paymentId',
            builder: (context, state) => ClientPaymentDetailScreen(
              paymentId: state.pathParameters['paymentId']!,
            ),
          ),
          GoRoute(
            path: '/client/payment-requests',
            builder: (context, state) => const ClientPaymentRequestsScreen(),
          ),
          GoRoute(
            path: '/client/payment-requests/:requestId',
            builder: (context, state) => ClientPaymentRequestDetailScreen(
              requestId: state.pathParameters['requestId']!,
            ),
          ),
          GoRoute(
            path: '/client/photographs',
            builder: (context, state) => const PhotographGalleryScreen.client(),
          ),
        ],
      ),
    ],
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authSessionProvider, (_, _) => notifyListeners());
    ref.listen(currentAccountProvider, (_, _) => notifyListeners());
  }
}

final routerInitialLocationProvider = Provider<String>((ref) => '/');

String? authRedirect(
  AuthSessionState session,
  CurrentAccountState account,
  Uri uri,
) {
  final path = uri.path;
  final isLogin = path == '/login';
  final isPasswordReset = path == '/reset-password';
  final isPasswordUpdate = path == '/update-password';
  final isClientInvitation = path == '/accept-invitation';
  final isOwnerActivation = path == '/owner/activate';
  final isInactive = path == '/inactive-account';
  final isAccountLoading = path == '/account-loading';
  final isActivation = isClientInvitation || isOwnerActivation;
  final isPublic =
      isLogin ||
      isPasswordReset ||
      isPasswordUpdate ||
      isInactive ||
      isActivation;

  if (session.isInitializing) {
    return null;
  }

  if (session.status == AuthSessionStatus.passwordRecovery) {
    return isPasswordUpdate ? null : '/update-password';
  }

  if (!session.isAuthenticated) {
    if (isPublic) {
      return null;
    }
    return '/login';
  }

  if (isActivation) {
    return null;
  }

  final target = account.routeTarget;
  if (target == TrustedAccountRouteTarget.loading ||
      target == TrustedAccountRouteTarget.failure) {
    return isAccountLoading ? null : '/account-loading';
  }

  if (target == TrustedAccountRouteTarget.notProvisioned ||
      target == TrustedAccountRouteTarget.pendingInvite ||
      target == TrustedAccountRouteTarget.suspended ||
      target == TrustedAccountRouteTarget.deactivated ||
      target == TrustedAccountRouteTarget.noActiveRole) {
    return isInactive ? null : '/inactive-account';
  }

  if (isPublic && !isActivation) {
    return defaultHomeFor(account);
  }

  if (path.startsWith('/staff') && target != TrustedAccountRouteTarget.staff) {
    return defaultHomeFor(account);
  }

  if (path.startsWith('/client') &&
      target != TrustedAccountRouteTarget.client) {
    return defaultHomeFor(account);
  }

  return null;
}

String? rootRedirect(AuthSessionState session, CurrentAccountState account) {
  return switch (session.status) {
    AuthSessionStatus.initializing => null,
    AuthSessionStatus.unauthenticated => '/login',
    AuthSessionStatus.passwordRecovery => '/update-password',
    AuthSessionStatus.authenticated => defaultHomeFor(account),
  };
}

String defaultHomeFor(CurrentAccountState account) {
  return switch (account.routeTarget) {
    TrustedAccountRouteTarget.staff => '/staff',
    TrustedAccountRouteTarget.client => '/client',
    TrustedAccountRouteTarget.loading ||
    TrustedAccountRouteTarget.failure => '/account-loading',
    TrustedAccountRouteTarget.notProvisioned ||
    TrustedAccountRouteTarget.pendingInvite ||
    TrustedAccountRouteTarget.suspended ||
    TrustedAccountRouteTarget.deactivated ||
    TrustedAccountRouteTarget.noActiveRole => '/inactive-account',
  };
}
