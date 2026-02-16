import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/api.dart' show ApiException, AuthResponse, OAuthProviders;
import '../services/oauth_service.dart';
import '../styles/app_sizes.dart';

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
  OAuthProviders _providers = OAuthProviders(google: false, vk: false, telegram: false, phone: false);
  StreamSubscription<AuthResponse?>? _googleAuthSub;

  @override
  void initState() {
    super.initState();
    OAuthService.getProviders().then((p) {
      if (mounted) setState(() => _providers = p);
    });
    if (kIsWeb) {
      _googleAuthSub = OAuthService.googleAuthStream.listen((res) async {
        if (!mounted || res == null) return;
        setState(() => _loading = true);
        try {
          await context.read<AuthService>().loginWithOAuth(res);
          if (!mounted) return;
          context.go('/');
        } on ApiException catch (e) {
          if (mounted) setState(() {
            _error = e.message;
            _loading = false;
          });
        } catch (_) {
          if (mounted) setState(() {
            _error = context.tr('connection_error');
            _loading = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _googleAuthSub?.cancel();
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
      if (!mounted) {
        return;
      }
      context.go('/');
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = context.tr('connection_error');
        _loading = false;
      });
    }
  }

  Widget _buildGoogleButton() {
    final webButton = OAuthService.getGoogleSignInButton();
    if (kIsWeb && webButton != null) {
      return SizedBox(height: 40, child: webButton);
    }
    return _OAuthButton(
      icon: Icons.g_mobiledata_rounded,
      label: 'Google',
      onPressed: _loading ? null : () => _oauthLogin(OAuthService.signInWithGoogle),
    );
  }

  Future<void> _oauthLogin(Future<AuthResponse?> Function() fn) async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final res = await fn();
      if (!mounted) return;
      if (res == null) {
        setState(() => _loading = false);
        return;
      }
      await context.read<AuthService>().loginWithOAuth(res);
      if (!mounted) return;
      context.go('/');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().contains('501') ? context.tr('oauth_not_configured') : context.tr('connection_error');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final padding = AppSizes.isCompact(screenWidth) ? 16.0 : 24.0;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: screenWidth < 400 ? double.infinity : 380),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.tr('messenger'),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
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
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? context.tr('enter_username')
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _password,
                              decoration: InputDecoration(
                                labelText: context.tr('password'),
                                border: const OutlineInputBorder(),
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
                              obscureText: !_passwordVisible,
                              enableInteractiveSelection: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              onFieldSubmitted: (_) => _submit(),
                              validator: (v) => v == null || v.isEmpty
                                  ? context.tr('enter_password')
                                  : null,
                            ),
                            if (_error != null) ...[
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
                                      if (_formKey.currentState!.validate()) {
                                        _submit();
                                      }
                                    },
                              child: _loading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
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
                            if (_providers.google || _providers.vk || _providers.telegram || _providers.phone) ...[
                              const SizedBox(height: 24),
                              Row(children: [
                                Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    context.tr('or_login_with'),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                                Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
                              ]),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                alignment: WrapAlignment.center,
                                children: [
                                  if (_providers.google)
                                    _buildGoogleButton(),
                                  if (_providers.vk)
                                    _OAuthButton(
                                      icon: Icons.tag,
                                      label: 'VK',
                                      onPressed: _loading ? null : () => _oauthLogin(OAuthService.signInWithVk),
                                    ),
                                  if (_providers.telegram)
                                    _OAuthButton(
                                      icon: Icons.send_rounded,
                                      label: 'Telegram',
                                      onPressed: _loading
                                          ? null
                                          : () async {
                                              final messenger = ScaffoldMessenger.of(context);
                                              try {
                                                await OAuthService.signInWithTelegram();
                                              } catch (e) {
                                                if (mounted) {
                                                  messenger.showSnackBar(
                                                    SnackBar(content: Text(e.toString())),
                                                  );
                                                }
                                              }
                                            },
                                    ),
                                  if (_providers.phone)
                                    _OAuthButton(
                                      icon: Icons.phone_android,
                                      label: context.tr('phone'),
                                      onPressed: _loading ? null : () => context.push('/login/phone'),
                                    ),
                                ],
                              ),
                            ],
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

class _OAuthButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _OAuthButton({required this.icon, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
