import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../financial_accounts/financial_account_providers.dart';
import '../financial_accounts/financial_account_models.dart';
import '../financial_corrections/financial_correction_models.dart';
import '../financial_corrections/financial_correction_providers.dart';

class FinancialReversalsScreen extends ConsumerStatefulWidget {
  const FinancialReversalsScreen({super.key});
  @override
  ConsumerState<FinancialReversalsScreen> createState() =>
      _FinancialReversalsScreenState();
}

class _FinancialReversalsScreenState
    extends ConsumerState<FinancialReversalsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(reversalListProvider.notifier).load();
      ref.read(correctionSourceListProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reversalListProvider);
    return _ListScaffold(
      title: 'Financial Reversals',
      createLabel: 'Create',
      onCreate: () => _create(context),
      child: state.when(
        loading: () => const Center(child: Text('Loading reversals...')),
        error: (_, _) =>
            const Center(child: Text('Reversals could not be loaded.')),
        data: (rows) => rows.isEmpty
            ? const Center(child: Text('No reversals found.'))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = rows[index];
                  return ListTile(
                    leading: const Icon(Icons.undo),
                    title: Text(item.eventNumber),
                    subtitle: Text(
                      'Original FT ${item.originalTransactionId} - ${_status(item.eventStatus, item.transactionStatus)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(
                      '/staff/financial-reversals/${item.financialEventId}',
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final draft = await showModalBottomSheet<ReversalDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReversalForm(),
    );
    if (draft == null) return;
    try {
      final result = await ref
          .read(financialCorrectionRepositoryProvider)
          .createReversal(draft);
      await ref.read(reversalListProvider.notifier).load();
      if (context.mounted) {
        context.go('/staff/financial-reversals/${result.financialEventId}');
      }
    } catch (_) {
      if (context.mounted) _snack(context, 'Reversal could not be created.');
    }
  }
}

class FinancialReversalDetailScreen extends ConsumerWidget {
  const FinancialReversalDetailScreen({
    required this.financialEventId,
    super.key,
  });
  final String financialEventId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reversalDetailProvider(financialEventId));
    return state.when(
      loading: () => const Center(child: Text('Loading reversal...')),
      error: (_, _) =>
          const Center(child: Text('Reversal could not be loaded.')),
      data: (item) => _Detail(
        title: item.eventNumber,
        rows: [
          ('Correction transaction', item.transactionNumber),
          ('Original transaction', item.originalTransactionId),
          ('Reversal type', 'Full reversal'),
          ('Reversal date', item.reversalDate),
          ('Status', _status(item.eventStatus, item.transactionStatus)),
          if (item.reason != null) ('Reason', item.reason!),
          if (item.description != null) ('Description', item.description!),
          if (item.rejectionReason != null)
            ('Rejection reason', item.rejectionReason!),
        ],
        actions: _actions(
          context,
          item.isSubmitted,
          item.isDraft,
          () => ref
              .read(reversalDetailProvider(financialEventId).notifier)
              .submit(),
          () => ref
              .read(reversalDetailProvider(financialEventId).notifier)
              .approve(),
          (reason) => ref
              .read(reversalDetailProvider(financialEventId).notifier)
              .reject(reason),
        ),
        footer:
            'Original posted transactions, ledger entries, and FX snapshots remain immutable. Approval is posted only by a different Owner through PostgreSQL.',
      ),
    );
  }
}

class FinancialAdjustmentsScreen extends ConsumerStatefulWidget {
  const FinancialAdjustmentsScreen({super.key});
  @override
  ConsumerState<FinancialAdjustmentsScreen> createState() =>
      _FinancialAdjustmentsScreenState();
}

class _FinancialAdjustmentsScreenState
    extends ConsumerState<FinancialAdjustmentsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(adjustmentListProvider.notifier).load();
      ref.read(correctionSourceListProvider.notifier).load();
      ref.read(financialAccountListProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adjustmentListProvider);
    return _ListScaffold(
      title: 'Financial Adjustments',
      createLabel: 'Create',
      onCreate: () => _create(context),
      child: state.when(
        loading: () => const Center(child: Text('Loading adjustments...')),
        error: (_, _) =>
            const Center(child: Text('Adjustments could not be loaded.')),
        data: (rows) => rows.isEmpty
            ? const Center(child: Text('No adjustments found.'))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = rows[index];
                  return ListTile(
                    leading: const Icon(Icons.tune),
                    title: Text('${item.eventNumber} - ${item.moneyDisplay}'),
                    subtitle: Text(
                      '${item.direction} delta - ${_status(item.eventStatus, item.transactionStatus)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(
                      '/staff/financial-adjustments/${item.financialEventId}',
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final draft = await showModalBottomSheet<AdjustmentDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AdjustmentForm(),
    );
    if (draft == null) return;
    try {
      final result = await ref
          .read(financialCorrectionRepositoryProvider)
          .createAdjustment(draft);
      await ref.read(adjustmentListProvider.notifier).load();
      if (context.mounted) {
        context.go('/staff/financial-adjustments/${result.financialEventId}');
      }
    } catch (_) {
      if (context.mounted) _snack(context, 'Adjustment could not be created.');
    }
  }
}

class FinancialAdjustmentDetailScreen extends ConsumerWidget {
  const FinancialAdjustmentDetailScreen({
    required this.financialEventId,
    super.key,
  });
  final String financialEventId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adjustmentDetailProvider(financialEventId));
    return state.when(
      loading: () => const Center(child: Text('Loading adjustment...')),
      error: (_, _) =>
          const Center(child: Text('Adjustment could not be loaded.')),
      data: (item) => _Detail(
        title: item.eventNumber,
        rows: [
          ('Correction transaction', item.transactionNumber),
          if (item.adjustedTransactionId != null)
            ('Original transaction', item.adjustedTransactionId!),
          (
            'Adjustment Amount / Delta',
            '${item.direction} ${item.moneyDisplay}',
          ),
          ('Adjustment date', item.adjustmentDate),
          ('Status', _status(item.eventStatus, item.transactionStatus)),
          if (item.reason != null) ('Reason', item.reason!),
          if (item.rejectionReason != null)
            ('Rejection reason', item.rejectionReason!),
        ],
        actions: _actions(
          context,
          item.isSubmitted,
          item.isDraft,
          () => ref
              .read(adjustmentDetailProvider(financialEventId).notifier)
              .submit(),
          () => ref
              .read(adjustmentDetailProvider(financialEventId).notifier)
              .approve(),
          (reason) => ref
              .read(adjustmentDetailProvider(financialEventId).notifier)
              .reject(reason),
        ),
        footer:
            'Adjustment Amount / Delta creates a new correcting financial event. It does not replace or edit the original posted transaction.',
      ),
    );
  }
}

class _ReversalForm extends ConsumerStatefulWidget {
  const _ReversalForm();
  @override
  ConsumerState<_ReversalForm> createState() => _ReversalFormState();
}

class _ReversalFormState extends ConsumerState<_ReversalForm> {
  final reason = TextEditingController();
  final date = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  CorrectionSource? source;
  @override
  Widget build(BuildContext context) {
    final sources =
        ref
            .watch(correctionSourceListProvider)
            .value
            ?.where((s) => s.canReverse)
            .toList() ??
        const <CorrectionSource>[];
    source ??= sources.firstOrNull;
    return _FormFrame(
      title: 'Create reversal',
      children: [
        DropdownButtonFormField<CorrectionSource>(
          initialValue: source,
          items: [
            for (final s in sources)
              DropdownMenuItem(
                value: s,
                child: Text('${s.eventNumber} - ${s.moneyDisplay}'),
              ),
          ],
          onChanged: (v) => setState(() => source = v),
          decoration: const InputDecoration(
            labelText: 'Posted source transaction',
          ),
        ),
        TextField(
          controller: date,
          decoration: const InputDecoration(labelText: 'Reversal date'),
        ),
        TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason'),
          maxLines: 3,
        ),
        FilledButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('Save Draft'),
          onPressed: () {
            if (source == null || reason.text.trim().isEmpty) return;
            Navigator.of(context).pop(
              ReversalDraft(
                originalTransactionId: source!.financialTransactionId,
                reversalDate: date.text.trim(),
                reason: reason.text.trim(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AdjustmentForm extends ConsumerStatefulWidget {
  const _AdjustmentForm();
  @override
  ConsumerState<_AdjustmentForm> createState() => _AdjustmentFormState();
}

class _AdjustmentFormState extends ConsumerState<_AdjustmentForm> {
  final amount = TextEditingController();
  final reason = TextEditingController();
  final date = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  CorrectionSource? source;
  FinancialAccount? account;
  String direction = 'INCREASE';
  @override
  Widget build(BuildContext context) {
    final sources =
        ref
            .watch(correctionSourceListProvider)
            .value
            ?.where((s) => s.canAdjust)
            .toList() ??
        const <CorrectionSource>[];
    final accounts = ref
        .watch(financialAccountListProvider)
        .accounts
        .where((a) => a.isActive && !a.isArchived)
        .toList();
    source ??= sources.firstOrNull;
    account ??= accounts
        .where((a) => a.currencyCode == source?.currencyCode)
        .firstOrNull;
    return _FormFrame(
      title: 'Create adjustment',
      children: [
        DropdownButtonFormField<CorrectionSource>(
          initialValue: source,
          items: [
            for (final s in sources)
              DropdownMenuItem(
                value: s,
                child: Text('${s.eventNumber} - ${s.moneyDisplay}'),
              ),
          ],
          onChanged: (v) => setState(() => source = v),
          decoration: const InputDecoration(
            labelText: 'Posted source transaction',
          ),
        ),
        DropdownButtonFormField<FinancialAccount>(
          initialValue: account,
          items: [
            for (final a in accounts)
              DropdownMenuItem(
                value: a,
                child: Text('${a.name} - ${a.currencyCode}'),
              ),
          ],
          onChanged: (v) => setState(() => account = v),
          decoration: const InputDecoration(
            labelText: 'Financial account to adjust',
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'INCREASE', label: Text('Increase')),
            ButtonSegment(value: 'DECREASE', label: Text('Decrease')),
          ],
          selected: {direction},
          onSelectionChanged: (v) => setState(() => direction = v.first),
        ),
        TextField(
          controller: amount,
          decoration: const InputDecoration(
            labelText: 'Adjustment Amount / Delta',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        TextField(
          controller: date,
          decoration: const InputDecoration(labelText: 'Adjustment date'),
        ),
        TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason'),
          maxLines: 3,
        ),
        FilledButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('Save Draft'),
          onPressed: () {
            if (source == null ||
                account == null ||
                amount.text.trim().isEmpty ||
                reason.text.trim().isEmpty) {
              return;
            }
            Navigator.of(context).pop(
              AdjustmentDraft(
                financialAccountId: account!.id,
                direction: direction,
                amount: amount.text.trim(),
                adjustmentDate: date.text.trim(),
                reportingCurrencyCode: account!.currencyCode,
                reason: reason.text.trim(),
                adjustedTransactionId: source!.financialTransactionId,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ListScaffold extends StatelessWidget {
  const _ListScaffold({
    required this.title,
    required this.createLabel,
    required this.onCreate,
    required this.child,
  });
  final String title;
  final String createLabel;
  final VoidCallback onCreate;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text(createLabel),
              onPressed: onCreate,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: child),
      ],
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.title,
    required this.rows,
    required this.actions,
    required this.footer,
  });
  final String title;
  final List<(String, String)> rows;
  final List<Widget> actions;
  final String footer;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      Wrap(spacing: 8, runSpacing: 8, children: actions),
      const SizedBox(height: 16),
      for (final row in rows) _Meta(row.$1, row.$2),
      const SizedBox(height: 12),
      Text(footer),
    ],
  );
}

List<Widget> _actions(
  BuildContext context,
  bool submitted,
  bool draft,
  Future<bool> Function() submit,
  Future<bool> Function() approve,
  Future<bool> Function(String) reject,
) => [
  if (draft)
    ActionChip(
      avatar: const Icon(Icons.send),
      label: const Text('Submit'),
      onPressed: () async {
        final ok = await submit();
        if (context.mounted) {
          _snack(context, ok ? 'Submitted.' : 'Action failed.');
        }
      },
    ),
  if (submitted)
    ActionChip(
      avatar: const Icon(Icons.verified),
      label: const Text('Approve & Post'),
      onPressed: () async {
        final ok = await approve();
        if (context.mounted) {
          _snack(context, ok ? 'Approved and posted.' : 'Action failed.');
        }
      },
    ),
  if (submitted)
    ActionChip(
      avatar: const Icon(Icons.block),
      label: const Text('Reject'),
      onPressed: () async {
        final reason = await showDialog<String>(
          context: context,
          builder: (_) => const _RejectDialog(),
        );
        if (reason != null) {
          final ok = await reject(reason);
          if (context.mounted) {
            _snack(context, ok ? 'Rejected.' : 'Action failed.');
          }
        }
      },
    ),
  if (submitted) const Chip(label: Text('Another Owner Required')),
];

class _FormFrame extends StatelessWidget {
  const _FormFrame({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          ...children.map(
            (w) => Padding(padding: const EdgeInsets.only(top: 10), child: w),
          ),
        ],
      ),
    ),
  );
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
    title: const Text('Reject correction'),
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

String _status(String eventStatus, String transactionStatus) =>
    eventStatus == 'APPROVED' && transactionStatus == 'POSTED'
    ? 'Posted'
    : '$eventStatus / $transactionStatus';
void _snack(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
