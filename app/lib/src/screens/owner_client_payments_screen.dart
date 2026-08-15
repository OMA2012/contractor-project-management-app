import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../financial_accounts/financial_account_models.dart';
import '../financial_accounts/financial_account_providers.dart';
import '../payments/owner_payment_models.dart';
import '../payments/owner_payment_providers.dart';

class OwnerClientPaymentsScreen extends ConsumerStatefulWidget {
  const OwnerClientPaymentsScreen({super.key});
  @override
  ConsumerState<OwnerClientPaymentsScreen> createState() =>
      _OwnerClientPaymentsScreenState();
}

class _OwnerClientPaymentsScreenState
    extends ConsumerState<OwnerClientPaymentsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(ownerClientPaymentListProvider.notifier).load();
      ref.read(financialAccountListProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(ownerClientPaymentListProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Client Payments',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.read(ownerClientPaymentListProvider.notifier).refresh(),
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
                  const Center(child: Text('Loading client payments...')),
              error: (_, _) => const Center(
                child: Text('Client payments could not be loaded.'),
              ),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('No client payments found.'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: Icon(
                            item.isPosted ? Icons.verified : Icons.payments,
                          ),
                          title: Text(
                            '${item.eventNumber} - ${item.moneyDisplay}',
                          ),
                          subtitle: Text(
                            '${item.receivedDate} - ${item.verificationLabel}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go(
                            '/staff/client-payments/${item.financialEventId}',
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
    final draft = await showModalBottomSheet<OwnerClientPaymentDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _PaymentForm(),
    );
    if (draft == null) return;
    try {
      final result = await ref
          .read(ownerPaymentRepositoryProvider)
          .createPayment(draft);
      await ref.read(ownerClientPaymentListProvider.notifier).refresh();
      if (context.mounted && result.financialEventId != null) {
        context.go('/staff/client-payments/${result.financialEventId}');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Client payment could not be created.')),
        );
      }
    }
  }
}

class OwnerClientPaymentDetailScreen extends ConsumerWidget {
  const OwnerClientPaymentDetailScreen({
    required this.financialEventId,
    super.key,
  });
  final String financialEventId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ownerClientPaymentDetailProvider(financialEventId));
    return state.when(
      loading: () => const Center(child: Text('Loading client payment...')),
      error: (_, _) =>
          const Center(child: Text('Client payment could not be loaded.')),
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
              if (item.isDraft && !item.isClientSubmitted)
                ActionChip(
                  avatar: const Icon(Icons.edit),
                  label: const Text('Edit Draft'),
                  onPressed: () => _edit(context, ref, item),
                ),
              if (item.isClientSubmitted && item.isSubmitted)
                ActionChip(
                  avatar: const Icon(Icons.account_balance),
                  label: const Text('Set Receiving Account'),
                  onPressed: () => _verify(context, ref, item),
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
                          ownerClientPaymentDetailProvider(
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
                          ownerClientPaymentDetailProvider(
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
                'Another Owner is required where you created this event. Approval eligibility is enforced by the backend.',
              ),
            ),
          if (item.isClientSubmitted && !item.isPosted)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Submitted for verification. This is not a received payment until approved and posted.',
              ),
            ),
          const SizedBox(height: 16),
          _Meta('Amount', item.moneyDisplay),
          _Meta('Client', item.clientId),
          _Meta('Project', item.projectId),
          _Meta('Payment date', item.receivedDate),
          _Meta('Status', item.isPosted ? 'Posted' : item.eventStatus),
          _Meta('Transaction', item.transactionStatus),
          if (item.receivedAccountId != null)
            _Meta('Receiving account', item.receivedAccountId!),
          if (item.paymentReference != null)
            _Meta('Reference', item.paymentReference!),
          if (item.payerName != null) _Meta('Payer', item.payerName!),
          if (item.reportingCurrencyCode != null)
            _Meta('Reporting currency', item.reportingCurrencyCode!),
          if (item.notes != null) _Meta('Notes', item.notes!),
          if (item.rejectionReason != null)
            _Meta('Rejection reason', item.rejectionReason!),
          if (item.approvedAt != null)
            _Meta('Approved/posted', item.approvedAt!),
          if (item.isPosted)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Posted payments are immutable and account balances derive from posted ledger entries.',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    OwnerClientPayment item,
  ) async {
    final draft = await showModalBottomSheet<OwnerClientPaymentDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PaymentForm(item: item),
    );
    if (draft == null || !context.mounted) return;
    await _run(
      context,
      ref,
      'Draft updated.',
      () => ref
          .read(ownerClientPaymentDetailProvider(financialEventId).notifier)
          .createOrUpdate(draft),
    );
  }

  Future<void> _verify(
    BuildContext context,
    WidgetRef ref,
    OwnerClientPayment item,
  ) async {
    await ref.read(financialAccountListProvider.notifier).load();
    if (!context.mounted) return;
    final account = await showModalBottomSheet<FinancialAccount>(
      context: context,
      showDragHandle: true,
      builder: (context) => _AccountPicker(currencyCode: item.currencyCode),
    );
    if (account == null || !context.mounted) return;
    await _run(
      context,
      ref,
      'Receiving account set.',
      () => ref
          .read(ownerClientPaymentDetailProvider(financialEventId).notifier)
          .verifyClientSubmitted(account.id, item.notes),
    );
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final reason = await _reason(context, 'Reject client payment');
    if (reason == null || !context.mounted) return;
    await _run(
      context,
      ref,
      'Rejected.',
      () => ref
          .read(ownerClientPaymentDetailProvider(financialEventId).notifier)
          .reject(reason),
    );
  }
}

class _PaymentForm extends ConsumerStatefulWidget {
  const _PaymentForm({this.item});
  final OwnerClientPayment? item;
  @override
  ConsumerState<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends ConsumerState<_PaymentForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _project = TextEditingController(
    text: widget.item?.projectId,
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.item?.amount,
  );
  late final TextEditingController _currency = TextEditingController(
    text: widget.item?.currencyCode ?? 'USD',
  );
  late final TextEditingController _date = TextEditingController(
    text:
        widget.item?.receivedDate ??
        DateTime.now().toIso8601String().substring(0, 10),
  );
  late final TextEditingController _reference = TextEditingController(
    text: widget.item?.paymentReference,
  );
  late final TextEditingController _payer = TextEditingController(
    text: widget.item?.payerName,
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.item?.notes,
  );
  FinancialAccount? _account;
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(financialAccountListProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref
        .watch(financialAccountListProvider)
        .accounts
        .where(
          (a) =>
              a.isActive &&
              !a.isArchived &&
              a.currencyCode == _currency.text.trim().toUpperCase(),
        )
        .toList();
    _account ??= accounts
        .where((a) => a.id == widget.item?.receivedAccountId)
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
                widget.item == null ? 'Create client payment' : 'Edit draft',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextFormField(
                controller: _project,
                decoration: const InputDecoration(labelText: 'Project ID'),
                validator: _required,
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
                onChanged: (_) => setState(() => _account = null),
              ),
              DropdownButtonFormField<FinancialAccount>(
                initialValue: _account,
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                      value: a,
                      child: Text('${a.name} - ${a.currencyCode}'),
                    ),
                ],
                onChanged: (value) => setState(() => _account = value),
                decoration: const InputDecoration(
                  labelText: 'Receiving account',
                ),
              ),
              TextFormField(
                controller: _date,
                decoration: const InputDecoration(labelText: 'Payment date'),
                validator: _dateValidator,
              ),
              TextFormField(
                controller: _reference,
                decoration: const InputDecoration(labelText: 'Reference'),
              ),
              TextFormField(
                controller: _payer,
                decoration: const InputDecoration(labelText: 'Payer'),
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
    if (_key.currentState?.validate() != true) return;
    Navigator.of(context).pop(
      OwnerClientPaymentDraft(
        projectId: _project.text.trim(),
        amount: _amount.text.trim(),
        currencyCode: _currency.text.trim().toUpperCase(),
        receivedDate: _date.text.trim(),
        receivedAccountId: _account?.id,
        paymentReference: _optional(_reference.text),
        payerName: _optional(_payer.text),
        notes: _optional(_notes.text),
      ),
    );
  }
}

class _AccountPicker extends ConsumerWidget {
  const _AccountPicker({required this.currencyCode});
  final String currencyCode;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref
        .watch(financialAccountListProvider)
        .accounts
        .where(
          (a) => a.isActive && !a.isArchived && a.currencyCode == currencyCode,
        )
        .toList();
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Receiving account',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final account in accounts)
            ListTile(
              title: Text(account.name),
              subtitle: Text('${account.typeCode} - ${account.currencyCode}'),
              onTap: () => Navigator.of(context).pop(account),
            ),
          if (accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No active account matches this payment currency.'),
            ),
        ],
      ),
    );
  }
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
        success ? ok : 'Payment action failed. No financial data was changed.',
      ),
    ),
  );
}

Future<String?> _reason(BuildContext context, String title) async {
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
String? _currencyValidator(String? value) =>
    RegExp(r'^[A-Za-z]{3}$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Use a 3-letter currency';
String? _optional(String value) => value.trim().isEmpty ? null : value.trim();
