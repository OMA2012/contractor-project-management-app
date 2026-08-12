import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/current_account_provider.dart';
import '../auth/auth_session.dart';
import '../documents/document_file_services.dart';
import '../documents/document_models.dart';
import '../documents/document_providers.dart';
import '../documents/document_repository.dart';

class PhotographGalleryScreen extends ConsumerStatefulWidget {
  const PhotographGalleryScreen.ownerAdmin({super.key})
    : audience = PhotographGalleryAudience.ownerAdmin;

  const PhotographGalleryScreen.client({super.key})
    : audience = PhotographGalleryAudience.client;

  final PhotographGalleryAudience audience;

  @override
  ConsumerState<PhotographGalleryScreen> createState() =>
      _PhotographGalleryScreenState();
}

class _PhotographGalleryScreenState
    extends ConsumerState<PhotographGalleryScreen> {
  final _thumbs = <String, AsyncValue<Uint8List>>{};
  var _thumbGeneration = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadInitial);
  }

  @override
  Widget build(BuildContext context) {
    final generation = _sessionGeneration(ref);
    if (_thumbGeneration != generation) {
      _thumbGeneration = generation;
      _thumbs.clear();
    }
    final isOwner = widget.audience == PhotographGalleryAudience.ownerAdmin;
    final state = isOwner
        ? ref.watch(ownerAdminPhotographGalleryProvider)
        : ref.watch(clientPhotographGalleryProvider);
    final category = ref.watch(ownerAdminPhotographCategoryProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        final columns = isWide
            ? (constraints.maxWidth / 220).floor().clamp(3, 6)
            : 2;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isOwner ? 'Photograph Gallery' : 'Photographs',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (isOwner) ...[
                const SizedBox(height: 12),
                SegmentedButton<OwnerAdminPhotographCategory>(
                  segments: const [
                    ButtonSegment(
                      value: OwnerAdminPhotographCategory.progress,
                      icon: Icon(Icons.photo_library),
                      label: Text('Progress'),
                    ),
                    ButtonSegment(
                      value: OwnerAdminPhotographCategory.taskImage,
                      icon: Icon(Icons.image),
                      label: Text('Task images'),
                    ),
                  ],
                  selected: {category},
                  onSelectionChanged: (selection) => ref
                      .read(ownerAdminPhotographGalleryProvider.notifier)
                      .selectCategory(selection.single),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: PhotographGalleryBody(
                  state: state,
                  columns: columns,
                  emptyText: isOwner
                      ? category == OwnerAdminPhotographCategory.progress
                            ? 'No progress photographs yet.'
                            : 'No task images yet.'
                      : 'No photographs are available yet.',
                  ownerAdmin: isOwner,
                  thumbnailFor: _thumbnailFor,
                  onOpen: _openPreview,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed:
                      state.isLoading || state.isLoadingMore || !state.hasMore
                      ? null
                      : _loadMore,
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

  void _loadInitial() {
    if (widget.audience == PhotographGalleryAudience.ownerAdmin) {
      ref.read(ownerAdminPhotographGalleryProvider.notifier).load();
    } else {
      ref.read(clientPhotographGalleryProvider.notifier).load();
    }
  }

  void _loadMore() {
    if (widget.audience == PhotographGalleryAudience.ownerAdmin) {
      ref.read(ownerAdminPhotographGalleryProvider.notifier).loadMore();
    } else {
      ref.read(clientPhotographGalleryProvider.notifier).loadMore();
    }
  }

  AsyncValue<Uint8List> _thumbnailFor(PhotographGalleryItem item) {
    if (!item.thumbnailAvailable) return AsyncValue.data(Uint8List(0));
    final cached = _thumbs[item.id];
    if (cached != null) return cached;
    _thumbs[item.id] = const AsyncValue.loading();
    final generation = _thumbGeneration;
    ref
        .read(documentRepositoryProvider)
        .requestPhotographThumbnail(item.id)
        .then((access) {
          if (!mounted || generation != _thumbGeneration) return;
          setState(() => _thumbs[item.id] = AsyncValue.data(access.bytes));
        })
        .catchError((Object error) {
          if (!mounted || generation != _thumbGeneration) return;
          setState(
            () =>
                _thumbs[item.id] = AsyncValue.error(error, StackTrace.current),
          );
        });
    return const AsyncValue.loading();
  }

  Future<void> _openPreview(PhotographGalleryItem item) {
    return showDialog<void>(
      context: context,
      builder: (context) => PhotographPreviewDialog(
        item: item,
        repository: ref.read(documentRepositoryProvider),
        presenter: ref.read(documentContentPresenterProvider),
        ownerAdmin: widget.audience == PhotographGalleryAudience.ownerAdmin,
        generation: _sessionGeneration(ref),
        currentGeneration: () => _sessionGeneration(ref),
      ),
    );
  }
}

class PhotographGalleryBody extends StatelessWidget {
  const PhotographGalleryBody({
    required this.state,
    required this.columns,
    required this.emptyText,
    required this.ownerAdmin,
    required this.thumbnailFor,
    required this.onOpen,
    this.shrinkWrap = false,
    super.key,
  });

  final PhotographGalleryState state;
  final int columns;
  final String emptyText;
  final bool ownerAdmin;
  final AsyncValue<Uint8List> Function(PhotographGalleryItem) thumbnailFor;
  final ValueChanged<PhotographGalleryItem> onOpen;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return const Center(child: Text('Photographs could not be loaded.'));
    }
    if (state.items.isEmpty) return Center(child: Text(emptyText));
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: .78,
      ),
      itemCount: state.items.length,
      itemBuilder: (context, index) => PhotographGalleryTile(
        item: state.items[index],
        ownerAdmin: ownerAdmin,
        thumbnail: thumbnailFor(state.items[index]),
        onTap: () => onOpen(state.items[index]),
      ),
    );
  }
}

class PhotographGalleryTile extends StatelessWidget {
  const PhotographGalleryTile({
    required this.item,
    required this.ownerAdmin,
    required this.thumbnail,
    required this.onTap,
    super.key,
  });

  final PhotographGalleryItem item;
  final bool ownerAdmin;
  final AsyncValue<Uint8List> thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.previewAvailable ? onTap : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: colors.surfaceContainerHighest,
                child: thumbnail.when(
                  data: (bytes) => bytes.isEmpty
                      ? const _PhotoPlaceholder(label: 'Unavailable')
                      : Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) =>
                      const _PhotoPlaceholder(label: 'Unavailable'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.safeDisplayFileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(item.documentNumber, overflow: TextOverflow.ellipsis),
                  Text(_typeLabel(item), overflow: TextOverflow.ellipsis),
                  Text(
                    _formatDate(item.uploadedAt),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (ownerAdmin)
                    Text(
                      item.clientVisible == true ? 'Client visible' : 'Private',
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(_processingLabel(item), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [const Icon(Icons.image_not_supported), Text(label)],
      ),
    );
  }
}

class PhotographPreviewDialog extends StatefulWidget {
  const PhotographPreviewDialog({
    required this.item,
    required this.repository,
    required this.presenter,
    required this.ownerAdmin,
    required this.generation,
    required this.currentGeneration,
    super.key,
  });

  final PhotographGalleryItem item;
  final DocumentRepository repository;
  final DocumentContentPresenter presenter;
  final bool ownerAdmin;
  final String generation;
  final String Function() currentGeneration;

  @override
  State<PhotographPreviewDialog> createState() =>
      _PhotographPreviewDialogState();
}

class _PhotographPreviewDialogState extends State<PhotographPreviewDialog> {
  late final Future<SecureDocumentAccess?> _preview;

  @override
  void initState() {
    super.initState();
    final generation = widget.generation;
    _preview = widget.repository
        .requestPhotographPreview(widget.item.id)
        .then((access) {
          if (!mounted || generation != widget.currentGeneration()) return null;
          return access;
        })
        .catchError((Object _) {
          if (!mounted || generation != widget.currentGeneration()) return null;
          throw const DocumentFailure('Preview is unavailable.');
        });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: Text(widget.item.safeDisplayFileName),
              subtitle: Text(
                '${widget.item.documentNumber} - ${_formatDate(widget.item.uploadedAt)}',
              ),
              trailing: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: FutureBuilder<SecureDocumentAccess?>(
                future: _preview,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError ||
                      snapshot.data == null ||
                      !widget.item.previewAvailable ||
                      widget.generation != widget.currentGeneration()) {
                    return const Center(child: Text('Preview is unavailable.'));
                  }
                  return InteractiveViewer(
                    child: Center(
                      child: Image.memory(
                        snapshot.data!.bytes,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),
            FutureBuilder<SecureDocumentAccess?>(
              future: _preview,
              builder: (context, snapshot) => Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed:
                      snapshot.hasData &&
                          widget.generation == widget.currentGeneration()
                      ? () => widget.presenter.download(
                          DocumentPresentationContent(
                            bytes: snapshot.data!.bytes,
                            mimeType: snapshot.data!.mimeType,
                            safeFileName: snapshot.data!.safeFileName,
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _sessionGeneration(WidgetRef ref) {
  final session = ref.watch(authSessionProvider);
  final account = ref.watch(currentAccountProvider);
  return '${session.authUserId}:${account.routeTarget}';
}

String _typeLabel(PhotographGalleryItem item) =>
    item.documentTypeCode == 'TASK_ATTACHMENT'
    ? 'Task image'
    : 'Progress photograph';

String _processingLabel(PhotographGalleryItem item) {
  if (item.previewAvailable || item.thumbnailAvailable) return 'Ready';
  if (item.processingState == 'FAILED') return 'Processing failed';
  return 'Processing unavailable';
}

String _formatDate(DateTime? date) => date == null
    ? 'Date unavailable'
    : date.toLocal().toString().split('.').first;
