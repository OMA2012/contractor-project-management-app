import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_session.dart';
import 'responsive_auth_scaffold.dart';

class PasswordResetRequestScreen extends ConsumerStatefulWidget {
  const PasswordResetRequestScreen({super.key});

  @override
  ConsumerState<PasswordResetRequestScreen> createState() =>
      _PasswordResetRequestScreenState();
}

class _PasswordResetRequestScreenState
    extends ConsumerState<PasswordResetRequestScreen> {
  final emailController = TextEditingController();
  var _isSubmitting = false;
  String? _message;
  var _isError = false;

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAuthScaffold(
      title: 'Reset password',
      subtitle: 'Request a secure password reset link.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send reset link'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _message!,
                style: _isError
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _message = 'Enter your email address.';
        _isError = true;
      });
      return;
    }
    setState(() {
      _isSubmitting = true;
      _message = null;
      _isError = false;
    });
    try {
      await ref.read(authSessionProvider.notifier).requestPasswordReset(email);
      if (mounted) {
        setState(() {
          _message = 'If the account is eligible, a reset link has been sent.';
          _isError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Password reset could not be requested. Try again.';
          _isError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
