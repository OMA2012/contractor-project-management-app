import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account_transfers/account_transfer_models.dart';
import '../account_transfers/account_transfer_providers.dart';
import '../financial_accounts/financial_account_models.dart';
import '../financial_accounts/financial_account_providers.dart';

class OwnerAccountTransfersScreen extends ConsumerStatefulWidget {
  const OwnerAccountTransfersScreen({super.key});
  @override
  ConsumerState<OwnerAccountTransfersScreen> createState() =>
      _OwnerAccountTransfersScreenState();
}

class _OwnerAccountTransfersScreenState
    extends ConsumerState<OwnerAccountTransfersScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(accountTransferListProvider.notifier).load();
      ref.read(financialAccountListProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(accountTransferListProvider);
    final accounts = ref.watch(financialAccountListProvider).accounts;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Account Transfers',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.read(accountTransferListProvider.notifier).refresh(),
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
                  const Center(child: Text('Loading account transfers...')),
              error: (_, _) => const Center(
                child: Text('Account transfers could not be loaded.'),
              ),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('No account transfers found.'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: Icon(
                            item.isPosted ? Icons.verified : Icons.swap_horiz,
                          ),
                          title: Text(
                            '${item.eventNumber} - ${item.moneyDisplay}',
                          ),
                          subtitle: Text(
                            '${_name(accounts, item.sourceAccountId)} -> ${_name(accounts, item.destinationAccountId)} - ${item.transferDate} - ${item.eventStatus}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go(
                            '/staff/account-transfers/${item.financialEventId}',
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
    final draft = await showModalBottomSheet<AccountTransferDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _TransferForm(),
    );
    if (draft == null) return;
    try {
      final result = await ref
          .read(accountTransferRepositoryProvider)
          .create(draft);
      await ref.read(accountTransferListProvider.notifier).refresh();
      if (context.mounted) {
        context.go('/staff/account-transfers/${result.financialEventId}');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account transfer could not be created.'),
          ),
        );
      }
    }
  }
}

class OwnerAccountTransferDetailScreen extends ConsumerWidget {
  const OwnerAccountTransferDetailScreen({
    required this.financialEventId,
    super.key,
  });
  final String financialEventId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountTransferDetailProvider(financialEventId));
    final accounts = ref.watch(financialAccountListProvider).accounts;
    if (accounts.isEmpty) {
      Future.microtask(
        () => ref.read(financialAccountListProvider.notifier).load(),
      );
    }
    return state.when(
      loading: () => const Center(child: Text('Loading account transfer...')),
      error: (_, _) =>
          const Center(child: Text('Account transfer could not be loaded.')),
      data: (item) {
        final source = _find(accounts, item.sourceAccountId);
        final destination = _find(accounts, item.destinationAccountId);
        return ListView(
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
                            accountTransferDetailProvider(
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
                            accountTransferDetailProvider(
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
            const SizedBox(height: 16),
            _Meta('Amount', item.moneyDisplay),
            _Meta(
              'Source account',
              _accountDisplay(source, item.sourceAccountId),
            ),
            _Meta(
              'Destination account',
              _accountDisplay(destination, item.destinationAccountId),
            ),
            _Meta('Transfer date', item.transferDate),
            _Meta('Status', item.isPosted ? 'Posted' : item.eventStatus),
            _Meta('Transaction', item.transactionStatus),
            _Meta(
              'Projected Balance Change',
              'Source -${item.amount} ${item.currencyCode} / Destination +${item.amount} ${item.currencyCode}',
            ),
            if (source?.balance != null)
              _Meta(
                'Source Before -> After',
                '${source!.balance!.display} -> ${item.currencyCode} ${_sub(source.balance!.amount, item.amount)}',
              ),
            if (destination?.balance != null)
              _Meta(
                'Destination Before -> After',
                '${destination!.balance!.display} -> ${item.currencyCode} ${_add(destination.balance!.amount, item.amount)}',
              ),
            if (item.reference != null) _Meta('Reference', item.reference!),
            if (item.notes != null) _Meta('Notes', item.notes!),
            if (item.reportingCurrencyCode != null)
              _Meta('Reporting currency', item.reportingCurrencyCode!),
            if (item.rejectionReason != null)
              _Meta('Rejection reason', item.rejectionReason!),
            if (item.isPosted)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Posted transfers are immutable and balances derive from posted ledger entries.',
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AccountTransfer item,
  ) async {
    final draft = await showModalBottomSheet<AccountTransferDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TransferForm(item: item),
    );
    if (draft == null || !context.mounted) return;
    await _run(
      context,
      ref,
      'Draft updated.',
      () => ref
          .read(accountTransferDetailProvider(financialEventId).notifier)
          .createOrUpdate(draft),
    );
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final reason = await _reason(context);
    if (reason == null || !context.mounted) return;
    await _run(
      context,
      ref,
      'Rejected.',
      () => ref
          .read(accountTransferDetailProvider(financialEventId).notifier)
          .reject(reason),
    );
  }
}

class _TransferForm extends ConsumerStatefulWidget {
  const _TransferForm({this.item});
  final AccountTransfer? item;
  @override
  ConsumerState<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends ConsumerState<_TransferForm> {
  final _key = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.item?.amount);
  late final _date = TextEditingController(
    text:
        widget.item?.transferDate ??
        DateTime.now().toIso8601String().substring(0, 10),
  );
  late final _reference = TextEditingController(text: widget.item?.reference);
  late final _notes = TextEditingController(text: widget.item?.notes);
  FinancialAccount? _source;
  FinancialAccount? _destination;

  @override
  Widget build(BuildContext context) {
    final accounts = ref
        .watch(financialAccountListProvider)
        .accounts
        .where((a) => a.isActive && !a.isArchived)
        .toList();
    _source ??= accounts
        .where((a) => a.id == widget.item?.sourceAccountId)
        .firstOrNull;
    _destination ??= accounts
        .where((a) => a.id == widget.item?.destinationAccountId)
        .firstOrNull;
    final destinations = accounts
        .where(
          (a) =>
              _source == null ||
              (a.currencyCode == _source!.currencyCode && a.id != _source!.id),
        )
        .toList();
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
                widget.item == null ? 'Create account transfer' : 'Edit draft',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              DropdownButtonFormField<FinancialAccount>(
                initialValue: _source,
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                      value: a,
                      child: Text(_accountDisplay(a, a.id)),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _source = value;
                  if (_destination?.currencyCode != value?.currencyCode ||
                      _destination?.id == value?.id) {
                    _destination = null;
                  }
                }),
                validator: (value) => value == null ? 'Required' : null,
                decoration: const InputDecoration(labelText: 'Source account'),
              ),
              DropdownButtonFormField<FinancialAccount>(
                initialValue: destinations.contains(_destination)
                    ? _destination
                    : null,
                items: [
                  for (final a in destinations)
                    DropdownMenuItem(
                      value: a,
                      child: Text(_accountDisplay(a, a.id)),
                    ),
                ],
                onChanged: (value) => setState(() => _destination = value),
                validator: (value) => value == null ? 'Required' : null,
                decoration: const InputDecoration(
                  labelText: 'Destination account',
                ),
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
                controller: _date,
                decoration: const InputDecoration(labelText: 'Transfer date'),
                validator: _dateValidator,
              ),
              TextFormField(
                controller: _reference,
                decoration: const InputDecoration(labelText: 'Reference'),
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
    if (_key.currentState?.validate() != true ||
        _source == null ||
        _destination == null) {
      return;
    }
    Navigator.of(context).pop(
      AccountTransferDraft(
        sourceAccountId: _source!.id,
        destinationAccountId: _destination!.id,
        amount: _amount.text.trim(),
        currencyCode: _source!.currencyCode,
        transferDate: _date.text.trim(),
        reference: _optional(_reference.text),
        notes: _optional(_notes.text),
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
        success
            ? ok
            : 'Account transfer action failed. No financial data was changed.',
      ),
    ),
  );
}

Future<String?> _reason(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reject account transfer'),
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
          width: 170,
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

FinancialAccount? _find(List<FinancialAccount> accounts, String id) =>
    accounts.where((a) => a.id == id).firstOrNull;
String _name(List<FinancialAccount> accounts, String id) =>
    _find(accounts, id)?.name ?? id;
String _accountDisplay(FinancialAccount? account, String fallback) {
  if (account == null) return fallback;
  if (!account.isBank) {
    return '${account.name} - Cash - ${account.currencyCode}';
  }
  final suffix = account.maskedAccountIdentifier == null
      ? ''
      : ' - ${account.maskedAccountIdentifier}';
  final bank = account.bankName == null ? '' : ' - ${account.bankName}';
  return '${account.name} - Bank - ${account.currencyCode}$bank$suffix';
}

String _add(String a, String b) => _decimalMath(a, b, add: true);
String _sub(String a, String b) => _decimalMath(a, b, add: false);
String _decimalMath(String a, String b, {required bool add}) {
  final scale = _scale(a, b);
  final left = _minor(a, scale);
  final right = _minor(b, scale);
  final result = add ? left + right : left - right;
  final sign = result.isNegative ? '-' : '';
  final digits = result.abs().toString().padLeft(scale + 1, '0');
  if (scale == 0) return '$sign$digits';
  return '$sign${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}';
}

BigInt _minor(String value, int scale) {
  final parts = value.split('.');
  final units = parts.first.isEmpty ? '0' : parts.first;
  final decimals = parts.length > 1 ? parts[1] : '';
  return BigInt.parse('$units${decimals.padRight(scale, '0')}');
}

int _scale(String a, String b) => [a, b]
    .map((v) => v.contains('.') ? v.split('.').last.length : 0)
    .reduce((x, y) => x > y ? x : y);
String? _money(String? value) =>
    RegExp(r'^\d+(\.\d+)?$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Use a positive exact amount';
String? _dateValidator(String? value) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Use YYYY-MM-DD';
String? _optional(String value) => value.trim().isEmpty ? null : value.trim();
