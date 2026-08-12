import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../documents/document_file_services.dart';
import '../documents/document_models.dart';
import '../documents/document_providers.dart';
import '../documents/document_repository.dart';
import '../projects/project_models.dart';
import '../projects/project_providers.dart';
import 'photograph_gallery_screen.dart';

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
    Future.microtask(() {
      ref.read(clientProjectDetailProvider(widget.projectId).notifier).load();
      ref
          .read(clientProjectCompletionProvider(widget.projectId).notifier)
          .load();
      ref
          .read(clientProjectProgressUpdatesProvider(widget.projectId).notifier)
          .load();
      ref
          .read(clientProjectDocumentsProvider(widget.projectId).notifier)
          .load();
      ref
          .read(clientProjectPhotographsProvider(widget.projectId).notifier)
          .load();
    });
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
    return _ProjectDetail(project: state.project!, projectId: widget.projectId);
  }
}

class _ProjectDetail extends ConsumerStatefulWidget {
  const _ProjectDetail({required this.project, required this.projectId});

  final ClientProject project;
  final String projectId;

  @override
  ConsumerState<_ProjectDetail> createState() => _ProjectDetailState();
}

class _ProjectDetailState extends ConsumerState<_ProjectDetail> {
  final _thumbs = <String, AsyncValue<Uint8List>>{};
  String? _thumbContextToken;
  var _thumbGeneration = 0;

  @override
  Widget build(BuildContext context) {
    ref.watch(clientProjectAccessContextProvider);
    final contextToken = _projectViewContextToken(ref, widget.projectId);
    if (_thumbContextToken != contextToken) {
      _thumbContextToken = contextToken;
      _thumbs.clear();
      _thumbGeneration++;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.project.projectNumber,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              widget.project.name,
              style: Theme.of(context).textTheme.headlineSmall,
              softWrap: true,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(widget.project.status.replaceAll('_', ' ')),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: isWide ? 24 : 12,
              runSpacing: 12,
              children: [
                if (widget.project.projectType != null)
                  _DetailMeta('Project type', widget.project.projectType!),
                if (widget.project.location != null)
                  _DetailMeta('Location', widget.project.location!),
                if (widget.project.startDate != null)
                  _DetailMeta(
                    'Start date',
                    _formatDate(widget.project.startDate),
                  ),
                if (widget.project.endDate != null)
                  _DetailMeta('End date', _formatDate(widget.project.endDate)),
                _DetailMeta(
                  'Reporting currency',
                  widget.project.reportingCurrencyCode,
                ),
              ],
            ),
            if (widget.project.clientVisibleSummary != null) ...[
              const SizedBox(height: 24),
              Text('Summary', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(widget.project.clientVisibleSummary!),
            ],
            const SizedBox(height: 24),
            _CompletionSection(projectId: widget.projectId),
            const SizedBox(height: 24),
            _ProgressUpdatesSection(projectId: widget.projectId),
            const SizedBox(height: 24),
            _DocumentsSection(projectId: widget.projectId),
            const SizedBox(height: 24),
            _PhotographsSection(
              projectId: widget.projectId,
              thumbnailFor: _thumbnailFor,
              onOpen: _openPreview,
            ),
          ],
        );
      },
    );
  }

  AsyncValue<Uint8List> _thumbnailFor(PhotographGalleryItem item) {
    if (!item.thumbnailAvailable) return AsyncValue.data(Uint8List(0));
    final contextToken = _projectViewContextToken(ref, widget.projectId);
    if (contextToken == null) return AsyncValue.data(Uint8List(0));
    final cacheKey = '$contextToken:${item.id}';
    final cached = _thumbs[cacheKey];
    if (cached != null) return cached;
    final generation = _thumbGeneration;
    _thumbs[cacheKey] = const AsyncValue.loading();
    ref
        .read(documentRepositoryProvider)
        .requestPhotographThumbnail(item.id)
        .then((access) {
          if (!_canApplyProjectAccess(contextToken, generation)) return;
          setState(() => _thumbs[cacheKey] = AsyncValue.data(access.bytes));
        })
        .catchError((Object error) {
          if (!_canApplyProjectAccess(contextToken, generation)) return;
          setState(
            () =>
                _thumbs[cacheKey] = AsyncValue.error(error, StackTrace.current),
          );
        });
    return const AsyncValue.loading();
  }

  void _openPreview(PhotographGalleryItem item) {
    final contextToken = _projectViewContextToken(ref, widget.projectId);
    if (contextToken == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => PhotographPreviewDialog(
        item: item,
        repository: ref.read(documentRepositoryProvider),
        presenter: ref.read(documentContentPresenterProvider),
        ownerAdmin: false,
        generation: contextToken,
        currentGeneration: () =>
            _projectViewContextToken(ref, widget.projectId) ?? '',
      ),
    );
  }

  bool _canApplyProjectAccess(String contextToken, int generation) {
    return mounted &&
        generation == _thumbGeneration &&
        _thumbContextToken == contextToken &&
        _projectViewContextToken(ref, widget.projectId) == contextToken;
  }
}

class _CompletionSection extends ConsumerWidget {
  const _CompletionSection({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientProjectCompletionProvider(projectId));
    final completion = state.completion;
    return _Section(
      title: 'Project progress',
      child: state.isLoading
          ? const _SectionLoading()
          : state.error != null
          ? const Text('Project progress could not be loaded.')
          : completion == null || completion.officialCompletionPercent == null
          ? const Text('Project progress is not available yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatPercent(completion.officialCompletionPercent),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Semantics(
                  label:
                      'Project progress ${_formatPercent(completion.officialCompletionPercent)}',
                  child: LinearProgressIndicator(
                    value:
                        (_visualPercent(completion.officialCompletionPercent) /
                        100),
                  ),
                ),
                if (completion.isOverridden &&
                    completion.calculatedCompletionPercent != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Official progress: ${_formatPercent(completion.officialCompletionPercent)}',
                  ),
                  Text(
                    'Calculated progress: ${_formatPercent(completion.calculatedCompletionPercent)}',
                  ),
                ],
              ],
            ),
    );
  }
}

class _ProgressUpdatesSection extends ConsumerWidget {
  const _ProgressUpdatesSection({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientProjectProgressUpdatesProvider(projectId));
    return _Section(
      title: 'Recent progress updates',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.isLoading)
            const _SectionLoading()
          else if (state.error != null)
            const Text('Progress updates could not be loaded.')
          else if (state.items.isEmpty)
            const Text('No progress updates are available yet.')
          else
            ...state.items.map((update) => _ProgressUpdateCard(update)),
          if (!state.isLoading && state.error == null)
            _LoadMoreButton(
              hasMore: state.hasMore,
              isLoadingMore: state.isLoadingMore,
              onPressed: () => ref
                  .read(
                    clientProjectProgressUpdatesProvider(projectId).notifier,
                  )
                  .loadMore(),
            ),
        ],
      ),
    );
  }
}

class _DocumentsSection extends ConsumerWidget {
  const _DocumentsSection({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientProjectDocumentsProvider(projectId));
    final repository = ref.read(documentRepositoryProvider);
    final presenter = ref.read(documentContentPresenterProvider);
    return _Section(
      title: 'Project documents',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.isLoading)
            const _SectionLoading()
          else if (state.error != null)
            const Text('Project documents could not be loaded.')
          else if (state.documents.isEmpty)
            const Text('No project documents are available yet.')
          else
            ...state.documents.map(
              (document) => _DocumentRow(
                document: document,
                projectId: projectId,
                repository: repository,
                presenter: presenter,
              ),
            ),
          if (!state.isLoading && state.error == null)
            _LoadMoreButton(
              hasMore: state.hasMore,
              isLoadingMore: state.isLoadingMore,
              onPressed: () => ref
                  .read(clientProjectDocumentsProvider(projectId).notifier)
                  .loadMore(),
            ),
        ],
      ),
    );
  }
}

class _PhotographsSection extends ConsumerWidget {
  const _PhotographsSection({
    required this.projectId,
    required this.thumbnailFor,
    required this.onOpen,
  });

  final String projectId;
  final AsyncValue<Uint8List> Function(PhotographGalleryItem) thumbnailFor;
  final ValueChanged<PhotographGalleryItem> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientProjectPhotographsProvider(projectId));
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? (constraints.maxWidth / 220).floor().clamp(3, 6)
            : 2;
        return _Section(
          title: 'Project photographs',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: state.items.isEmpty ? 96 : null,
                child: PhotographGalleryBody(
                  state: state,
                  columns: columns,
                  emptyText: 'No project photographs are available yet.',
                  ownerAdmin: false,
                  thumbnailFor: thumbnailFor,
                  onOpen: onOpen,
                  shrinkWrap: true,
                ),
              ),
              if (!state.isLoading && state.error == null)
                _LoadMoreButton(
                  hasMore: state.hasMore,
                  isLoadingMore: state.isLoadingMore,
                  onPressed: () => ref
                      .read(
                        clientProjectPhotographsProvider(projectId).notifier,
                      )
                      .loadMore(),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ProgressUpdateCard extends StatelessWidget {
  const _ProgressUpdateCard(this.update);

  final ClientProgressUpdate update;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              update.title,
              style: Theme.of(context).textTheme.titleSmall,
              softWrap: true,
            ),
            if (update.publishedAt != null)
              Text('Published ${_formatDate(update.publishedAt)}'),
            if (update.reportedCompletionPercent != null)
              Text(
                'Reported completion ${_formatPercent(update.reportedCompletionPercent)}',
              ),
            if (update.summary != null) ...[
              const SizedBox(height: 8),
              Text(update.summary!, softWrap: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _DocumentRow extends ConsumerStatefulWidget {
  const _DocumentRow({
    required this.document,
    required this.projectId,
    required this.repository,
    required this.presenter,
  });

  final SafeDocument document;
  final String projectId;
  final DocumentRepository repository;
  final DocumentContentPresenter presenter;

  @override
  ConsumerState<_DocumentRow> createState() => _DocumentRowState();
}

class _DocumentRowState extends ConsumerState<_DocumentRow> {
  var _busy = false;
  var _requestGeneration = 0;

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              document.safeDisplayFileName,
              style: Theme.of(context).textTheme.titleSmall,
              softWrap: true,
            ),
            Text(document.documentNumber, overflow: TextOverflow.ellipsis),
            Text(document.documentTypeCode, overflow: TextOverflow.ellipsis),
            Text(
              [
                if (document.fileSizeBytes != null)
                  _formatBytes(document.fileSizeBytes!),
                if (document.createdAt != null) _formatDate(document.createdAt),
              ].join(' - '),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _present(DocumentAccessPurpose.preview),
                  icon: const Icon(Icons.visibility),
                  label: const Text('Preview'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _present(DocumentAccessPurpose.download),
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _present(DocumentAccessPurpose purpose) async {
    final contextToken = _projectViewContextToken(ref, widget.projectId);
    if (contextToken == null) return;
    final documentId = widget.document.id;
    final generation = ++_requestGeneration;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final access = await widget.repository.requestDocumentAccess(
        documentId,
        purpose,
      );
      if (!_canPresent(contextToken, documentId, generation)) return;
      final content = DocumentPresentationContent(
        bytes: access.bytes,
        mimeType: access.mimeType,
        safeFileName: access.safeFileName,
      );
      if (purpose == DocumentAccessPurpose.preview) {
        await widget.presenter.preview(content);
      } else {
        await widget.presenter.download(content);
      }
    } catch (_) {
      if (!_canPresent(contextToken, documentId, generation)) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('Document access is unavailable.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _canPresent(String contextToken, String documentId, int generation) {
    return mounted &&
        generation == _requestGeneration &&
        widget.document.id == documentId &&
        _projectViewContextToken(ref, widget.projectId) == contextToken;
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.hasMore,
    required this.isLoadingMore,
    required this.onPressed,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: !hasMore || isLoadingMore ? null : onPressed,
        icon: isLoadingMore
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more),
        label: Text(hasMore ? 'Load more' : 'All loaded'),
      ),
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

String _formatPercent(num? value) {
  if (value == null) return 'Not available';
  final rounded = value.round();
  return '$rounded%';
}

double _visualPercent(num? value) {
  final numeric = value?.toDouble() ?? 0;
  return numeric.clamp(0, 100).toDouble();
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}

String? _projectViewContextToken(WidgetRef ref, String projectId) {
  final accessContext = ref.read(clientProjectAccessContextProvider);
  if (accessContext == null) return null;
  return [
    projectId,
    accessContext.authStatus.name,
    accessContext.authUserId ?? '',
    accessContext.applicationUserId,
    accessContext.routeTarget.name,
    accessContext.accountStatus.name,
    accessContext.isActive,
    accessContext.accessAllowed,
    accessContext.userType.name,
  ].join('|');
}
