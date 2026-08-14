import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../projects/project_providers.dart';
import 'client_dashboard_models.dart';
import 'client_dashboard_repository.dart';

final clientDashboardRepositoryProvider = Provider<ClientDashboardRepository>(
  (ref) => const SupabaseClientDashboardRepository(),
);

final clientDashboardProvider =
    NotifierProvider<ClientDashboardController, ClientDashboardState>(
      ClientDashboardController.new,
    );

class ClientDashboardController extends Notifier<ClientDashboardState> {
  static const projectLimit = 6;
  static const updateLimit = 5;
  static const activityLimit = 8;

  var _generation = 0;
  ClientProjectAccessContext? _accessContext;

  @override
  ClientDashboardState build() {
    ref.listen<ClientProjectAccessContext?>(
      clientProjectAccessContextProvider,
      (_, next) {
        _accessContext = next;
        _generation++;
        if (next == null) {
          state = const ClientDashboardState();
        } else {
          state = const ClientDashboardState(isLoading: true);
          Future<void>.microtask(load);
        }
      },
    );

    final accessContext = ref.watch(clientProjectAccessContextProvider);
    _accessContext = accessContext;
    if (accessContext == null) {
      return const ClientDashboardState();
    }

    Future<void>.microtask(load);
    return const ClientDashboardState(isLoading: true);
  }

  Future<void> load() async {
    final accessContext = ref.read(clientProjectAccessContextProvider);
    _accessContext = accessContext;
    if (accessContext == null) {
      _generation++;
      state = const ClientDashboardState();
      return;
    }

    final generation = ++_generation;
    state = const ClientDashboardState(isLoading: true);
    try {
      final repository = ref.read(clientDashboardRepositoryProvider);
      final results = await Future.wait([
        repository.listProjectSummaries(limit: projectLimit),
        repository.listRecentUpdates(limit: updateLimit),
        repository.listRecentActivity(limit: activityLimit),
      ]);
      if (!_canApply(generation, accessContext)) return;
      state = ClientDashboardState(
        projects: results[0] as List<ClientDashboardProjectSummary>,
        recentUpdates: results[1] as List<ClientDashboardRecentUpdate>,
        recentActivity: results[2] as List<ClientDashboardRecentActivity>,
      );
    } catch (error) {
      if (!_canApply(generation, accessContext)) return;
      state = ClientDashboardState(error: error);
    }
  }

  Future<void> refresh() => load();

  bool _canApply(int generation, ClientProjectAccessContext accessContext) =>
      ref.mounted &&
      generation == _generation &&
      _accessContext == accessContext &&
      ref.read(clientProjectAccessContextProvider) == accessContext;
}
