import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/api.dart';
import '../widgets/app_back_button.dart';
import '../styles/app_sizes.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _firstFieldFocus = FocusNode();
  bool _loading = false;
  bool _passwordVisible = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstFieldFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _firstFieldFocus.dispose();
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.tr('register_title')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          primary: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.all(AppSizes.isCompact(MediaQuery.sizeOf(context).width) ? 16 : 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  focusNode: _firstFieldFocus,
                  controller: _username,
                  decoration: InputDecoration(
                    labelText: context.tr('username'),
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.name,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableInteractiveSelection: true,
                  autofocus: true,
                  validator: (v) {
                    if (v == null || v.trim().length < 3) {
                      return context.tr('min_3_chars');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _displayName,
                  decoration: InputDecoration(
                    labelText: context.tr('display_name_optional'),
                    border: const OutlineInputBorder(),
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
                    border: const OutlineInputBorder(),
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
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                      tooltip: _passwordVisible
                          ? 'Скрыть пароль'
                          : 'Показать пароль',
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.visiblePassword,
                  obscureText: !_passwordVisible,
                  enableSuggestions: false,
                  autocorrect: false,
                  enableInteractiveSelection: true,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) {
                    if (v == null || v.length < 6) {
                      return context.tr('min_6_chars');
                    }
                    return null;
                  },
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
                          if (_formKey.currentState!.validate()) _submit();
                        },
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr('create_account')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
