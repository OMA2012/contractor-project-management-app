import 'dart:async';

import 'package:contractor_project_management/src/account/current_account.dart';
import 'package:contractor_project_management/src/account/current_account_provider.dart';
import 'package:contractor_project_management/src/account/current_account_repository.dart';
import 'package:contractor_project_management/src/auth/auth_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps no row to not provisioned', () async {
    final container = containerFor(<Map<String, dynamic>>[]);
    addTearDown(container.dispose);

    container.read(currentAccountProvider);
    await pumpProvider();

    expect(
      container.read(currentAccountProvider),
      isA<CurrentAccountNotProvisioned>(),
    );
  });

  test('maps invited, suspended and disabled account states', () async {
    expect(
      await stateFor(status: 'INVITED'),
      isA<CurrentAccountPendingInvite>(),
    );
    expect(await stateFor(status: 'SUSPENDED'), isA<CurrentAccountSuspended>());
    expect(
      await stateFor(status: 'DISABLED'),
      isA<CurrentAccountDeactivated>(),
    );
  });

  test('maps active with no valid role to no active role', () async {
    final state = await stateFor(status: 'ACTIVE', accessAllowed: false);

    expect(state, isA<CurrentAccountNoActiveRole>());
  });

  test('maps valid active staff and client accounts', () async {
    final staff = await stateFor(
      status: 'ACTIVE',
      userType: 'STAFF',
      roles: ['owner_admin'],
    );
    final client = await stateFor(
      status: 'ACTIVE',
      userType: 'CLIENT',
      roles: ['client'],
    );

    expect(staff, isA<CurrentAccountLoaded>());
    expect(client, isA<CurrentAccountLoaded>());
  });

  test('maps rpc failure to retryable failure', () async {
    final container = ProviderContainer(
      overrides: [
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.authenticated(email: 'person@example.com'),
        ),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(
            rpc: (_) async => throw StateError('offline'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      currentAccountProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await pumpProvider();

    expect(
      container.read(currentAccountProvider),
      isA<CurrentAccountFailure>(),
    );
  });

  test('ignores old result after sign-out', () async {
    final firstLoad = Completer<dynamic>();
    final container = ProviderContainer(
      overrides: [
        initialAuthSessionProvider.overrideWithValue(
          const AuthSessionState.authenticated(
            authUserId: '00000000-0000-0000-0000-000000000201',
            email: 'a@example.test',
          ),
        ),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(rpc: (_) => firstLoad.future),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      currentAccountProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await pumpProvider();
    container.read(currentAccountProvider.notifier).clear();
    firstLoad.complete(activeRowFor('STAFF', ['owner_admin']));
    await pumpProvider();

    expect(
      container.read(currentAccountProvider),
      isA<CurrentAccountNotProvisioned>(),
    );
  });

  test('ignores user A result after session changes to user B', () async {
    final source = ControlledAuthSessionSource(
      AuthSessionSnapshot(
        authUserId: '00000000-0000-0000-0000-000000000201',
        email: 'a@example.test',
      ),
    );
    final firstLoad = Completer<dynamic>();
    final secondLoad = Completer<dynamic>();
    var call = 0;
    final container = ProviderContainer(
      overrides: [
        authSessionSourceProvider.overrideWithValue(source),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(
            rpc: (_) {
              call++;
              return call == 1 ? firstLoad.future : secondLoad.future;
            },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      currentAccountProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await pumpProvider();
    source.emitSignedIn(
      const AuthSessionSnapshot(
        authUserId: '00000000-0000-0000-0000-000000000202',
        email: 'b@example.test',
      ),
    );
    await pumpProvider();
    firstLoad.complete(activeRowFor('STAFF', ['owner_admin']));
    await pumpProvider();

    expect(
      container.read(currentAccountProvider),
      isA<CurrentAccountLoading>(),
    );
  });

  test(
    'newer user B result remains after older user A completes later',
    () async {
      final source = ControlledAuthSessionSource(
        AuthSessionSnapshot(
          authUserId: '00000000-0000-0000-0000-000000000201',
          email: 'a@example.test',
        ),
      );
      final firstLoad = Completer<dynamic>();
      final secondLoad = Completer<dynamic>();
      var call = 0;
      final container = ProviderContainer(
        overrides: [
          authSessionSourceProvider.overrideWithValue(source),
          currentAccountRepositoryProvider.overrideWithValue(
            CurrentAccountRepository(
              rpc: (_) {
                call++;
                return call == 1 ? firstLoad.future : secondLoad.future;
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        currentAccountProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await pumpProvider();
      source.emitSignedIn(
        const AuthSessionSnapshot(
          authUserId: '00000000-0000-0000-0000-000000000202',
          email: 'b@example.test',
        ),
      );
      await pumpProvider();
      secondLoad.complete(activeRowFor('CLIENT', ['client']));
      await pumpProvider();
      firstLoad.complete(activeRowFor('STAFF', ['owner_admin']));
      await pumpProvider();

      final state = container.read(currentAccountProvider);
      expect(state, isA<CurrentAccountLoaded>());
      expect(
        (state as CurrentAccountLoaded).account.userType,
        AccountUserType.client,
      );
    },
  );

  test('authentication loss clears loaded trusted account state', () async {
    final source = ControlledAuthSessionSource(
      AuthSessionSnapshot(
        authUserId: '00000000-0000-0000-0000-000000000201',
        email: 'a@example.test',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        authSessionSourceProvider.overrideWithValue(source),
        currentAccountRepositoryProvider.overrideWithValue(
          CurrentAccountRepository(
            rpc: (_) async => activeRowFor('STAFF', ['owner_admin']),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      currentAccountProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await pumpProvider();
    expect(container.read(currentAccountProvider), isA<CurrentAccountLoaded>());

    source.emitSignedOut();
    await pumpProvider();

    expect(
      container.read(currentAccountProvider),
      isA<CurrentAccountNotProvisioned>(),
    );
  });

  test(
    'provider disposal during in-flight request does not update state',
    () async {
      final load = Completer<dynamic>();
      final container = ProviderContainer(
        overrides: [
          initialAuthSessionProvider.overrideWithValue(
            const AuthSessionState.authenticated(
              authUserId: '00000000-0000-0000-0000-000000000201',
              email: 'a@example.test',
            ),
          ),
          currentAccountRepositoryProvider.overrideWithValue(
            CurrentAccountRepository(rpc: (_) => load.future),
          ),
        ],
      );

      container.read(currentAccountProvider);
      await pumpProvider();
      container.dispose();
      load.complete(activeRowFor('STAFF', ['owner_admin']));
      await pumpProvider();
    },
  );
}

ProviderContainer containerFor(dynamic response) {
  return ProviderContainer(
    overrides: [
      initialAuthSessionProvider.overrideWithValue(
        const AuthSessionState.authenticated(email: 'person@example.com'),
      ),
      currentAccountRepositoryProvider.overrideWithValue(
        CurrentAccountRepository(rpc: (_) async => response),
      ),
    ],
  );
}

Future<void> pumpProvider() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<CurrentAccountState> stateFor({
  required String status,
  String userType = 'STAFF',
  bool accessAllowed = true,
  List<String> roles = const [],
}) async {
  final container = containerFor([
    {
      'application_user_id': '10000000-0000-0000-0000-000000000201',
      'account_status': status,
      'is_active': status == 'ACTIVE',
      'access_allowed': accessAllowed,
      'user_type': userType,
      'full_name': status == 'ACTIVE' ? 'Person' : null,
      'job_title': status == 'ACTIVE' ? 'Role' : null,
      'active_role_codes': roles,
    },
  ]);
  addTearDown(container.dispose);

  container.read(currentAccountProvider);
  await pumpProvider();
  return container.read(currentAccountProvider);
}

List<Map<String, dynamic>> activeRowFor(String userType, List<String> roles) {
  return [
    {
      'application_user_id': '10000000-0000-0000-0000-000000000201',
      'account_status': 'ACTIVE',
      'is_active': true,
      'access_allowed': true,
      'user_type': userType,
      'full_name': 'Person',
      'job_title': 'Role',
      'active_role_codes': roles,
    },
  ];
}

class ControlledAuthSessionSource implements AuthSessionSource {
  ControlledAuthSessionSource(this.restoredSession);

  AuthSessionSnapshot? restoredSession;

  final controller = StreamController<AuthSessionChange>.broadcast();

  @override
  AuthSessionSnapshot? get currentSession => restoredSession;

  @override
  Stream<AuthSessionChange> get onAuthStateChange => controller.stream;

  void emitSignedIn(AuthSessionSnapshot session) {
    restoredSession = session;
    controller.add(
      AuthSessionChange(
        event: AuthSessionChangeEvent.signedIn,
        session: session,
      ),
    );
  }

  void emitSignedOut() {
    restoredSession = null;
    controller.add(
      const AuthSessionChange(event: AuthSessionChangeEvent.signedOut),
    );
  }
}
