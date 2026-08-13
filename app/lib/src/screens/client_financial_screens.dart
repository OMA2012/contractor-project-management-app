import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../payments/payment_models.dart';
import '../payments/payment_providers.dart';
import '../projects/project_models.dart';
import '../projects/project_providers.dart';

class ClientPaymentsScreen extends ConsumerStatefulWidget {
  const ClientPaymentsScreen({super.key});

  @override
  ConsumerState<ClientPaymentsScreen> createState() =>
      _ClientPaymentsScreenState();
}

class _ClientPaymentsScreenState extends ConsumerState<ClientPaymentsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(clientApprovedPaymentListProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(clientProjectAccessProvider, (previous, hasAccess) {
      if (previous != true && hasAccess) {
        Future.microtask(
          () => ref.read(clientApprovedPaymentListProvider.notifier).load(),
        );
      }
    });
    final state = ref.watch(clientApprovedPaymentListProvider);
    return _FinancialPage(
      title: 'Payments',
      action: FilledButton.icon(
        onPressed: () => context.go('/client/payments/submit'),
        icon: const Icon(Icons.add),
        label: const Text('Submit payment'),
      ),
      footer: _LoadMoreButton(
        hasMore: state.hasMore,
        isLoadingMore: state.isLoadingMore,
        onPressed: () =>
            ref.read(clientApprovedPaymentListProvider.notifier).loadMore(),
      ),
      child: _PaymentListBody(state: state),
    );
  }
}

class ClientPaymentDetailScreen extends ConsumerStatefulWidget {
  const ClientPaymentDetailScreen({required this.paymentId, super.key});

  final String paymentId;

  @override
  ConsumerState<ClientPaymentDetailScreen> createState() =>
      _ClientPaymentDetailScreenState();
}

class _ClientPaymentDetailScreenState
    extends ConsumerState<ClientPaymentDetailScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ClientPaymentDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paymentId != widget.paymentId) _load();
  }

  void _load() {
    Future.microtask(
      () => ref
          .read(clientApprovedPaymentDetailProvider(widget.paymentId).notifier)
          .load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      clientApprovedPaymentDetailProvider(widget.paymentId),
    );
    return _FinancialPage(
      title: 'Payment detail',
      child: state.isLoading
          ? const _CenteredProgress()
          : state.unavailable
          ? const _SafeMessage('Payment is unavailable.')
          : state.error != null || state.payment == null
          ? const _SafeMessage('Payment could not be loaded.')
          : _PaymentDetail(payment: state.payment!),
    );
  }
}

class ClientPaymentRequestsScreen extends ConsumerStatefulWidget {
  const ClientPaymentRequestsScreen({super.key});

  @override
  ConsumerState<ClientPaymentRequestsScreen> createState() =>
      _ClientPaymentRequestsScreenState();
}

class _ClientPaymentRequestsScreenState
    extends ConsumerState<ClientPaymentRequestsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(clientPaymentRequestListProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(clientProjectAccessProvider, (previous, hasAccess) {
      if (previous != true && hasAccess) {
        Future.microtask(
          () => ref.read(clientPaymentRequestListProvider.notifier).load(),
        );
      }
    });
    final state = ref.watch(clientPaymentRequestListProvider);
    return _FinancialPage(
      title: 'Payment requests',
      footer: _LoadMoreButton(
        hasMore: state.hasMore,
        isLoadingMore: state.isLoadingMore,
        onPressed: () =>
            ref.read(clientPaymentRequestListProvider.notifier).loadMore(),
      ),
      child: _RequestListBody(state: state),
    );
  }
}

class ClientPaymentRequestDetailScreen extends ConsumerStatefulWidget {
  const ClientPaymentRequestDetailScreen({required this.requestId, super.key});

  final String requestId;

  @override
  ConsumerState<ClientPaymentRequestDetailScreen> createState() =>
      _ClientPaymentRequestDetailScreenState();
}

class _ClientPaymentRequestDetailScreenState
    extends ConsumerState<ClientPaymentRequestDetailScreen> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ClientPaymentRequestDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId) _load();
  }

  void _load() {
    Future.microtask(
      () => ref
          .read(clientPaymentRequestDetailProvider(widget.requestId).notifier)
          .load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      clientPaymentRequestDetailProvider(widget.requestId),
    );
    return _FinancialPage(
      title: 'Payment request detail',
      child: state.isLoading
          ? const _CenteredProgress()
          : state.unavailable
          ? const _SafeMessage('Payment request is unavailable.')
          : state.error != null || state.request == null
          ? const _SafeMessage('Payment request could not be loaded.')
          : _RequestDetail(request: state.request!),
    );
  }
}

class ClientSubmitPaymentScreen extends ConsumerStatefulWidget {
  const ClientSubmitPaymentScreen({super.key});

  @override
  ConsumerState<ClientSubmitPaymentScreen> createState() =>
      _ClientSubmitPaymentScreenState();
}

class _ClientSubmitPaymentScreenState
    extends ConsumerState<ClientSubmitPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _payer = TextEditingController();
  ClientProject? _project;
  String? _currencyCode;
  DateTime? _paymentDate;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(clientProjectListProvider.notifier).load());
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _payer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectState = ref.watch(clientProjectListProvider);
    final submitState = ref.watch(clientPaymentSubmitProvider);
    final projects = projectState.projects;
    if (_project != null &&
        !projects.any((project) => project.id == _project!.id)) {
      _project = null;
      _currencyCode = null;
    }
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return _FinancialPage(
      title: 'Submit payment',
      child: Form(
        key: _formKey,
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 720 : double.infinity,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (projectState.isLoading) const _CenteredProgress(),
                if (!projectState.isLoading && projectState.error != null)
                  const _SafeMessage('Projects could not be loaded.'),
                if (!projectState.isLoading &&
                    projectState.error == null &&
                    projects.isEmpty)
                  const _SafeMessage(
                    'No projects are available for payment submission.',
                  ),
                if (projects.isNotEmpty)
                  DropdownButtonFormField<ClientProject>(
                    initialValue: _project,
                    decoration: const InputDecoration(labelText: 'Project'),
                    items: projects
                        .map(
                          (project) => DropdownMenuItem(
                            value: project,
                            child: Text(
                              '${project.projectNumber} - ${project.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: submitState.isSubmitting
                        ? null
                        : (project) => setState(() {
                            _project = project;
                            _currencyCode = project?.reportingCurrencyCode;
                          }),
                    validator: (value) =>
                        value == null ? 'Select a project.' : null,
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  enabled: !submitState.isSubmitting,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  validator: (value) {
                    try {
                      ExactMoney.fromInput(value ?? '');
                      return null;
                    } on PaymentFailure catch (error) {
                      return error.message;
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _currencyCode,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: _currencyOptions(projects)
                      .map(
                        (code) =>
                            DropdownMenuItem(value: code, child: Text(code)),
                      )
                      .toList(growable: false),
                  onChanged: submitState.isSubmitting
                      ? null
                      : (value) => setState(() => _currencyCode = value),
                  validator: (value) =>
                      value == null ? 'Select a currency.' : null,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: submitState.isSubmitting ? null : _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    _paymentDate == null
                        ? 'Select payment date'
                        : 'Payment date ${_formatDate(_paymentDate)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reference,
                  enabled: !submitState.isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Payment reference optional',
                  ),
                  maxLength: 120,
                ),
                TextFormField(
                  controller: _payer,
                  enabled: !submitState.isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Payer name optional',
                  ),
                  maxLength: 200,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: submitState.isSubmitting || projects.isEmpty
                      ? null
                      : _submit,
                  icon: submitState.isSubmitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    submitState.isSubmitting
                        ? 'Submitting'
                        : 'Submit for verification',
                  ),
                ),
                if (submitState.error != null) ...[
                  const SizedBox(height: 12),
                  const Text('Payment submission failed. Please try again.'),
                ],
                if (submitState.result != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Submitted for verification. This does not confirm receipt.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Set<String> _currencyOptions(List<ClientProject> projects) {
    return projects.map((project) => project.reportingCurrencyCode).toSet();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _paymentDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (date != null) setState(() => _paymentDate = date);
  }

  Future<void> _submit() async {
    if (_paymentDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a payment date.')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(clientPaymentSubmitProvider.notifier)
        .submit(
          projectId: _project!.id,
          amount: ExactMoney.fromInput(_amount.text),
          currencyCode: _currencyCode!,
          receivedDate: _paymentDate!,
          paymentReference: _reference.text,
          payerName: _payer.text,
        );
  }
}

class _PaymentListBody extends StatelessWidget {
  const _PaymentListBody({required this.state});

  final ClientPaymentListState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const _CenteredProgress();
    }
    if (state.error != null) {
      return const _SafeMessage('Payments could not be loaded.');
    }
    if (state.payments.isEmpty) {
      return const _SafeMessage('No posted payments are available yet.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: state.payments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) =>
          _PaymentCard(payment: state.payments[index]),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment});

  final ClientApprovedPayment payment;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(payment.amount.display(payment.currencyCode)),
        subtitle: Text(
          [
            payment.projectNumber,
            'Received ${_formatDate(payment.receivedDate)}',
            if (payment.paymentReference != null) payment.paymentReference!,
          ].join(' - '),
        ),
        trailing: const Icon(Icons.arrow_forward),
        onTap: () => context.go('/client/payments/${payment.clientPaymentId}'),
      ),
    );
  }
}

class _PaymentDetail extends StatelessWidget {
  const _PaymentDetail({required this.payment});

  final ClientApprovedPayment payment;

  @override
  Widget build(BuildContext context) {
    return _DetailGrid(
      rows: [
        ('Project', payment.projectNumber),
        ('Amount', payment.amount.display(payment.currencyCode)),
        ('Received date', _formatDate(payment.receivedDate)),
        (
          'Status',
          payment.isReceived ? 'Received and posted' : 'Status unavailable',
        ),
        if (payment.paymentReference != null)
          ('Reference', payment.paymentReference!),
        if (payment.approvedAt != null)
          ('Approved date', _formatDate(payment.approvedAt)),
      ],
    );
  }
}

class _RequestListBody extends StatelessWidget {
  const _RequestListBody({required this.state});

  final ClientPaymentRequestListState state;

  @override
  Widget build(BuildContext context) {
    final visibleRequests = state.requests
        .where(
          (request) =>
              request.status != 'DRAFT' && request.effectiveStatus != 'DRAFT',
        )
        .toList(growable: false);
    if (state.isLoading) {
      return const _CenteredProgress();
    }
    if (state.error != null) {
      return const _SafeMessage('Payment requests could not be loaded.');
    }
    if (visibleRequests.isEmpty) {
      return const _SafeMessage('No payment requests are available.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: visibleRequests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) =>
          _RequestCard(request: visibleRequests[index]),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final ClientPaymentRequest request;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(request.requestNumber),
        subtitle: Text(
          [
            request.projectNumber,
            request.requestedAmount.display(request.currencyCode),
            _statusLabel(request.effectiveStatus),
          ].join(' - '),
        ),
        trailing: const Icon(Icons.arrow_forward),
        onTap: () =>
            context.go('/client/payment-requests/${request.paymentRequestId}'),
      ),
    );
  }
}

class _RequestDetail extends StatelessWidget {
  const _RequestDetail({required this.request});

  final ClientPaymentRequest request;

  @override
  Widget build(BuildContext context) {
    return _DetailGrid(
      rows: [
        ('Request', request.requestNumber),
        ('Project', request.projectNumber),
        ('Requested', request.requestedAmount.display(request.currencyCode)),
        ('Paid', request.paidAmount.display(request.currencyCode)),
        ('Remaining', request.remainingAmount.display(request.currencyCode)),
        ('Status', _statusLabel(request.effectiveStatus)),
        if (request.requestDate != null)
          ('Request date', _formatDate(request.requestDate)),
        if (request.dueDate != null) ('Due date', _formatDate(request.dueDate)),
        if (request.description != null) ('Description', request.description!),
      ],
    );
  }
}

class _FinancialPage extends StatelessWidget {
  const _FinancialPage({
    required this.title,
    required this.child,
    this.action,
    this.footer,
  });

  final String title;
  final Widget child;
  final Widget? action;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: EdgeInsets.all(isWide ? 24 : 16),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ?action,
          ],
        ),
        const SizedBox(height: 16),
        child,
        if (footer != null) ...[const SizedBox(height: 8), footer!],
      ],
    );
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: rows
          .map(
            (row) => ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: isWide ? 240 : double.infinity,
                maxWidth: isWide ? 360 : double.infinity,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.$1, style: Theme.of(context).textTheme.labelSmall),
                  Text(row.$2, softWrap: true),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.hasMore,
    required this.isLoadingMore,
    required this.onPressed,
  });

  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: !hasMore || isLoadingMore ? null : onPressed,
        icon: isLoadingMore
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more),
        label: Text(hasMore ? 'Load more' : 'All loaded'),
      ),
    );
  }
}

class _CenteredProgress extends StatelessWidget {
  const _CenteredProgress();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _SafeMessage extends StatelessWidget {
  const _SafeMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(16), child: Text(text));
}

String _statusLabel(String status) => status.replaceAll('_', ' ');

String _formatDate(DateTime? date) {
  if (date == null) return 'Not available';
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
