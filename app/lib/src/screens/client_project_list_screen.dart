import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../projects/project_models.dart';
import '../projects/project_providers.dart';

class ClientProjectListScreen extends ConsumerStatefulWidget {
  const ClientProjectListScreen({super.key});

  @override
  ConsumerState<ClientProjectListScreen> createState() =>
      _ClientProjectListScreenState();
}

class _ClientProjectListScreenState
    extends ConsumerState<ClientProjectListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(clientProjectListProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(clientProjectAccessProvider, (previous, hasAccess) {
      if (previous != true && hasAccess) {
        Future.microtask(
          () => ref.read(clientProjectListProvider.notifier).load(),
        );
      }
    });
    final state = ref.watch(clientProjectListProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Projects',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _ProjectListBody(state: state, isWide: isWide),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed:
                      state.isLoading || state.isLoadingMore || !state.hasMore
                      ? null
                      : () => ref
                            .read(clientProjectListProvider.notifier)
                            .loadMore(),
                  icon: state.isLoadingMore
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  label: Text(state.hasMore ? 'Load more' : 'All loaded'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProjectListBody extends StatelessWidget {
  const _ProjectListBody({required this.state, required this.isWide});

  final ClientProjectListState state;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return const Center(child: Text('Projects could not be loaded.'));
    }
    if (state.projects.isEmpty) {
      return const Center(child: Text('No projects are available yet.'));
    }
    return ListView.separated(
      itemBuilder: (context, index) =>
          _ProjectCard(project: state.projects[index], isWide: isWide),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemCount: state.projects.length,
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.isWide});

  final ClientProject project;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/client/projects/${project.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isWide ? _wide(context) : _narrow(context),
        ),
      ),
    );
  }

  Widget _wide(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: _headline(context)),
        const SizedBox(width: 16),
        Expanded(flex: 4, child: _metadata(context)),
        const SizedBox(width: 16),
        IconButton(
          tooltip: 'View project',
          onPressed: () => context.go('/client/projects/${project.id}'),
          icon: const Icon(Icons.arrow_forward),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headline(context),
        const SizedBox(height: 12),
        _metadata(context),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => context.go('/client/projects/${project.id}'),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('View'),
          ),
        ),
      ],
    );
  }

  Widget _headline(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          project.projectNumber,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          project.name,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _StatusChip(status: project.status),
        if (project.clientVisibleSummary != null) ...[
          const SizedBox(height: 8),
          Text(
            project.clientVisibleSummary!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _metadata(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        if (project.projectType != null) _Meta('Type', project.projectType!),
        if (project.location != null) _Meta('Location', project.location!),
        if (project.startDate != null)
          _Meta('Start', _formatDate(project.startDate)),
        if (project.endDate != null) _Meta('End', _formatDate(project.endDate)),
        _Meta('Currency', project.reportingCurrencyCode),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(_statusLabel(status)));
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, overflow: TextOverflow.ellipsis, maxLines: 2),
        ],
      ),
    );
  }
}

String _statusLabel(String status) => status.replaceAll('_', ' ');

String _formatDate(DateTime? date) {
  if (date == null) return 'Not available';
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
