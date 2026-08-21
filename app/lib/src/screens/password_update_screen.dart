import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_session.dart';
import 'responsive_auth_scaffold.dart';

class PasswordUpdateScreen extends ConsumerStatefulWidget {
  const PasswordUpdateScreen({super.key});

  @override
  ConsumerState<PasswordUpdateScreen> createState() =>
      _PasswordUpdateScreenState();
}

class _PasswordUpdateScreenState extends ConsumerState<PasswordUpdateScreen> {
  final passwordController = TextEditingController();
  var _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAuthScaffold(
      title: 'Update password',
      subtitle: 'Choose a new password to continue.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Update password'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final password = passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter a new password.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(authSessionProvider.notifier).updatePassword(password);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Password could not be updated. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
