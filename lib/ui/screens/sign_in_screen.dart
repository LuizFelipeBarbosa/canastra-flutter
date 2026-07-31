/// Gives every player a way to keep playing without making an account a toll
/// booth in front of the table.
library;

import 'package:flutter/material.dart';

import '../../account/account.dart';
import '../account_scope.dart';
import '../app_scope.dart';
import '../copy.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/sheet.dart';
import '../widgets/stage.dart';
import 'otp_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _showPassword = false;
  bool _pushing = false;
  String? _error;
  String? _confirmation;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _completeSignIn(
    Future<void> Function(Account account) action,
  ) async {
    if (_pushing) return;

    final account = context.account;
    final auth = context.copy.auth;
    final navigator = Navigator.of(context);
    var succeeded = false;

    setState(() {
      _pushing = true;
      _error = null;
      _confirmation = null;
    });
    try {
      await action(account);
      succeeded = true;
    } on AccountException catch (exception) {
      if (mounted) {
        setState(() => _error = _authError(auth, exception.error));
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }

    if (succeeded && mounted) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  Future<void> _sendCode() async {
    if (_pushing) return;

    final email = _email.text.trim();
    final auth = context.copy.auth;
    if (!email.contains('@') || !email.contains('.')) {
      setState(() {
        _error = auth.badEmail;
        _confirmation = null;
      });
      return;
    }

    final account = context.account;
    final navigator = Navigator.of(context);
    var succeeded = false;

    setState(() {
      _pushing = true;
      _error = null;
      _confirmation = null;
    });
    try {
      await account.sendOtp(email);
      succeeded = true;
    } on AccountException catch (exception) {
      if (mounted) {
        setState(() => _error = _authError(auth, exception.error));
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }

    if (succeeded && mounted) {
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => OtpScreen(email: email)),
      );
    }
  }

  Future<void> _resetPassword() async {
    if (_pushing) return;

    final email = _email.text.trim();
    final account = context.account;
    final auth = context.copy.auth;
    var succeeded = false;

    setState(() {
      _pushing = true;
      _error = null;
      _confirmation = null;
    });
    try {
      await account.sendPasswordReset(email);
      succeeded = true;
    } on AccountException catch (exception) {
      if (mounted) {
        setState(() => _error = _authError(auth, exception.error));
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }

    if (succeeded && mounted) {
      setState(() => _confirmation = auth.codeSentTo(email));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final l = context.copy;

    return Scaffold(
      body: Stage(
        palette: p,
        children: [
          Positioned.fill(
            child: SheetCard(
              palette: p,
              children: [
                IgnorePointer(
                  ignoring: _pushing,
                  child: BackLink(
                    label: l.back,
                    palette: p,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  l.auth.title,
                  style: T.display(34, tracking: -1.4, color: p.text),
                ),
                const SizedBox(height: 20),
                Text(l.auth.blurb, style: T.body(13, color: p.ash)),
                const SizedBox(height: 20),
                IgnorePointer(
                  ignoring: _pushing,
                  child: GoldButton(
                    label: l.auth.playAsGuest,
                    palette: p,
                    wide: true,
                    onTap: () => _completeSignIn(
                      (account) => account.signInAnonymously(),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: Divider(color: p.line)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(l.auth.or, style: mono(10, color: p.ashDim)),
                    ),
                    Expanded(child: Divider(color: p.line)),
                  ],
                ),
                const SizedBox(height: 18),
                TextEntry(
                  label: l.auth.emailLabel,
                  controller: _email,
                  hint: l.auth.emailHint,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_pushing,
                  palette: p,
                ),
                const SizedBox(height: 14),
                IgnorePointer(
                  ignoring: _pushing,
                  child: MintButton(
                    label: l.auth.sendCode,
                    palette: p,
                    onTap: _sendCode,
                  ),
                ),
                const SizedBox(height: 12),
                if (!_showPassword)
                  Center(
                    child: IgnorePointer(
                      ignoring: _pushing,
                      child: TextLink(
                        label: l.auth.usePassword,
                        palette: p,
                        onTap: () => setState(() {
                          _showPassword = true;
                          _error = null;
                          _confirmation = null;
                        }),
                      ),
                    ),
                  )
                else ...[
                  TextEntry(
                    label: l.auth.passwordLabel,
                    controller: _password,
                    hint: l.auth.passwordHint,
                    obscure: true,
                    enabled: !_pushing,
                    palette: p,
                  ),
                  const SizedBox(height: 14),
                  IgnorePointer(
                    ignoring: _pushing,
                    child: MintButton(
                      label: l.auth.verify,
                      palette: p,
                      onTap: () => _completeSignIn(
                        (account) => account.signInWithPassword(
                          _email.text.trim(),
                          _password.text,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IgnorePointer(
                        ignoring: _pushing,
                        child: TextLink(
                          label: l.auth.createAccount,
                          palette: p,
                          onTap: () => _completeSignIn(
                            (account) => account.signUpWithPassword(
                              _email.text.trim(),
                              _password.text,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      IgnorePointer(
                        ignoring: _pushing,
                        child: TextLink(
                          label: l.auth.forgotPassword,
                          palette: p,
                          onTap: _resetPassword,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_confirmation != null) ...[
                  const SizedBox(height: 14),
                  Text(_confirmation!, style: T.body(13, color: p.ash)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: T.body(13, color: p.pink)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _authError(AuthCopy auth, AccountError error) => switch (error) {
  AccountError.badEmail => auth.badEmail,
  AccountError.badCode => auth.badCode,
  AccountError.expiredCode => auth.expiredCode,
  AccountError.weakPassword => auth.weakPassword,
  AccountError.wrongPassword => auth.wrongPassword,
  AccountError.accountExists => auth.accountExists,
  AccountError.offline => auth.offline,
  AccountError.unknown => auth.somethingBroke,
};
