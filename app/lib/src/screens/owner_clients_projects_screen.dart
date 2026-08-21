import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../owner_clients_projects/owner_clients_projects_providers.dart';

class OwnerClientListScreen extends ConsumerWidget {
  const OwnerClientListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(ownerClientListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clients'),
        actions: [
          IconButton(
            tooltip: 'Create Client',
            onPressed: () => context.go('/staff/clients/new'),
            icon: const Icon(Icons.add_business),
          ),
        ],
      ),
      body: clients.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Clients could not be loaded.')),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No Clients yet.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final client = items[index];
                  return Card(
                    child: ListTile(
                      title: Text(
                        '${client.clientNumber}  ${client.displayName}',
                      ),
                      subtitle: Text(
                        [
                          if (client.email != null) client.email!,
                          client.accountState,
                          '${client.projectCount} projects',
                        ].join(' - '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/staff/clients/${client.id}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class OwnerClientDetailScreen extends ConsumerWidget {
  const OwnerClientDetailScreen({required this.clientId, super.key});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(ownerClientDetailProvider(clientId));
    final projects = ref.watch(ownerClientProjectsProvider(clientId));
    final invitation = ref.watch(ownerClientInvitationStatusProvider(clientId));
    return Scaffold(
      appBar: AppBar(title: const Text('Client')),
      body: client.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Client could not be loaded.')),
        data: (client) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Panel(
              title: '${client.clientNumber}  ${client.displayName}',
              children: [
                _Info('Status', client.status),
                invitation.when(
                  loading: () => const _Info('Invitation', 'Loading'),
                  error: (_, _) => _Info('Invitation', client.accountState),
                  data: (data) => _Info(
                    'Invitation',
                    (data['invitation'] as Map?)?['status']?.toString() ??
                        data['status']?.toString() ??
                        client.accountState,
                  ),
                ),
                if (client.email != null) _Info('Email', client.email!),
                if (client.phone != null) _Info('Phone', client.phone!),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () =>
                          context.go('/staff/clients/$clientId/edit'),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                    OutlinedButton.icon(
                      onPressed: client.portalUserId == null
                          ? () async {
                              await ref
                                  .read(ownerClientsProjectsRepositoryProvider)
                                  .sendInvitation(client.id);
                              ref.invalidate(
                                ownerClientInvitationStatusProvider(clientId),
                              );
                              ref.invalidate(
                                ownerClientDetailProvider(clientId),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.mark_email_unread),
                      label: const Text('Send Invitation'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.go('/staff/projects/new?clientId=$clientId'),
                      icon: const Icon(Icons.work),
                      label: const Text('New Project'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Projects', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            projects.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Projects could not be loaded.'),
              data: (items) => Column(
                children: [
                  for (final project in items)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${project.projectNumber}  ${project.name}',
                        ),
                        subtitle: Text(project.status),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.go('/staff/projects/${project.id}'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OwnerProjectListScreen extends ConsumerWidget {
  const OwnerProjectListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(ownerProjectListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            tooltip: 'Create Project',
            onPressed: () => context.go('/staff/projects/new'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Projects could not be loaded.')),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No Projects yet.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final project = items[index];
                  return Card(
                    child: ListTile(
                      title: Text('${project.projectNumber}  ${project.name}'),
                      subtitle: Text(
                        [
                          project.status,
                          project.reportingCurrencyCode,
                          if (project.clientNumber != null)
                            project.clientNumber!,
                          if (project.clientName != null) project.clientName!,
                        ].join(' - '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/staff/projects/${project.id}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class OwnerProjectDetailScreen extends ConsumerWidget {
  const OwnerProjectDetailScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(ownerProjectDetailProvider(projectId));
    return Scaffold(
      appBar: AppBar(title: const Text('Project')),
      body: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Project could not be loaded.')),
        data: (project) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Panel(
              title: '${project.projectNumber}  ${project.name}',
              children: [
                _Info('Status', project.status),
                _Info(
                  'Client',
                  [
                    project.clientNumber,
                    project.clientName,
                  ].whereType<String>().join(' - '),
                ),
                _Info('Reporting currency', project.reportingCurrencyCode),
                if (project.location != null)
                  _Info('Location', project.location!),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (project.canEdit)
                      FilledButton.icon(
                        onPressed: () =>
                            context.go('/staff/projects/$projectId/edit'),
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                    for (final status in project.nextStatuses)
                      OutlinedButton(
                        onPressed: () async {
                          final reason = status == 'CANCELLED'
                              ? await _cancelReason(context)
                              : null;
                          if (status == 'CANCELLED' && reason == null) return;
                          await ref
                              .read(ownerClientsProjectsRepositoryProvider)
                              .transitionProject(
                                projectId: project.id,
                                expectedVersionNumber: project.versionNumber,
                                newStatus: status,
                                cancellationReason: reason,
                              );
                          ref.invalidate(ownerProjectDetailProvider(projectId));
                        },
                        child: Text(status.replaceAll('_', ' ')),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.go('/staff/documents'),
                  icon: const Icon(Icons.description),
                  label: const Text('Documents'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/staff/photographs'),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Photographs'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/staff/client-payments'),
                  icon: const Icon(Icons.payments),
                  label: const Text('Client Payments'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/staff/project-expenses'),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Expenses'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class OwnerClientFormScreen extends ConsumerStatefulWidget {
  const OwnerClientFormScreen({this.clientId, super.key});
  final String? clientId;

  @override
  ConsumerState<OwnerClientFormScreen> createState() =>
      _OwnerClientFormScreenState();
}

class _OwnerClientFormScreenState extends ConsumerState<OwnerClientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  int? _version;

  @override
  Widget build(BuildContext context) {
    final detail = widget.clientId == null
        ? null
        : ref.watch(ownerClientDetailProvider(widget.clientId!));
    detail?.whenData((client) {
      if (_version == null) {
        _name.text = client.displayName;
        _email.text = client.email ?? '';
        _phone.text = client.phone ?? '';
        _version = client.versionNumber;
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clientId == null ? 'New Client' : 'Edit Client'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Client name'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final saved = await ref
                    .read(ownerClientsProjectsRepositoryProvider)
                    .saveClient(
                      clientId: widget.clientId,
                      expectedVersionNumber: _version,
                      displayName: _name.text,
                      email: _email.text,
                      phone: _phone.text,
                    );
                if (context.mounted) context.go('/staff/clients/${saved.id}');
              },
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class OwnerProjectFormScreen extends ConsumerStatefulWidget {
  const OwnerProjectFormScreen({
    this.projectId,
    this.initialClientId,
    this.contractorDefaultReportingCurrencyCode = 'USD',
    super.key,
  });
  final String? projectId;
  final String? initialClientId;
  final String? contractorDefaultReportingCurrencyCode;

  @override
  ConsumerState<OwnerProjectFormScreen> createState() =>
      _OwnerProjectFormScreenState();
}

class _OwnerProjectFormScreenState
    extends ConsumerState<OwnerProjectFormScreen> {
  static const _reportingCurrencyCodes = ['USD', 'SAR', 'YER'];

  final _formKey = GlobalKey<FormState>();
  final _reportingCurrencyFieldKey = GlobalKey<FormFieldState<String>>();
  final _name = TextEditingController();
  final _location = TextEditingController();
  String? _clientId;
  String? _reportingCurrencyCode;
  int? _version;

  @override
  void initState() {
    super.initState();
    _clientId = widget.initialClientId;
    final contractorDefault = widget.contractorDefaultReportingCurrencyCode;
    _reportingCurrencyCode = _reportingCurrencyCodes.contains(contractorDefault)
        ? contractorDefault
        : 'USD';
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(ownerClientListProvider);
    final detail = widget.projectId == null
        ? null
        : ref.watch(ownerProjectDetailProvider(widget.projectId!));
    detail?.whenData((project) {
      if (_version == null) {
        _name.text = project.name;
        _reportingCurrencyCode = project.reportingCurrencyCode;
        _location.text = project.location ?? '';
        _clientId = project.clientId;
        _version = project.versionNumber;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _reportingCurrencyFieldKey.currentState?.didChange(
            project.reportingCurrencyCode,
          );
        });
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectId == null ? 'New Project' : 'Edit Project'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            clients.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Clients could not be loaded.'),
              data: (items) => DropdownButtonFormField<String>(
                initialValue: _clientId,
                decoration: const InputDecoration(labelText: 'Client'),
                items: [
                  for (final client in items)
                    DropdownMenuItem(
                      value: client.id,
                      child: Text(client.pickerLabel),
                    ),
                ],
                onChanged: widget.projectId == null
                    ? (value) => setState(() => _clientId = value)
                    : null,
                validator: (value) => value == null ? 'Required' : null,
              ),
            ),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Project name'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            DropdownButtonFormField<String>(
              key: _reportingCurrencyFieldKey,
              initialValue: _reportingCurrencyCode,
              decoration: const InputDecoration(
                labelText: 'Reporting currency',
              ),
              items: [
                for (final code in _reportingCurrencyCodes)
                  DropdownMenuItem(value: code, child: Text(code)),
              ],
              onChanged: (value) =>
                  setState(() => _reportingCurrencyCode = value),
              validator: (value) => value == null ? 'Required' : null,
            ),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final saved = await ref
                    .read(ownerClientsProjectsRepositoryProvider)
                    .saveProject(
                      projectId: widget.projectId,
                      expectedVersionNumber: _version,
                      clientId: _clientId!,
                      name: _name.text,
                      reportingCurrencyCode: _reportingCurrencyCode!,
                      location: _location.text,
                    );
                if (context.mounted) context.go('/staff/projects/${saved.id}');
              },
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text('$label: $value'),
  );
}

Future<String?> _cancelReason(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cancel Project'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Reason'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Cancel Project'),
        ),
      ],
    ),
  );
}
