import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
import 'owner_clients_projects_models.dart';
import 'owner_clients_projects_repository.dart';

final ownerClientsProjectsRepositoryProvider =
    Provider<OwnerClientsProjectsRepository>(
      (ref) => OwnerClientsProjectsRepository(),
    );

final ownerClientProjectAccessProvider = Provider<bool>((ref) {
  final session = ref.watch(authSessionProvider);
  final account = ref.watch(currentAccountProvider);
  return session.status == AuthSessionStatus.authenticated &&
      account is CurrentAccountLoaded &&
      account.routeTarget == TrustedAccountRouteTarget.staff;
});

final ownerClientListProvider = FutureProvider<List<OwnerClientRecord>>((ref) {
  if (!ref.watch(ownerClientProjectAccessProvider)) return const [];
  return ref.watch(ownerClientsProjectsRepositoryProvider).listClients();
});

final ownerClientDetailProvider =
    FutureProvider.family<OwnerClientRecord, String>((ref, clientId) {
      if (!ref.watch(ownerClientProjectAccessProvider)) {
        throw const OwnerClientProjectFailure('Owner access required.');
      }
      return ref
          .watch(ownerClientsProjectsRepositoryProvider)
          .clientDetail(clientId);
    });

final ownerClientProjectsProvider =
    FutureProvider.family<List<OwnerProjectRecord>, String>((ref, clientId) {
      if (!ref.watch(ownerClientProjectAccessProvider)) return const [];
      return ref
          .watch(ownerClientsProjectsRepositoryProvider)
          .clientProjects(clientId);
    });

final ownerClientInvitationStatusProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, clientId) {
      if (!ref.watch(ownerClientProjectAccessProvider)) return const {};
      return ref
          .watch(ownerClientsProjectsRepositoryProvider)
          .invitationStatus(clientId);
    });

final ownerProjectListProvider = FutureProvider<List<OwnerProjectRecord>>((
  ref,
) {
  if (!ref.watch(ownerClientProjectAccessProvider)) return const [];
  return ref.watch(ownerClientsProjectsRepositoryProvider).listProjects();
});

final ownerProjectDetailProvider =
    FutureProvider.family<OwnerProjectRecord, String>((ref, projectId) {
      if (!ref.watch(ownerClientProjectAccessProvider)) {
        throw const OwnerClientProjectFailure('Owner access required.');
      }
      return ref
          .watch(ownerClientsProjectsRepositoryProvider)
          .projectDetail(projectId);
    });
