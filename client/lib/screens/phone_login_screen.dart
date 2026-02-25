import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/oauth_service.dart';
import '../services/api.dart';
import '../utils/user_action_logger.dart';

/// Экран входа по номеру телефона (SMS-код)
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _codeSent = false;
  String? _error;

  @override
  void dispose() {
    logAction('phone_login_screen', 'dispose', 'done');
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim().replaceAll(
      RegExp(r'[\s\-\(\)]'),
      '',
    );
    final scope = logActionStart('phone_login_screen', 'sendCode', {
      'phoneLen': phone.length,
    });
    if (phone.isEmpty) {
      scope.fail('empty phone');
      setState(() => _error = context.tr('enter_phone'));
      return;
    }
    final normalized = phone.startsWith('+') ? phone : '+7$phone';
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await OAuthService.sendPhoneCode(normalized);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _loading = false;
      });
      scope.end({'codeSent': true});
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
        _error = context.tr('connection_error');
        _loading = false;
      });
    }
  }

  Future<void> _verify() async {
    final phone = _phoneController.text.trim().replaceAll(
      RegExp(r'[\s\-\(\)]'),
      '',
    );
    final normalized = phone.startsWith('+') ? phone : '+7$phone';
    final code = _codeController.text.trim();
    final scope = logActionStart('phone_login_screen', 'verify', {
      'codeLen': code.length,
    });
    if (code.length != 6) {
      scope.fail('invalid code length');
      setState(() => _error = context.tr('enter_code_6'));
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final res = await OAuthService.verifyPhoneCode(normalized, code);
      if (!mounted) return;
      await context.read<AuthService>().loginWithOAuth(res);
      if (!mounted) return;
      scope.end({'userId': res.user.id});
      context.go('/');
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
        _error = context.tr('connection_error');
        _loading = false;
      });
    }
  }

  void _onBack() {
    logUserAction('phone_login_back');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('login_with_phone')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBack,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_codeSent) ...[
                TextField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: context.tr('phone_label'),
                    hintText: context.tr('phone_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                ),
              ] else ...[
                Text(
                  '${context.tr('code_sent_to')} ${_phoneController.text}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    labelText: context.tr('code'),
                    hintText: '123456',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofillHints: const [AutofillHints.oneTimeCode],
                ),
              ],
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
                        if (_codeSent) {
                          _verify();
                        } else {
                          _sendCode();
                        }
                      },
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _codeSent
                            ? context.tr('login_btn')
                            : context.tr('send_code'),
                      ),
              ),
              if (_codeSent)
                TextButton(
                  onPressed: _loading ? null : _sendCode,
                  child: Text(context.tr('resend_code')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
