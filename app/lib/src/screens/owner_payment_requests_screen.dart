import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../payments/owner_payment_models.dart';
import '../payments/owner_payment_providers.dart';

class OwnerPaymentRequestsScreen extends ConsumerStatefulWidget {
  const OwnerPaymentRequestsScreen({super.key});
  @override
  ConsumerState<OwnerPaymentRequestsScreen> createState() =>
      _OwnerPaymentRequestsScreenState();
}

class _OwnerPaymentRequestsScreenState
    extends ConsumerState<OwnerPaymentRequestsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(ownerPaymentRequestListProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(ownerPaymentRequestListProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Payment Requests',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref
                    .read(ownerPaymentRequestListProvider.notifier)
                    .refresh(),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Create'),
                onPressed: () => _create(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.when(
              loading: () =>
                  const Center(child: Text('Loading payment requests...')),
              error: (_, _) => const Center(
                child: Text('Payment requests could not be loaded.'),
              ),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('No payment requests found.'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: Icon(
                            item.status == 'SENT'
                                ? Icons.mark_email_read
                                : Icons.request_quote,
                          ),
                          title: Text(
                            '${item.requestNumber} - ${item.moneyDisplay}',
                          ),
                          subtitle: Text(
                            '${item.effectiveStatus} - due ${item.dueDate ?? 'not set'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go(
                            '/staff/payment-requests/${item.paymentRequestId}',
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final draft = await showModalBottomSheet<OwnerPaymentRequestDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _RequestForm(),
    );
    if (draft == null) return;
    try {
      final result = await ref
          .read(ownerPaymentRepositoryProvider)
          .createRequest(draft);
      await ref.read(ownerPaymentRequestListProvider.notifier).refresh();
      if (context.mounted && result.paymentRequestId != null) {
        context.go('/staff/payment-requests/${result.paymentRequestId}');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment request could not be created.'),
          ),
        );
      }
    }
  }
}

class OwnerPaymentRequestDetailScreen extends ConsumerWidget {
  const OwnerPaymentRequestDetailScreen({
    required this.paymentRequestId,
    super.key,
  });
  final String paymentRequestId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      ownerPaymentRequestDetailProvider(paymentRequestId),
    );
    return state.when(
      loading: () => const Center(child: Text('Loading payment request...')),
      error: (_, _) =>
          const Center(child: Text('Payment request could not be loaded.')),
      data: (item) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            item.requestNumber,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (item.isDraft)
                ActionChip(
                  avatar: const Icon(Icons.edit),
                  label: const Text('Edit Draft'),
                  onPressed: () => _edit(context, ref, item),
                ),
              if (item.canSend)
                ActionChip(
                  avatar: const Icon(Icons.send),
                  label: const Text('Send'),
                  onPressed: () => _run(
                    context,
                    'Sent.',
                    () => ref
                        .read(
                          ownerPaymentRequestDetailProvider(
                            paymentRequestId,
                          ).notifier,
                        )
                        .send(),
                  ),
                ),
              if (item.status == 'SENT' ||
                  item.status == 'VIEWED' ||
                  item.status == 'OVERDUE')
                ActionChip(
                  avatar: const Icon(Icons.block),
                  label: const Text('Cancel'),
                  onPressed: () => _cancel(context, ref),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _Meta('Amount', item.moneyDisplay),
          _Meta('Client', item.clientDisplay),
          _Meta('Project', item.projectDisplay),
          _Meta('Status', item.effectiveStatus),
          if (item.requestDate != null)
            _Meta('Request date', item.requestDate!),
          if (item.dueDate != null) _Meta('Due date', item.dueDate!),
          if (item.description != null) _Meta('Description', item.description!),
          if (item.sentAt != null) _Meta('Sent', item.sentAt!),
          if (item.viewedAt != null) _Meta('Viewed', item.viewedAt!),
          if (item.cancelledAt != null) _Meta('Cancelled', item.cancelledAt!),
          if (item.cancellationReason != null)
            _Meta('Cancellation reason', item.cancellationReason!),
          if (item.paidAmount != null)
            _Meta('Paid', '${item.currencyCode} ${item.paidAmount!}'),
          if (item.remainingAmount != null)
            _Meta('Remaining', '${item.currencyCode} ${item.remainingAmount!}'),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    OwnerPaymentRequest item,
  ) async {
    final draft = await showModalBottomSheet<OwnerPaymentRequestDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RequestForm(item: item),
    );
    if (draft == null || !context.mounted) return;
    await _run(
      context,
      'Draft updated.',
      () => ref
          .read(ownerPaymentRequestDetailProvider(paymentRequestId).notifier)
          .createOrUpdate(draft),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = await _reason(context, 'Cancel payment request');
    if (reason == null || !context.mounted) return;
    await _run(
      context,
      'Cancelled.',
      () => ref
          .read(ownerPaymentRequestDetailProvider(paymentRequestId).notifier)
          .cancel(reason),
    );
  }
}

class _RequestForm extends ConsumerStatefulWidget {
  const _RequestForm({this.item});
  final OwnerPaymentRequest? item;
  @override
  ConsumerState<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends ConsumerState<_RequestForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _project = TextEditingController(
    text: widget.item?.projectId,
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.item?.requestedAmount,
  );
  late final TextEditingController _currency = TextEditingController(
    text: widget.item?.currencyCode ?? 'USD',
  );
  late final TextEditingController _requestDate = TextEditingController(
    text:
        widget.item?.requestDate ??
        DateTime.now().toIso8601String().substring(0, 10),
  );
  late final TextEditingController _dueDate = TextEditingController(
    text: widget.item?.dueDate,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.item?.description,
  );
  OwnerPaymentProjectOption? _projectOption;
  late final Future<List<OwnerPaymentProjectOption>> _projects;
  @override
  void initState() {
    super.initState();
    _projects = ref.read(ownerPaymentRepositoryProvider).projectLookups();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<OwnerPaymentProjectOption>>(
    future: _projects,
    builder: (context, snapshot) {
      final projects = snapshot.data ?? const <OwnerPaymentProjectOption>[];
      _projectOption ??= projects
          .where((p) => p.projectId == widget.item?.projectId)
          .firstOrNull;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: Form(
            key: _key,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  widget.item == null ? 'Create payment request' : 'Edit draft',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                DropdownButtonFormField<OwnerPaymentProjectOption>(
                  initialValue: _projectOption,
                  items: [
                    for (final p in projects)
                      DropdownMenuItem(value: p, child: Text(p.display)),
                  ],
                  onChanged: (value) => setState(() {
                    _projectOption = value;
                    _project.text = value?.projectId ?? '';
                  }),
                  decoration: const InputDecoration(labelText: 'Project'),
                  validator: (value) => value == null ? 'Required' : null,
                ),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _money,
                ),
                TextFormField(
                  controller: _currency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  validator: _currencyValidator,
                ),
                TextFormField(
                  controller: _requestDate,
                  decoration: const InputDecoration(labelText: 'Request date'),
                  validator: _dateValidator,
                ),
                TextFormField(
                  controller: _dueDate,
                  decoration: const InputDecoration(labelText: 'Due date'),
                ),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save Draft'),
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  void _submit() {
    if (_key.currentState?.validate() != true) return;
    Navigator.of(context).pop(
      OwnerPaymentRequestDraft(
        projectId: _project.text.trim(),
        requestedAmount: _amount.text.trim(),
        currencyCode: _currency.text.trim().toUpperCase(),
        requestDate: _optional(_requestDate.text),
        dueDate: _optional(_dueDate.text),
        description: _optional(_description.text),
      ),
    );
  }
}

Future<void> _run(
  BuildContext context,
  String ok,
  Future<bool> Function() action,
) async {
  final success = await action();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(success ? ok : 'Payment request action failed.')),
  );
}

Future<String?> _reason(BuildContext context, String title) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Reason'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) Navigator.of(context).pop(text);
          },
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
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

String? _money(String? value) =>
    RegExp(r'^\d+(\.\d+)?$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Use a positive exact amount';
String? _dateValidator(String? value) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Use YYYY-MM-DD';
String? _currencyValidator(String? value) =>
    RegExp(r'^[A-Za-z]{3}$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Use a 3-letter currency';
String? _optional(String value) => value.trim().isEmpty ? null : value.trim();
