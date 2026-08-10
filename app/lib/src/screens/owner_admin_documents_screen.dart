import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/current_account.dart';
import '../account/current_account_provider.dart';
import '../documents/document_file_services.dart';
import '../documents/document_models.dart';
import '../documents/document_providers.dart';
import '../documents/document_repository.dart';

class OwnerAdminDocumentsScreen extends ConsumerStatefulWidget {
  const OwnerAdminDocumentsScreen({super.key});

  @override
  ConsumerState<OwnerAdminDocumentsScreen> createState() =>
      _OwnerAdminDocumentsScreenState();
}

class _OwnerAdminDocumentsScreenState
    extends ConsumerState<OwnerAdminDocumentsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(ownerAdminDocumentListProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerAdminDocumentListProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Owner/Admin Documents',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Filters',
                    onPressed: () => _showFilters(context),
                    icon: const Icon(Icons.tune),
                  ),
                  IconButton(
                    tooltip: 'Upload',
                    onPressed: () => context.go('/staff/documents/upload'),
                    icon: const Icon(Icons.upload_file),
                  ),
                ],
              ),
              if (isWide) const _InlineFilters(),
              const SizedBox(height: 12),
              Expanded(
                child: _DocumentListBody(state: state, isWide: isWide),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: state.isLoading
                      ? null
                      : () => ref
                            .read(ownerAdminDocumentListProvider.notifier)
                            .loadMore(),
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Load more'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showFilters(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          const Padding(padding: EdgeInsets.all(16), child: _InlineFilters()),
    );
  }
}

class OwnerAdminDocumentDetailScreen extends ConsumerStatefulWidget {
  const OwnerAdminDocumentDetailScreen({required this.documentId, super.key});

  final String documentId;

  @override
  ConsumerState<OwnerAdminDocumentDetailScreen> createState() =>
      _OwnerAdminDocumentDetailScreenState();
}

class _OwnerAdminDocumentDetailScreenState
    extends ConsumerState<OwnerAdminDocumentDetailScreen> {
  Object? _accessError;
  String? _accessMessage;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(ownerAdminDocumentDetailProvider(widget.documentId).notifier)
          .load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      ownerAdminDocumentDetailProvider(widget.documentId),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
          ? _ErrorView(
              message: 'Document details could not be loaded.',
              onRetry: () => ref
                  .read(
                    ownerAdminDocumentDetailProvider(
                      widget.documentId,
                    ).notifier,
                  )
                  .load(),
            )
          : _DetailContent(
              state: state,
              document: state.document!,
              accessError: _accessError,
              accessMessage: _accessMessage,
              onAccess: _requestAccess,
              onArchive: _archive,
              onRestore: _restore,
              onReplace: _replace,
            ),
    );
  }

  Future<void> _requestAccess(
    SafeDocument document,
    DocumentAccessPurpose purpose,
  ) async {
    setState(() {
      _accessError = null;
      _accessMessage = null;
    });
    try {
      final repository = ref.read(documentRepositoryProvider);
      final access =
          document.isPhotograph && purpose == DocumentAccessPurpose.preview
          ? await repository.requestPhotographPreview(document.id)
          : await repository.requestDocumentAccess(document.id, purpose);
      final content = DocumentPresentationContent(
        bytes: access.bytes,
        mimeType: access.mimeType,
        safeFileName: access.safeFileName,
      );
      final presenter = ref.read(documentContentPresenterProvider);
      if (purpose == DocumentAccessPurpose.preview) {
        await presenter.preview(content);
        setState(() => _accessMessage = 'Preview opened.');
      } else {
        await presenter.download(content);
        setState(() => _accessMessage = 'Download started.');
      }
    } catch (error) {
      setState(() => _accessError = error);
    }
  }

  Future<void> _archive(SafeDocument document) async {
    final confirmed = await _confirmLifecycle(
      title: 'Archive document',
      body:
          'The document remains retained. It will no longer be current or Client-visible according to lifecycle rules. This is not permanent deletion.',
      action: 'Archive document',
    );
    if (confirmed != true) return;
    final ok = await ref
        .read(ownerAdminDocumentDetailProvider(widget.documentId).notifier)
        .archive();
    if (!mounted) return;
    _showLifecycleSnack(ok, 'Document archived.');
  }

  Future<void> _restore(SafeDocument document) async {
    final confirmed = await _confirmLifecycle(
      title: 'Restore document',
      body:
          'The restored document returns as contractor-private. Client visibility is not automatically restored.',
      action: 'Restore document',
    );
    if (confirmed != true) return;
    final ok = await ref
        .read(ownerAdminDocumentDetailProvider(widget.documentId).notifier)
        .restore();
    if (!mounted) return;
    _showLifecycleSnack(ok, 'Document restored as private.');
  }

  Future<void> _replace(SafeDocument document) async {
    final candidate = await _selectReplacementCandidate(document);
    if (candidate == null) return;
    final confirmed = await _confirmLifecycle(
      title: 'Confirm replacement',
      body:
          '${document.documentNumber} will remain retained as historical. ${candidate.documentNumber} becomes the approved replacement. Client visibility is not automatically inherited.',
      action: 'Confirm replacement',
    );
    if (confirmed != true) return;
    final ok = await ref
        .read(ownerAdminDocumentDetailProvider(widget.documentId).notifier)
        .replaceWith(candidate.id);
    if (!mounted) return;
    _showLifecycleSnack(ok, 'Replacement recorded.');
  }

  Future<bool?> _confirmLifecycle({
    required String title,
    required String body,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<SafeDocument?> _selectReplacementCandidate(SafeDocument document) {
    return showModalBottomSheet<SafeDocument>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ReplacementCandidateSheet(
        currentDocumentId: document.id,
        repository: ref.read(documentRepositoryProvider),
      ),
    );
  }

  void _showLifecycleSnack(bool ok, String success) {
    final message = ok
        ? success
        : _safeLifecycleError(
            ref
                .read(ownerAdminDocumentDetailProvider(widget.documentId))
                .mutationError,
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ReplacementCandidateSheet extends StatefulWidget {
  const _ReplacementCandidateSheet({
    required this.currentDocumentId,
    required this.repository,
  });

  static const pageSize = 100;

  final String currentDocumentId;
  final DocumentRepository repository;

  @override
  State<_ReplacementCandidateSheet> createState() =>
      _ReplacementCandidateSheetState();
}

class _ReplacementCandidateSheetState
    extends State<_ReplacementCandidateSheet> {
  final _documents = <SafeDocument>[];
  final _seen = <String>{};
  var _isLoading = false;
  var _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadNextPage);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Replace document',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose the approved replacement. The existing document remains historical and is not deleted.',
          ),
          const SizedBox(height: 12),
          if (_documents.isEmpty && _isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_documents.isEmpty && _error == null)
            const Text('No replacement candidates are available yet.'),
          ..._documents.map(
            (candidate) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(candidate.safeDisplayFileName),
              subtitle: Text(_candidateLabel(candidate)),
              onTap: () => Navigator.of(context).pop(candidate),
            ),
          ),
          if (_error != null)
            Text(
              'Replacement candidates could not be loaded.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _loadNextPage,
                icon: _isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: const Text('Load more documents'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.listOwnerAdminDocuments(
        limit: _ReplacementCandidateSheet.pageSize,
        offset: _documents.length,
      );
      if (!mounted) return;
      setState(() {
        for (final document in page) {
          if (document.id == widget.currentDocumentId) continue;
          if (document.status != 'ACTIVE') continue;
          if (_seen.add(document.id)) {
            _documents.add(document);
          }
        }
        _hasMore = page.length == _ReplacementCandidateSheet.pageSize;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }
}

class OwnerAdminDocumentUploadScreen extends ConsumerStatefulWidget {
  const OwnerAdminDocumentUploadScreen({super.key});

  @override
  ConsumerState<OwnerAdminDocumentUploadScreen> createState() =>
      _OwnerAdminDocumentUploadScreenState();
}

class _OwnerAdminDocumentUploadScreenState
    extends ConsumerState<OwnerAdminDocumentUploadScreen> {
  SelectedDocumentFile? _selectedFile;
  String _documentType = 'GENERAL_DOCUMENT';
  var _clientVisible = false;
  Object? _filePickError;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentUploadProvider);
    ref.listen<CurrentAccountState>(currentAccountProvider, (_, account) {
      if (account.routeTarget != TrustedAccountRouteTarget.staff) {
        setState(() {
          _selectedFile = null;
          _filePickError = null;
        });
      }
    });
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Upload Document',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy(state) ? null : _pickFile,
          icon: const Icon(Icons.attach_file),
          label: const Text('Choose file'),
        ),
        if (_selectedFile == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No file selected.'),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_selectedFile!.safeFileName),
                Text(_selectedFile!.mimeType),
                Text(_formatSize(_selectedFile!.sizeBytes)),
              ],
            ),
          ),
        if (_filePickError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'File selection failed.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _documentType,
          decoration: const InputDecoration(labelText: 'Document type'),
          items: const [
            DropdownMenuItem(
              value: 'GENERAL_DOCUMENT',
              child: Text('General document'),
            ),
            DropdownMenuItem(
              value: 'PROGRESS_PHOTOGRAPH',
              child: Text('Progress photograph'),
            ),
            DropdownMenuItem(value: 'INVOICE', child: Text('Invoice')),
          ],
          onChanged: _busy(state)
              ? null
              : (value) =>
                    setState(() => _documentType = value ?? 'GENERAL_DOCUMENT'),
        ),
        SwitchListTile(
          value: _clientVisible,
          onChanged: _busy(state)
              ? null
              : (value) => setState(() => _clientVisible = value),
          title: const Text('Client visible'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _canUpload(state) ? _startUpload : null,
          icon: const Icon(Icons.upload_file),
          label: const Text('Upload'),
        ),
        const SizedBox(height: 16),
        Text(_uploadPhaseLabel(state.phase)),
        if (state.error != null)
          Text(
            'Upload failed.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _selectedFile = null;
      _filePickError = null;
    });
    try {
      final file = await ref
          .read(documentFilePickerProvider)
          .pickDocumentFile();
      if (file == null) {
        setState(() => _selectedFile = null);
        return;
      }
      setState(() => _selectedFile = file);
    } catch (error) {
      setState(() {
        _selectedFile = null;
        _filePickError = error;
      });
    }
  }

  void _startUpload() {
    final file = _selectedFile;
    if (file == null || _documentType.isEmpty) return;
    ref
        .read(documentUploadProvider.notifier)
        .start(
          DocumentUploadRequest(
            originalFileName: file.safeFileName,
            mimeType: file.mimeType,
            documentTypeCode: _documentType,
            clientVisible: _clientVisible,
            bytes: file.bytes,
          ),
        );
  }

  bool _canUpload(DocumentUploadState state) {
    return !_busy(state) && _selectedFile != null && _documentType.isNotEmpty;
  }

  bool _busy(DocumentUploadState state) {
    return state.phase == DocumentUploadPhase.authorizing ||
        state.phase == DocumentUploadPhase.uploading ||
        state.phase == DocumentUploadPhase.validatingCompleting ||
        state.phase == DocumentUploadPhase.processingPhotograph;
  }
}

class _DocumentListBody extends StatelessWidget {
  const _DocumentListBody({required this.state, required this.isWide});

  final DocumentListState state;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return const _ErrorView(message: 'Documents could not be loaded.');
    }
    if (state.documents.isEmpty) {
      return const Center(child: Text('No documents found.'));
    }
    return ListView.separated(
      itemBuilder: (context, index) =>
          _DocumentRow(document: state.documents[index], isWide: isWide),
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemCount: state.documents.length,
    );
  }
}

class _DocumentRow extends ConsumerWidget {
  const _DocumentRow({required this.document, required this.isWide});

  final SafeDocument document;
  final bool isWide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: document.photograph?.thumbnailAvailable == true
          ? const Icon(Icons.image)
          : const Icon(Icons.description),
      title: Text(document.safeDisplayFileName),
      subtitle: Text(
        isWide
            ? '${document.documentNumber} - ${document.documentTypeCode} - ${document.mimeType} - ${_formatSize(document.fileSizeBytes)}'
            : '${document.documentNumber} - ${document.status}',
      ),
      trailing: Wrap(
        spacing: 8,
        children: [
          Chip(
            label: Text(
              document.clientVisible == true ? 'Client visible' : 'Private',
            ),
          ),
          Chip(label: Text(document.lifecycle?.status ?? document.status)),
          IconButton(
            tooltip: 'View',
            onPressed: () => context.go('/staff/documents/${document.id}'),
            icon: const Icon(Icons.visibility),
          ),
        ],
      ),
      onTap: () => context.go('/staff/documents/${document.id}'),
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({
    required this.state,
    required this.document,
    required this.onAccess,
    required this.onArchive,
    required this.onRestore,
    required this.onReplace,
    this.accessError,
    this.accessMessage,
  });

  final OwnerAdminDocumentDetailState state;
  final SafeDocument document;
  final Object? accessError;
  final String? accessMessage;
  final Future<void> Function(SafeDocument, DocumentAccessPurpose) onAccess;
  final Future<void> Function(SafeDocument) onArchive;
  final Future<void> Function(SafeDocument) onRestore;
  final Future<void> Function(SafeDocument) onReplace;

  @override
  Widget build(BuildContext context) {
    final lifecycle = document.lifecycle;
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final actions = _lifecycleActions(context, isWide);
    return ListView(
      children: [
        Text(
          document.safeDisplayFileName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.visibility),
              label: const Text('Preview'),
              onPressed: () =>
                  onAccess(document, DocumentAccessPurpose.preview),
            ),
            ActionChip(
              avatar: const Icon(Icons.download),
              label: const Text('Download'),
              onPressed: () =>
                  onAccess(document, DocumentAccessPurpose.download),
            ),
            if (isWide) ...actions,
            if (!isWide && actions.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Document lifecycle actions',
                enabled: !state.isMutating,
                onSelected: (value) {
                  if (value == 'archive') onArchive(document);
                  if (value == 'restore') onRestore(document);
                  if (value == 'replace') onReplace(document);
                },
                itemBuilder: (context) => [
                  if (_canArchive)
                    const PopupMenuItem(
                      value: 'archive',
                      child: Text('Archive document'),
                    ),
                  if (_canRestore)
                    const PopupMenuItem(
                      value: 'restore',
                      child: Text('Restore document'),
                    ),
                  const PopupMenuItem(
                    value: 'replace',
                    child: Text('Replace document'),
                  ),
                ],
              ),
          ],
        ),
        if (state.isMutating) const LinearProgressIndicator(),
        if (state.mutationError != null)
          Text(
            _safeLifecycleError(state.mutationError),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        _Meta('Document number', document.documentNumber),
        _Meta('Type', document.documentTypeCode),
        _Meta('MIME type', document.mimeType),
        _Meta('File size', _formatSize(document.fileSizeBytes)),
        _Meta('Status', document.status),
        _Meta(
          'Visibility',
          document.clientVisible == true ? 'Client visible' : 'Private',
        ),
        _Meta('Uploaded', _formatDate(document.createdAt)),
        _Meta('Finalized', _formatDate(document.finalizedAt)),
        if (lifecycle?.archivedAt != null)
          _Meta('Archived', _formatDate(lifecycle!.archivedAt)),
        if (lifecycle?.isSuperseded == true)
          const _Meta('Supersession', 'Superseded'),
        if (lifecycle?.replacesDocumentId != null)
          const _Meta('Replacement', 'Replaces an earlier document'),
        if (document.context != null)
          _Meta('Context', _contextLabel(document.context!)),
        if (document.photograph != null) ...[
          _Meta('Photograph processing', document.photograph!.processingState),
          _Meta(
            'Thumbnail',
            document.photograph!.thumbnailAvailable
                ? 'Available'
                : 'Unavailable',
          ),
          _Meta(
            'Preview',
            document.photograph!.previewAvailable ? 'Available' : 'Unavailable',
          ),
        ],
        if (accessMessage != null) _Meta('Access', accessMessage!),
        if (accessError != null)
          Text(
            'Document access failed.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  bool get _canArchive =>
      document.status == 'ACTIVE' && document.lifecycle?.isSuperseded != true;
  bool get _canRestore =>
      document.status == 'ARCHIVED' && document.lifecycle?.isSuperseded != true;

  List<Widget> _lifecycleActions(BuildContext context, bool isWide) {
    return [
      if (_canArchive)
        ActionChip(
          avatar: const Icon(Icons.archive),
          label: const Text('Archive'),
          onPressed: state.isMutating ? null : () => onArchive(document),
        ),
      if (_canRestore)
        ActionChip(
          avatar: const Icon(Icons.restore),
          label: const Text('Restore'),
          onPressed: state.isMutating ? null : () => onRestore(document),
        ),
      ActionChip(
        avatar: const Icon(Icons.swap_horiz),
        label: const Text('Replace document'),
        onPressed: state.isMutating ? null : () => onReplace(document),
      ),
    ];
  }
}

class _InlineFilters extends ConsumerWidget {
  const _InlineFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(ownerAdminDocumentFiltersProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterMenu(
          label: 'Type',
          value: filters.documentTypeCode,
          values: const ['GENERAL_DOCUMENT', 'PROGRESS_PHOTOGRAPH', 'INVOICE'],
          onChanged: (value) => _apply(
            ref,
            filters.copyWith(
              documentTypeCode: value,
              clearDocumentType: value == null,
            ),
          ),
        ),
        _FilterMenu(
          label: 'Visibility',
          value: filters.clientVisible == null
              ? null
              : filters.clientVisible!
              ? 'CLIENT'
              : 'PRIVATE',
          values: const ['CLIENT', 'PRIVATE'],
          onChanged: (value) => _apply(
            ref,
            filters.copyWith(
              clientVisible: value == null ? null : value == 'CLIENT',
              clearClientVisible: value == null,
            ),
          ),
        ),
        _FilterMenu(
          label: 'Status',
          value: filters.status,
          values: const ['ACTIVE', 'ARCHIVED'],
          onChanged: (value) => _apply(
            ref,
            filters.copyWith(status: value, clearStatus: value == null),
          ),
        ),
        _FilterMenu(
          label: 'Context',
          value: filters.contextType,
          values: const [
            FilterOption('Client', 'client'),
            FilterOption('Project', 'project'),
            FilterOption('Task', 'task'),
            FilterOption('Progress update', 'progress_update'),
            FilterOption('Client payment', 'client_payment'),
          ],
          onChanged: (value) => _apply(
            ref,
            filters.copyWith(
              contextType: value,
              clearContextType: value == null,
            ),
          ),
        ),
      ],
    );
  }

  void _apply(WidgetRef ref, OwnerAdminDocumentFilters filters) {
    ref.read(ownerAdminDocumentListProvider.notifier).applyFilters(filters);
  }
}

class _FilterMenu extends StatelessWidget {
  _FilterMenu({
    required this.label,
    required this.value,
    required List<Object> values,
    required this.onChanged,
  }) : values = values
           .map(
             (value) => value is FilterOption
                 ? value
                 : FilterOption(value.toString(), value.toString()),
           )
           .toList();

  final String label;
  final String? value;
  final List<FilterOption> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String?>(
      hint: Text(label),
      value: value,
      items: [
        DropdownMenuItem<String?>(value: null, child: Text('All $label')),
        ...values.map(
          (option) =>
              DropdownMenuItem(value: option.value, child: Text(option.label)),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class FilterOption {
  const FilterOption(this.label, this.value);

  final String label;
  final String value;
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

String _formatSize(int? bytes) {
  if (bytes == null) return 'Unknown size';
  if (bytes < 1024) return '$bytes B';
  return '${(bytes / 1024).toStringAsFixed(1)} KB';
}

String _formatDate(DateTime? date) =>
    date == null ? 'Not available' : date.toIso8601String();

String _contextLabel(DocumentContext context) {
  if (context.projectId != null) return 'Project context';
  if (context.taskId != null) return 'Task context';
  if (context.progressUpdateId != null) return 'Progress context';
  if (context.clientPaymentId != null) return 'Payment context';
  if (context.clientId != null) return 'Client context';
  return 'Context available';
}

String _candidateLabel(SafeDocument document) {
  return [
    document.documentNumber,
    document.status,
    document.documentTypeCode,
    _contextLabel(document.context ?? const DocumentContext()),
  ].join(' - ');
}

String _safeLifecycleError(Object? error) {
  final message = error?.toString().toLowerCase() ?? '';
  if (message.contains('permission') ||
      message.contains('authenticated') ||
      message.contains('active staff')) {
    return 'Document changes require an active Owner/Admin session.';
  }
  if (message.contains('superseded')) {
    return 'Superseded documents cannot be restored as current.';
  }
  if (message.contains('cycle')) {
    return 'That replacement would create a replacement loop.';
  }
  if (message.contains('context')) {
    return 'The replacement document must belong to the same document context.';
  }
  if (message.contains('candidate') ||
      message.contains('finalized') ||
      message.contains('clean')) {
    return 'The selected replacement document is not eligible.';
  }
  if (message.contains('archived') || message.contains('state')) {
    return 'The document is not in a lifecycle state that allows that change.';
  }
  return 'Document lifecycle change failed. No document data was changed.';
}

String _uploadPhaseLabel(DocumentUploadPhase phase) {
  return switch (phase) {
    DocumentUploadPhase.idle => 'Ready',
    DocumentUploadPhase.authorizing => 'Authorizing upload',
    DocumentUploadPhase.uploading => 'Uploading',
    DocumentUploadPhase.validatingCompleting => 'Completing upload',
    DocumentUploadPhase.awaitingScan =>
      'Uploaded - awaiting security verification',
    DocumentUploadPhase.processingPhotograph => 'Processing photograph',
    DocumentUploadPhase.complete => 'Complete',
    DocumentUploadPhase.failed => 'Failed',
  };
}
