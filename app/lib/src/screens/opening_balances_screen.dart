import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../financial_accounts/financial_account_models.dart';
import '../financial_accounts/financial_account_providers.dart';
import '../opening_balances/opening_balance_models.dart';
import '../opening_balances/opening_balance_providers.dart';

class OpeningBalancesScreen extends ConsumerStatefulWidget {
  const OpeningBalancesScreen({super.key});

  @override
  ConsumerState<OpeningBalancesScreen> createState() =>
      _OpeningBalancesScreenState();
}

class _OpeningBalancesScreenState extends ConsumerState<OpeningBalancesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(openingBalanceListProvider.notifier).load();
      ref.read(financialAccountListProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(openingBalanceListProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Opening Balances',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.read(openingBalanceListProvider.notifier).refresh(),
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
            child: items.when(
              loading: () =>
                  const Center(child: Text('Loading opening balances...')),
              error: (_, _) => const Center(
                child: Text('Opening balances could not be loaded.'),
              ),
              data: (rows) => rows.isEmpty
                  ? const Center(child: Text('No opening balances found.'))
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = rows[index];
                        return ListTile(
                          leading: const Icon(Icons.account_balance_wallet),
                          title: Text(
                            '${item.eventNumber} - ${item.moneyDisplay}',
                          ),
                          subtitle: Text(
                            '${item.openingDate} - ${item.eventStatus} - ${item.transactionStatus}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go(
                            '/staff/opening-balances/${item.financialEventId}',
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
    final draft = await showModalBottomSheet<OpeningBalanceDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _OpeningBalanceForm(),
    );
    if (draft == null) return;
    try {
      final result = await ref
          .read(openingBalanceRepositoryProvider)
          .create(draft);
      await ref.read(openingBalanceListProvider.notifier).refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening balance saved successfully.')),
        );
        context.go('/staff/opening-balances/${result.financialEventId}');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening balance could not be created.'),
          ),
        );
      }
    }
  }
}

class OpeningBalanceDetailScreen extends ConsumerWidget {
  const OpeningBalanceDetailScreen({required this.financialEventId, super.key});

  final String financialEventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(openingBalanceDetailProvider(financialEventId));
    return state.when(
      loading: () => const Center(child: Text('Loading opening balance...')),
      error: (_, _) =>
          const Center(child: Text('Opening balance could not be loaded.')),
      data: (item) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            item.eventNumber,
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
              if (item.isDraft)
                ActionChip(
                  avatar: const Icon(Icons.send),
                  label: const Text('Submit'),
                  onPressed: () => _run(
                    context,
                    ref,
                    'Submitted.',
                    () => ref
                        .read(
                          openingBalanceDetailProvider(
                            financialEventId,
                          ).notifier,
                        )
                        .submit(),
                  ),
                ),
              if (item.isSubmitted) ...[
                ActionChip(
                  avatar: const Icon(Icons.verified),
                  label: const Text('Approve & Post'),
                  onPressed: () => _run(
                    context,
                    ref,
                    'Approved and posted.',
                    () => ref
                        .read(
                          openingBalanceDetailProvider(
                            financialEventId,
                          ).notifier,
                        )
                        .approve(),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.block),
                  label: const Text('Reject'),
                  onPressed: () => _reject(context, ref),
                ),
              ],
            ],
          ),
          if (item.isSubmitted)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Created by me - another Owner required where applicable. Approval eligibility is enforced by the backend.',
              ),
            ),
          const SizedBox(height: 16),
          _Meta('Amount', item.moneyDisplay),
          _Meta('Opening date', item.openingDate),
          _Meta('Status', item.isPosted ? 'Posted' : item.eventStatus),
          _Meta('Transaction', item.transactionStatus),
          if (item.reportingCurrencyCode != null)
            _Meta('Reporting currency', item.reportingCurrencyCode!),
          if (item.description != null) _Meta('Description', item.description!),
          if (item.notes != null) _Meta('Notes', item.notes!),
          if (item.rejectionReason != null)
            _Meta('Rejection reason', item.rejectionReason!),
          if (item.submittedAt != null) _Meta('Submitted', item.submittedAt!),
          if (item.approvedAt != null)
            _Meta('Approved/posted', item.approvedAt!),
          if (item.rejectedAt != null) _Meta('Rejected', item.rejectedAt!),
          if (item.isPosted)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Posted opening balances are immutable. Corrections require an approved reversal or adjustment workflow.',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    OpeningBalance item,
  ) async {
    await ref.read(financialAccountListProvider.notifier).load();
    if (!context.mounted) return;
    final draft = await showModalBottomSheet<OpeningBalanceDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _OpeningBalanceForm(item: item),
    );
    if (draft == null) return;
    if (!context.mounted) return;
    await _run(
      context,
      ref,
      'Draft updated.',
      () => ref
          .read(openingBalanceDetailProvider(financialEventId).notifier)
          .createOrUpdate(draft),
    );
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _RejectDialog(),
    );
    if (reason == null) return;
    if (!context.mounted) return;
    await _run(
      context,
      ref,
      'Rejected.',
      () => ref
          .read(openingBalanceDetailProvider(financialEventId).notifier)
          .reject(reason),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    String ok,
    Future<bool> Function() action,
  ) async {
    final success = await action();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? ok
              : 'Opening balance action failed. No financial data was changed.',
        ),
      ),
    );
  }
}

class FinancialApprovalQueueScreen extends ConsumerStatefulWidget {
  const FinancialApprovalQueueScreen({super.key});
  @override
  ConsumerState<FinancialApprovalQueueScreen> createState() =>
      _FinancialApprovalQueueScreenState();
}

class _FinancialApprovalQueueScreenState
    extends ConsumerState<FinancialApprovalQueueScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(financialApprovalQueueProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financialApprovalQueueProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: state.when(
        loading: () =>
            const Center(child: Text('Loading financial approval queue...')),
        error: (_, _) => const Center(
          child: Text('Financial approval queue could not be loaded.'),
        ),
        data: (queue) => ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Financial Approval Queue',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      ref.read(financialApprovalQueueProvider.notifier).load(),
                ),
              ],
            ),
            _QueueSection('Eligible for My Approval', queue.eligible),
            _QueueSection(
              'Created by Me - Another Owner Required',
              queue.createdByMe,
            ),
            _QueueSection('Recently Approved / Posted', queue.recent),
            _QueueSection('Rejected', queue.rejected),
          ],
        ),
      ),
    );
  }
}

class _QueueSection extends StatelessWidget {
  const _QueueSection(this.title, this.items);
  final String title;
  final List<FinancialApprovalQueueItem> items;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No items.'),
          )
        else
          ...items.map(
            (item) => ListTile(
              leading: Icon(
                item.eligibleForMyApproval
                    ? Icons.verified_user
                    : Icons.history,
              ),
              title: Text('${item.eventNumber} - ${item.moneyDisplay}'),
              subtitle: Text(
                '${item.eventType} - ${item.relatedLabel} - ${item.eventStatus}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(_queueTarget(item)),
            ),
          ),
      ],
    ),
  );
}

String _queueTarget(FinancialApprovalQueueItem item) {
  return switch (item.eventType) {
    'OPENING_BALANCE' => '/staff/opening-balances/${item.financialEventId}',
    'CLIENT_PAYMENT' => '/staff/client-payments/${item.financialEventId}',
    'PROJECT_EXPENSE' => '/staff/project-expenses/${item.financialEventId}',
    'REVERSAL' => '/staff/financial-reversals/${item.financialEventId}',
    'ADJUSTMENT' => '/staff/financial-adjustments/${item.financialEventId}',
    _ => '/staff/financial-approval-queue',
  };
}

class _OpeningBalanceForm extends ConsumerStatefulWidget {
  const _OpeningBalanceForm({this.item});
  final OpeningBalance? item;
  @override
  ConsumerState<_OpeningBalanceForm> createState() =>
      _OpeningBalanceFormState();
}

class _OpeningBalanceFormState extends ConsumerState<_OpeningBalanceForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _date;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  FinancialAccount? _account;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.item?.amount);
    _date = TextEditingController(
      text:
          widget.item?.openingDate ??
          DateTime.now().toIso8601String().substring(0, 10),
    );
    _description = TextEditingController(text: widget.item?.description);
    _notes = TextEditingController(text: widget.item?.notes);
    Future.microtask(
      () => ref.read(financialAccountListProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref
        .watch(financialAccountListProvider)
        .accounts
        .where((a) => a.isActive && !a.isArchived)
        .toList();
    _account ??= accounts
        .where((a) => a.id == widget.item?.financialAccountId)
        .firstOrNull;
    _account ??= accounts.firstOrNull;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                widget.item == null ? 'Create opening balance' : 'Edit draft',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              DropdownButtonFormField<FinancialAccount>(
                initialValue: _account,
                items: [
                  for (final account in accounts)
                    DropdownMenuItem(
                      value: account,
                      child: Text('${account.name} - ${account.currencyCode}'),
                    ),
                ],
                onChanged: (value) => setState(() => _account = value),
                validator: (value) => value == null ? 'Required' : null,
                decoration: const InputDecoration(
                  labelText: 'Financial account',
                ),
              ),
              TextFormField(
                controller: _amount,
                decoration: const InputDecoration(labelText: 'Opening amount'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: _money,
              ),
              TextFormField(
                controller: _date,
                decoration: const InputDecoration(labelText: 'Opening date'),
                validator: _dateValidator,
              ),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: _required,
              ),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
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
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true || _account == null) return;
    Navigator.of(context).pop(
      OpeningBalanceDraft(
        financialAccountId: _account!.id,
        amount: _amount.text.trim(),
        openingDate: _date.text.trim(),
        reportingCurrencyCode: _account!.currencyCode,
        description: _description.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
  String? _money(String? value) =>
      RegExp(r'^\d+(\.\d+)?$').hasMatch(value?.trim() ?? '')
      ? null
      : 'Use a positive exact amount';
  String? _dateValidator(String? value) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value?.trim() ?? '')
      ? null
      : 'Use YYYY-MM-DD';
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final controller = TextEditingController();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reject opening balance'),
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
        child: const Text('Reject'),
      ),
    ],
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
