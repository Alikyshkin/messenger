import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/api.dart';
import '../app_colors.dart';
import '../styles/app_sizes.dart';
import '../utils/user_action_logger.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  bool _loading = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _displayName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    logUserAction('register_submit', {'username': _username.text.trim()});
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await context.read<AuthService>().register(
        _username.text.trim(),
        _password.text,
        _displayName.text.trim().isEmpty ? null : _displayName.text.trim(),
        _email.text.trim().isEmpty ? null : _email.text.trim(),
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final padding = AppSizes.isCompact(screenWidth) ? 16.0 : 24.0;
    // Capture translations in build() — validators run outside build phase
    final trMin3Chars = context.tr('min_3_chars');
    final trMin6Chars = context.tr('min_6_chars');
    final trEnterPassword = context.tr('enter_password');
    final trPasswordsMismatch = context.tr('passwords_dont_match');
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: screenWidth < 400 ? double.infinity : 380,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.primary,
                      child: const Icon(
                        Icons.send_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      context.tr('messenger'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('register_title'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _username,
                      decoration: InputDecoration(
                        labelText: context.tr('username'),
                      ),
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.name,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableInteractiveSelection: true,
                      validator: (v) {
                        if (v == null || v.trim().length < 3) {
                          return trMin3Chars;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _displayName,
                      decoration: InputDecoration(
                        labelText: context.tr('display_name_optional'),
                      ),
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.name,
                      autocorrect: false,
                      enableInteractiveSelection: true,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      decoration: InputDecoration(
                        labelText: context.tr('email_for_recovery'),
                        hintText: context.tr('email_hint_example'),
                      ),
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableInteractiveSelection: true,
                      enableSuggestions: false,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: context.tr('password'),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                          tooltip: _passwordVisible
                              ? 'Скрыть пароль'
                              : 'Показать пароль',
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.visiblePassword,
                      obscureText: !_passwordVisible,
                      enableSuggestions: false,
                      autocorrect: false,
                      enableInteractiveSelection: true,
                      validator: (v) {
                        if (v == null || v.length < 6) {
                          return trMin6Chars;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPassword,
                      decoration: InputDecoration(
                        labelText: context.tr('repeat_password'),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _confirmPasswordVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _confirmPasswordVisible =
                                !_confirmPasswordVisible,
                          ),
                          tooltip: _confirmPasswordVisible
                              ? 'Скрыть пароль'
                              : 'Показать пароль',
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      keyboardType: TextInputType.visiblePassword,
                      obscureText: !_confirmPasswordVisible,
                      enableSuggestions: false,
                      autocorrect: false,
                      enableInteractiveSelection: true,
                      onFieldSubmitted: (_) {
                        if (_formKey.currentState!.validate()) _submit();
                      },
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return trEnterPassword;
                        }
                        if (v != _password.text) {
                          return trPasswordsMismatch;
                        }
                        return null;
                      },
                    ),
                    if (_error != null && _error!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(context.tr('create_account')),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              logAction('register_screen', 'nav_go', 'done', {
                                'route': '/login',
                              });
                              context.go('/login');
                            },
                      child: Text(context.tr('have_account_login')),
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
