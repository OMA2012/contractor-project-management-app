import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../projects/project_models.dart';
import '../projects/project_providers.dart';

class ClientProjectDetailScreen extends ConsumerStatefulWidget {
  const ClientProjectDetailScreen({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<ClientProjectDetailScreen> createState() =>
      _ClientProjectDetailScreenState();
}

class _ClientProjectDetailScreenState
    extends ConsumerState<ClientProjectDetailScreen> {
  @override
  void initState() {
    super.initState();
    _loadProject();
  }

  @override
  void didUpdateWidget(covariant ClientProjectDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _loadProject();
    }
  }

  void _loadProject() {
    Future.microtask(
      () => ref
          .read(clientProjectDetailProvider(widget.projectId).notifier)
          .load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(clientProjectAccessProvider, (previous, hasAccess) {
      if (previous != true && hasAccess) {
        _loadProject();
      }
    });
    final state = ref.watch(clientProjectDetailProvider(widget.projectId));
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.unavailable) {
      return const Center(child: Text('Project is unavailable.'));
    }
    if (state.error != null || state.project == null) {
      return const Center(child: Text('Project could not be loaded.'));
    }
    return _ProjectDetail(project: state.project!);
  }
}

class _ProjectDetail extends StatelessWidget {
  const _ProjectDetail({required this.project});

  final ClientProject project;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              project.projectNumber,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              project.name,
              style: Theme.of(context).textTheme.headlineSmall,
              softWrap: true,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(label: Text(project.status.replaceAll('_', ' '))),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: isWide ? 24 : 12,
              runSpacing: 12,
              children: [
                if (project.projectType != null)
                  _DetailMeta('Project type', project.projectType!),
                if (project.location != null)
                  _DetailMeta('Location', project.location!),
                if (project.startDate != null)
                  _DetailMeta('Start date', _formatDate(project.startDate)),
                if (project.endDate != null)
                  _DetailMeta('End date', _formatDate(project.endDate)),
                _DetailMeta(
                  'Reporting currency',
                  project.reportingCurrencyCode,
                ),
              ],
            ),
            if (project.clientVisibleSummary != null) ...[
              const SizedBox(height: 24),
              Text('Summary', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(project.clientVisibleSummary!),
            ],
          ],
        );
      },
    );
  }
}

class _DetailMeta extends StatelessWidget {
  const _DetailMeta(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, softWrap: true),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Not available';
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
