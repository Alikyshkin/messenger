import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _passwordVisible = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await context.read<AuthService>().login(
        _username.text.trim(),
        _password.text,
      );
      if (!mounted) return;
      context.go('/');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.tr('connection_error');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('messenger'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _username,
                            decoration: InputDecoration(
                              labelText: context.tr('username'),
                              border: const OutlineInputBorder(),
                            ),
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableInteractiveSelection: true,
                            enableSuggestions: false,
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? context.tr('enter_username') : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            decoration: InputDecoration(
                              labelText: context.tr('password'),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(_passwordVisible ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                                tooltip: _passwordVisible ? 'Скрыть пароль' : 'Показать пароль',
                              ),
                            ),
                            obscureText: !_passwordVisible,
                            enableInteractiveSelection: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            onFieldSubmitted: (_) => _submit(),
                            validator: (v) =>
                                v == null || v.isEmpty ? context.tr('enter_password') : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _loading
                                ? null
                                : () {
                                    if (_formKey.currentState!.validate()) _submit();
                                  },
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(context.tr('login_btn')),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () {
                                    context.push('/forgot-password');
                                  },
                            child: Text(context.tr('forgot_password')),
                          ),
                          TextButton(
                            onPressed: () {
                              context.push('/register');
                            },
                            child: Text(context.tr('no_account_register')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
