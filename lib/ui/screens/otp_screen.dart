/// Keeps email sign-in short enough to feel like entering the table, while
/// retaining the address needed to retry the handoff safely.
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

class OtpScreen extends StatefulWidget {
  final String email;
  final bool upgrading;

  const OtpScreen({super.key, required this.email, this.upgrading = false});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();

  bool _pushing = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_pushing) return;

    final account = context.account;
    final auth = context.copy.auth;
    final navigator = Navigator.of(context);
    var succeeded = false;

    setState(() {
      _pushing = true;
      _error = null;
    });
    try {
      await account.verifyOtp(
        widget.email,
        _code.text.trim(),
        upgrading: widget.upgrading,
      );
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

  Future<void> _resend() async {
    if (_pushing) return;

    final account = context.account;
    final auth = context.copy.auth;

    setState(() {
      _pushing = true;
      _error = null;
    });
    try {
      if (widget.upgrading) {
        await account.linkEmail(widget.email);
      } else {
        await account.sendOtp(widget.email);
      }
    } on AccountException catch (exception) {
      if (mounted) {
        setState(() => _error = _authError(auth, exception.error));
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final l = context.copy;

    return Scaffold(
      body: Room(
        palette: p,
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
              l.auth.codeTitle,
              style: T.display(34, tracking: -1.4, color: p.text),
            ),
            const SizedBox(height: 20),
            Text(
              l.auth.codeSentTo(widget.email),
              style: T.body(13, color: p.ash),
            ),
            const SizedBox(height: 20),
            TextEntry(
              label: l.auth.codeLabel,
              controller: _code,
              keyboardType: TextInputType.number,
              enabled: !_pushing,
              palette: p,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: T.body(13, color: p.pink)),
            ],
            const SizedBox(height: 24),
            IgnorePointer(
              ignoring: _pushing,
              child: GoldButton(
                label: l.auth.verify,
                palette: p,
                wide: true,
                onTap: _verify,
              ),
            ),
            const SizedBox(height: 14),
            // A Wrap, not a Row: the two links fit side by side in
            // Portuguese but not quite in English, and a second line
            // beats nine clipped pixels.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 20,
              runSpacing: 8,
              children: [
                IgnorePointer(
                  ignoring: _pushing,
                  child: TextLink(
                    label: l.auth.resend,
                    palette: p,
                    onTap: _resend,
                  ),
                ),
                IgnorePointer(
                  ignoring: _pushing,
                  child: TextLink(
                    label: l.auth.changeEmail,
                    palette: p,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ],
            ),
          ],
        ),
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
