import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../financial_accounts/financial_account_models.dart';
import '../financial_accounts/financial_account_providers.dart';

class FinancialAccountsScreen extends ConsumerStatefulWidget {
  const FinancialAccountsScreen({super.key});

  @override
  ConsumerState<FinancialAccountsScreen> createState() =>
      _FinancialAccountsScreenState();
}

class _FinancialAccountsScreenState
    extends ConsumerState<FinancialAccountsScreen> {
  String? _currency;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(financialAccountListProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financialAccountListProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final currencies = _currencies(state);
        final selected =
            _currency ?? (currencies.isEmpty ? null : currencies.first);
        final accounts = selected == null
            ? state.accounts
            : state.accounts.where((a) => a.currencyCode == selected).toList();
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cash & Bank Accounts',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: state.isLoading
                        ? null
                        : () => ref
                              .read(financialAccountListProvider.notifier)
                              .refresh(),
                    icon: const Icon(Icons.refresh),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showAccountForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Create'),
                  ),
                ],
              ),
              if (currencies.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SegmentedButton<String>(
                    segments: [
                      for (final currency in currencies)
                        ButtonSegment(value: currency, label: Text(currency)),
                    ],
                    selected: {selected ?? currencies.first},
                    onSelectionChanged: (value) =>
                        setState(() => _currency = value.single),
                  ),
                ),
              _TotalsRow(
                cashTotals: state.cashTotals,
                bankTotals: state.bankTotals,
                isWide: isWide,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _AccountList(state: state, accounts: accounts),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAccountForm(BuildContext context) async {
    final draft = await showModalBottomSheet<FinancialAccountDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _AccountFormSheet(),
    );
    if (draft == null) {
      return;
    }
    try {
      final result = await ref
          .read(financialAccountRepositoryProvider)
          .create(draft);
      await ref.read(financialAccountListProvider.notifier).refresh();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Financial account created successfully.'),
        ),
      );
      context.go('/staff/financial-accounts/${result.financialAccountId}');
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Financial account could not be created.'),
        ),
      );
    }
  }
}

class FinancialAccountDetailScreen extends ConsumerStatefulWidget {
  const FinancialAccountDetailScreen({required this.accountId, super.key});

  final String accountId;

  @override
  ConsumerState<FinancialAccountDetailScreen> createState() =>
      _FinancialAccountDetailScreenState();
}

class _FinancialAccountDetailScreenState
    extends ConsumerState<FinancialAccountDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(financialAccountDetailProvider(widget.accountId).notifier)
          .load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financialAccountDetailProvider(widget.accountId));
    if (state.isLoading) {
      return const Center(child: Text('Loading financial account...'));
    }
    if (state.error != null || state.account == null) {
      return const Center(
        child: Text('Financial account could not be loaded.'),
      );
    }
    final account = state.account!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(account.name, style: Theme.of(context).textTheme.headlineSmall),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.edit),
              label: const Text('Edit'),
              onPressed: state.isMutating ? null : () => _edit(account),
            ),
            if (!account.isActive && !account.isArchived)
              ActionChip(
                avatar: const Icon(Icons.play_arrow),
                label: const Text('Activate'),
                onPressed: state.isMutating ? null : _activate,
              ),
            if (account.isActive && !account.isArchived)
              ActionChip(
                avatar: const Icon(Icons.pause),
                label: const Text('Deactivate'),
                onPressed: state.isMutating ? null : _deactivate,
              ),
            if (!account.isArchived)
              ActionChip(
                avatar: const Icon(Icons.archive),
                label: const Text('Archive'),
                onPressed: state.isMutating ? null : _archive,
              ),
          ],
        ),
        if (state.isMutating) const Text('Saving account changes...'),
        if (state.mutationError != null)
          Text(
            _safeMutationMessage(state.mutationError),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        _Meta('Account number', account.accountNumber),
        _Meta('Type', account.typeCode),
        _Meta('Currency', account.currencyCode),
        _Meta(
          'Balance',
          account.balance?.display ?? '${account.currencyCode} 0',
        ),
        _Meta(
          'Status',
          account.isArchived
              ? 'Archived'
              : account.isActive
              ? 'Active'
              : 'Inactive',
        ),
        if (account.isBank) _Meta('Bank', account.bankName ?? 'Not available'),
        if (account.isBank)
          _Meta(
            'Masked identifier',
            account.maskedAccountIdentifier ?? 'Not available',
          ),
        if (account.notes != null) _Meta('Notes', account.notes!),
      ],
    );
  }

  Future<void> _edit(FinancialAccount account) async {
    final draft = await showModalBottomSheet<FinancialAccountDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AccountFormSheet(account: account),
    );
    if (draft == null) {
      return;
    }
    final ok = await ref
        .read(financialAccountDetailProvider(widget.accountId).notifier)
        .update(draft);
    if (!mounted) {
      return;
    }
    _snack(
      ok
          ? 'Financial account updated.'
          : _safeMutationMessage(
              ref
                  .read(financialAccountDetailProvider(widget.accountId))
                  .mutationError,
            ),
    );
  }

  Future<void> _activate() => _runLifecycle(
    action: () => ref
        .read(financialAccountDetailProvider(widget.accountId).notifier)
        .activate(),
    success: 'Financial account activated.',
  );

  Future<void> _deactivate() async {
    if (await _confirm(
          'Deactivate account',
          'The account remains available as an inactive financial account.',
        ) !=
        true) {
      return;
    }
    await _runLifecycle(
      action: () => ref
          .read(financialAccountDetailProvider(widget.accountId).notifier)
          .deactivate(),
      success: 'Financial account deactivated.',
    );
  }

  Future<void> _archive() async {
    if (await _confirm(
          'Archive account',
          'The account remains retained as a historical financial record. This is not deletion.',
        ) !=
        true) {
      return;
    }
    await _runLifecycle(
      action: () => ref
          .read(financialAccountDetailProvider(widget.accountId).notifier)
          .archive(),
      success: 'Financial account archived.',
    );
  }

  Future<void> _runLifecycle({
    required Future<bool> Function() action,
    required String success,
  }) async {
    final ok = await action();
    if (!mounted) {
      return;
    }
    _snack(
      ok
          ? success
          : _safeMutationMessage(
              ref
                  .read(financialAccountDetailProvider(widget.accountId))
                  .mutationError,
            ),
    );
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
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
          child: Text(title.split(' ').first),
        ),
      ],
    ),
  );

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _AccountList extends StatelessWidget {
  const _AccountList({required this.state, required this.accounts});

  final FinancialAccountListState state;
  final List<FinancialAccount> accounts;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(child: Text('Loading financial accounts...'));
    }
    if (state.error != null) {
      return const Center(
        child: Text('Financial accounts could not be loaded.'),
      );
    }
    if (accounts.isEmpty) {
      return const Center(child: Text('No financial accounts found.'));
    }
    return ListView.separated(
      itemCount: accounts.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final account = accounts[index];
        return ListTile(
          leading: Icon(
            account.isBank ? Icons.account_balance : Icons.payments,
          ),
          title: Text(account.name),
          subtitle: Text(_subtitle(account)),
          trailing: Text(
            account.balance?.display ?? '${account.currencyCode} 0',
          ),
          onTap: () => context.go('/staff/financial-accounts/${account.id}'),
        );
      },
    );
  }

  String _subtitle(FinancialAccount account) {
    final status = account.isArchived
        ? 'Archived'
        : account.isActive
        ? 'Active'
        : 'Inactive';
    if (!account.isBank) {
      return 'Cash - ${account.currencyCode} - $status';
    }
    return [
      'Bank',
      account.currencyCode,
      if (account.bankName != null) account.bankName!,
      if (account.maskedAccountIdentifier != null)
        account.maskedAccountIdentifier!,
      status,
    ].join(' - ');
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.cashTotals,
    required this.bankTotals,
    required this.isWide,
  });

  final List<ExactMoney> cashTotals;
  final List<ExactMoney> bankTotals;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final children = [
      _TotalGroup(label: 'Cash total', totals: cashTotals),
      _TotalGroup(label: 'Bank total', totals: bankTotals),
    ];
    return isWide
        ? Row(children: children.map((c) => Expanded(child: c)).toList())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
  }
}

class _TotalGroup extends StatelessWidget {
  const _TotalGroup({required this.label, required this.totals});
  final String label;
  final List<ExactMoney> totals;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              if (totals.isEmpty)
                const Text('No balance')
              else
                ...totals.map((total) => Text(total.display)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountFormSheet extends StatefulWidget {
  const _AccountFormSheet({this.account});

  final FinancialAccount? account;

  @override
  State<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<_AccountFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _currency;
  late final TextEditingController _bankName;
  late final TextEditingController _masked;
  late final TextEditingController _notes;
  late FinancialAccountType _type;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _type = account?.type ?? FinancialAccountType.cash;
    _name = TextEditingController(text: account?.name);
    _currency = TextEditingController(text: account?.currencyCode ?? 'USD');
    _bankName = TextEditingController(text: account?.bankName);
    _masked = TextEditingController(text: account?.maskedAccountIdentifier);
    _notes = TextEditingController(text: account?.notes);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                widget.account == null ? 'Create account' : 'Edit account',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SegmentedButton<FinancialAccountType>(
                segments: const [
                  ButtonSegment(
                    value: FinancialAccountType.cash,
                    label: Text('Cash'),
                    icon: Icon(Icons.payments),
                  ),
                  ButtonSegment(
                    value: FinancialAccountType.bank,
                    label: Text('Bank'),
                    icon: Icon(Icons.account_balance),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (value) =>
                    setState(() => _type = value.single),
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Account name'),
                validator: _required,
              ),
              TextFormField(
                controller: _currency,
                decoration: const InputDecoration(labelText: 'Currency code'),
                maxLength: 3,
                validator: _currencyValidator,
              ),
              if (_type == FinancialAccountType.bank) ...[
                TextFormField(
                  controller: _bankName,
                  decoration: const InputDecoration(labelText: 'Bank name'),
                  validator: _required,
                ),
                TextFormField(
                  controller: _masked,
                  decoration: const InputDecoration(
                    labelText: 'Masked account identifier',
                  ),
                  validator: _required,
                ),
              ],
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    Navigator.of(context).pop(
      FinancialAccountDraft(
        name: _name.text.trim(),
        type: _type,
        currencyCode: _currency.text.trim().toUpperCase(),
        bankName: _type == FinancialAccountType.bank
            ? _bankName.text.trim()
            : null,
        maskedAccountIdentifier: _type == FinancialAccountType.bank
            ? _masked.text.trim()
            : null,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
  String? _currencyValidator(String? value) {
    final text = value?.trim().toUpperCase() ?? '';
    return RegExp(r'^[A-Z]{3}$').hasMatch(text) ? null : 'Use a 3-letter code';
  }
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

List<String> _currencies(FinancialAccountListState state) {
  final values = <String>{};
  for (final account in state.accounts) {
    values.add(account.currencyCode);
  }
  for (final total in [...state.cashTotals, ...state.bankTotals]) {
    values.add(total.currencyCode);
  }
  return values.toList()..sort();
}

String _safeMutationMessage(Object? error) {
  final message = error?.toString().toLowerCase() ?? '';
  if (message.contains('version')) {
    return 'Financial account version conflict. Refresh and try again.';
  }
  if (message.contains('encrypted')) {
    return 'This account cannot be converted to Cash because protected bank metadata is retained.';
  }
  if (message.contains('posted') || message.contains('history')) {
    return 'Posted financial history prevents that account type or currency change.';
  }
  return 'Financial account change failed. No financial data was changed.';
}
