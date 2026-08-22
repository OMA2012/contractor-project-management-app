import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../financial_accounts/financial_account_models.dart';
import '../financial_accounts/financial_account_providers.dart';
import '../project_expenses/project_expense_models.dart';
import '../project_expenses/project_expense_providers.dart';

const _expenseCurrencyCodes = ['USD', 'SAR', 'YER'];

class OwnerProjectExpensesScreen extends ConsumerStatefulWidget {
  const OwnerProjectExpensesScreen({this.clientId, super.key});

  final String? clientId;
  @override
  ConsumerState<OwnerProjectExpensesScreen> createState() =>
      _OwnerProjectExpensesScreenState();
}

class _OwnerProjectExpensesScreenState
    extends ConsumerState<OwnerProjectExpensesScreen> {
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(projectExpenseListProvider.notifier).load();
      ref.read(financialAccountListProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(projectExpenseListProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Project Expenses',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.read(projectExpenseListProvider.notifier).refresh(),
              ),
              FilledButton.icon(
                icon: _isCreating
                    ? const Icon(Icons.hourglass_top)
                    : const Icon(Icons.add),
                label: Text(_isCreating ? 'Saving' : 'Create'),
                onPressed: _isCreating ? null : () => _create(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.when(
              loading: () =>
                  const Center(child: Text('Loading project expenses...')),
              error: (_, _) => const Center(
                child: Text('Project expenses could not be loaded.'),
              ),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('No project expenses found.'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: Icon(
                            item.isPosted ? Icons.verified : Icons.receipt_long,
                          ),
                          title: Text(
                            '${item.eventNumber} - ${item.moneyDisplay}',
                          ),
                          subtitle: Text(
                            '${item.expenseDate} - ${item.eventStatus} - ${item.projectDisplay}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go(
                            '/staff/project-expenses/${item.financialEventId}',
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
    if (_isCreating) return;
    final draft = await showModalBottomSheet<ProjectExpenseDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ExpenseForm(clientId: widget.clientId),
    );
    if (draft == null) return;
    setState(() => _isCreating = true);
    try {
      final result = await ref
          .read(projectExpenseRepositoryProvider)
          .create(draft);
      await ref.read(projectExpenseListProvider.notifier).refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense saved successfully.')),
        );
        context.go('/staff/project-expenses/${result.financialEventId}');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expense could not be saved. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }
}

class OwnerProjectExpenseDetailScreen extends ConsumerWidget {
  const OwnerProjectExpenseDetailScreen({
    required this.financialEventId,
    super.key,
  });
  final String financialEventId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(projectExpenseDetailProvider(financialEventId));
    return state.when(
      loading: () => const Center(child: Text('Loading project expense...')),
      error: (_, _) =>
          const Center(child: Text('Project expense could not be loaded.')),
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
                          projectExpenseDetailProvider(
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
                          projectExpenseDetailProvider(
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
          _Meta('Project', item.projectDisplay),
          _Meta('Client', item.clientDisplay),
          _Meta('Expense date', item.expenseDate),
          _Meta('Paid from account', item.paidFromAccountId),
          _Meta('Status', item.isPosted ? 'Posted' : item.eventStatus),
          _Meta('Transaction', item.transactionStatus),
          _Meta('Category', item.expenseCategoryId),
          if (item.vendorName != null) _Meta('Vendor', item.vendorName!),
          if (item.vendorReference != null)
            _Meta('Reference', item.vendorReference!),
          if (item.description != null) _Meta('Description', item.description!),
          if (item.reportingCurrencyCode != null)
            _Meta('Reporting currency', item.reportingCurrencyCode!),
          if (item.rejectionReason != null)
            _Meta('Rejection reason', item.rejectionReason!),
          if (item.isPosted)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Posted expenses are immutable and balances derive from posted ledger entries.',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ProjectExpense item,
  ) async {
    final draft = await showModalBottomSheet<ProjectExpenseDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ExpenseForm(item: item),
    );
    if (draft == null || !context.mounted) return;
    await _run(
      context,
      ref,
      'Expense saved successfully.',
      () => ref
          .read(projectExpenseDetailProvider(financialEventId).notifier)
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
          .read(projectExpenseDetailProvider(financialEventId).notifier)
          .reject(reason),
    );
  }
}

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm({this.item, this.clientId});
  final ProjectExpense? item;
  final String? clientId;
  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _key = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.item?.amount);
  late String _currencyCode =
      _expenseCurrencyCodes.contains(widget.item?.currencyCode)
      ? widget.item!.currencyCode
      : 'USD';
  late final _date = TextEditingController(
    text:
        widget.item?.expenseDate ??
        DateTime.now().toIso8601String().substring(0, 10),
  );
  late final _vendor = TextEditingController(text: widget.item?.vendorName);
  late final _reference = TextEditingController(
    text: widget.item?.vendorReference,
  );
  late final _description = TextEditingController(
    text: widget.item?.description,
  );
  late final _notes = TextEditingController(text: widget.item?.privateNotes);
  FinancialAccount? _account;
  ProjectOption? _project;
  ExpenseCategoryOption? _category;
  bool _accountInitialized = false;
  late final Future<ProjectExpenseLookups> _lookups;

  @override
  void initState() {
    super.initState();
    _lookups = ref
        .read(projectExpenseRepositoryProvider)
        .lookups(clientId: widget.clientId);
    if (ref.read(financialAccountListProvider).isLoading) {
      Future.microtask(
        () => ref.read(financialAccountListProvider.notifier).load(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountState = ref.watch(financialAccountListProvider);
    final accounts = accountState.accounts
        .where(
          (a) => a.isActive && !a.isArchived && a.currencyCode == _currencyCode,
        )
        .toList();
    if (!_accountInitialized && !accountState.isLoading) {
      _account = accounts
          .where((a) => a.id == widget.item?.paidFromAccountId)
          .firstOrNull;
      _accountInitialized = true;
    }
    return FutureBuilder<ProjectExpenseLookups>(
      future: _lookups,
      builder: (context, snapshot) {
        final sourceLookups = snapshot.data;
        final lookups = sourceLookups == null
            ? null
            : ProjectExpenseLookups(
                expenseCategories: sourceLookups.expenseCategories,
                projects: sourceLookups.projects
                    .where(
                      (project) =>
                          widget.clientId == null ||
                          project.clientId == widget.clientId,
                    )
                    .toList(growable: false),
              );
        if (lookups != null) {
          _project ??= lookups.projects
              .where((p) => p.projectId == widget.item?.projectId)
              .firstOrNull;
          _category ??= lookups.expenseCategories
              .where(
                (c) => c.expenseCategoryId == widget.item?.expenseCategoryId,
              )
              .firstOrNull;
        }
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
                    widget.item == null
                        ? 'Create project expense'
                        : 'Edit draft',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  DropdownButtonFormField<ProjectOption>(
                    key: const ValueKey('expense-project-dropdown'),
                    initialValue: lookups?.projects.contains(_project) == true
                        ? _project
                        : null,
                    items: [
                      for (final project
                          in lookups?.projects ?? const <ProjectOption>[])
                        DropdownMenuItem(
                          value: project,
                          child: Text(project.display),
                        ),
                    ],
                    onChanged: snapshot.hasData
                        ? (value) => setState(() => _project = value)
                        : null,
                    decoration: const InputDecoration(labelText: 'Project'),
                    validator: (value) => value == null ? 'Required' : null,
                  ),
                  if (widget.clientId != null &&
                      snapshot.hasData &&
                      lookups!.projects.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('No projects available for this client.'),
                    ),
                  DropdownButtonFormField<ExpenseCategoryOption>(
                    key: const ValueKey('expense-category-dropdown'),
                    initialValue:
                        lookups?.expenseCategories.contains(_category) == true
                        ? _category
                        : null,
                    items: [
                      for (final category
                          in lookups?.expenseCategories ??
                              const <ExpenseCategoryOption>[])
                        DropdownMenuItem(
                          value: category,
                          child: Text(category.name),
                        ),
                    ],
                    onChanged: snapshot.hasData
                        ? (value) => setState(() => _category = value)
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Expense category',
                    ),
                    validator: (value) => value == null ? 'Required' : null,
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Loading project lookups...'),
                    )
                  else if (snapshot.hasError)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Project lookups could not be loaded.'),
                    ),
                  TextFormField(
                    controller: _amount,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _money,
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('expense-currency-dropdown'),
                    initialValue: _currencyCode,
                    items: [
                      for (final code in _expenseCurrencyCodes)
                        DropdownMenuItem(value: code, child: Text(code)),
                    ],
                    decoration: const InputDecoration(labelText: 'Currency'),
                    validator: (value) => value == null ? 'Required' : null,
                    onChanged: (value) {
                      if (value == null || value == _currencyCode) return;
                      setState(() {
                        _currencyCode = value;
                        if (_account?.currencyCode != value) _account = null;
                      });
                    },
                  ),
                  DropdownButtonFormField<FinancialAccount>(
                    key: ValueKey('paid-from-$_currencyCode'),
                    isExpanded: true,
                    initialValue: _account,
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(
                          value: a,
                          child: Text(
                            _accountDisplay(a),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: accounts.isEmpty
                        ? null
                        : (value) => setState(() => _account = value),
                    validator: (value) => value == null ? 'Required' : null,
                    decoration: const InputDecoration(
                      labelText: 'Paid from account',
                    ),
                  ),
                  if (accountState.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Loading financial accounts...'),
                    )
                  else if (accounts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'No active $_currencyCode accounts available.',
                      ),
                    ),
                  TextFormField(
                    controller: _date,
                    decoration: const InputDecoration(
                      labelText: 'Expense date',
                    ),
                    validator: _dateValidator,
                  ),
                  TextFormField(
                    controller: _vendor,
                    decoration: const InputDecoration(labelText: 'Vendor'),
                  ),
                  TextFormField(
                    controller: _reference,
                    decoration: const InputDecoration(labelText: 'Reference'),
                  ),
                  TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _notes,
                    decoration: const InputDecoration(
                      labelText: 'Private notes',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Save Draft'),
                    onPressed:
                        snapshot.hasData &&
                            lookups!.projects.isNotEmpty &&
                            accounts.contains(_account)
                        ? _submit
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _submit() {
    if (_key.currentState?.validate() != true ||
        _account == null ||
        _account!.currencyCode != _currencyCode ||
        !_account!.isActive ||
        _account!.isArchived ||
        _project == null ||
        (widget.clientId != null && _project!.clientId != widget.clientId) ||
        _category == null) {
      return;
    }
    Navigator.of(context).pop(
      ProjectExpenseDraft(
        projectId: _project!.projectId,
        clientId: widget.clientId,
        expenseCategoryId: _category!.expenseCategoryId,
        amount: _amount.text.trim(),
        currencyCode: _currencyCode,
        paidFromAccountId: _account!.id,
        expenseDate: _date.text.trim(),
        vendorName: _optional(_vendor.text),
        vendorReference: _optional(_reference.text),
        description: _description.text.trim(),
        privateNotes: _optional(_notes.text),
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
            : 'Project expense action failed. No financial data was changed.',
      ),
    ),
  );
}

Future<String?> _reason(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reject project expense'),
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
String? _optional(String value) => value.trim().isEmpty ? null : value.trim();

String _accountDisplay(FinancialAccount account) {
  if (!account.isBank) {
    return '${account.name} · Cash · ${account.currencyCode}';
  }
  return [
    account.name,
    'Bank',
    account.currencyCode,
    if (account.bankName?.trim().isNotEmpty == true) account.bankName!.trim(),
    if (account.maskedAccountIdentifier?.trim().isNotEmpty == true)
      account.maskedAccountIdentifier!.trim(),
  ].join(' · ');
}
