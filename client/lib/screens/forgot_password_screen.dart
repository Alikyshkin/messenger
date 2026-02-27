import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../services/api.dart';
import '../utils/user_action_logger.dart';
import '../app_colors.dart';
import '../styles/app_sizes.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _sent = false;
  // Cached translations for use outside build phase
  String _trEnterEmail = '';
  String _trConnectionError = '';

  @override
  void dispose() {
    logAction('forgot_password_screen', 'dispose', 'done');
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final scope = logActionStart('forgot_password_screen', 'submit', {
      'email': email.isNotEmpty ? '***' : '',
    });
    if (email.isEmpty) {
      scope.fail('empty email');
      setState(() => _error = _trEnterEmail);
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
      _sent = false;
    });
    try {
      await Api('').forgotPassword(email);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sent = true;
      });
      scope.end({'sent': true});
    } on ApiException catch (e) {
      scope.fail(e);
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      scope.fail(e);
      if (!mounted) return;
      setState(() {
        _error = _trConnectionError;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _trEnterEmail = context.tr('enter_email');
    _trConnectionError = context.tr('connection_error');
    final screenWidth = MediaQuery.sizeOf(context).width;
    final padding = AppSizes.isCompact(screenWidth) ? 16.0 : 24.0;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: screenWidth < 400 ? double.infinity : 380,
              ),
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
                    context.tr('forgot_password_title'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (_sent) ...[
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('forgot_email_sent'),
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        logAction(
                          'forgot_password_screen',
                          'nav_go',
                          'done',
                          {'route': '/login'},
                        );
                        context.go('/login');
                      },
                      child: Text(context.tr('back_to_login')),
                    ),
                  ] else ...[
                    Text(
                      context.tr('forgot_email_prompt'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: context.tr('email_label'),
                        hintText: context.tr('email_hint_example'),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableInteractiveSelection: true,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(context.tr('send_reset_link')),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              logAction(
                                'forgot_password_screen',
                                'nav_go',
                                'done',
                                {'route': '/login'},
                              );
                              context.go('/login');
                            },
                      child: Text(context.tr('back_to_login')),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              logAction(
                                'forgot_password_screen',
                                'nav_push',
                                'done',
                                {'route': '/register'},
                              );
                              context.push('/register');
                            },
                      child: Text(context.tr('no_account_register')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
