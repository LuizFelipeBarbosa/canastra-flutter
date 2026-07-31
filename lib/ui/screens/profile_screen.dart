/// Keeps a table identity useful on its own, while giving a temporary guest a
/// clear path to preserve the games already attached to it.
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

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();

  bool _initializedName = false;
  bool _saved = false;
  bool _pushing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(_clearSaved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializedName) return;
    _initializedName = true;
    _name.text = context.account.displayName ?? '';
  }

  void _clearSaved() {
    if (_saved && mounted) setState(() => _saved = false);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_clearSaved)
      ..dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_pushing) return;

    final account = context.account;
    final auth = context.copy.auth;
    var succeeded = false;

    setState(() {
      _pushing = true;
      _saved = false;
      _error = null;
    });
    try {
      await account.updateDisplayName(_name.text);
      succeeded = true;
    } on AccountException catch (exception) {
      if (mounted) {
        setState(() => _error = _authError(auth, exception.error));
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }

    if (succeeded && mounted) setState(() => _saved = true);
  }

  Future<void> _upgrade() async {
    if (_pushing) return;

    final email = _email.text.trim();
    final account = context.account;
    final auth = context.copy.auth;
    final navigator = Navigator.of(context);
    var succeeded = false;

    setState(() {
      _pushing = true;
      _error = null;
    });
    try {
      await account.linkEmail(email);
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
        MaterialPageRoute<void>(
          builder: (_) => OtpScreen(email: email, upgrading: true),
        ),
      );
    }
  }

  Future<void> _signOut() async {
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
      await account.signOut();
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

  @override
  Widget build(BuildContext context) {
    final account = context.account;
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
                  l.auth.profileTitle,
                  style: T.display(34, tracking: -1.4, color: p.text),
                ),
                const SizedBox(height: 20),
                TextEntry(
                  label: l.auth.displayNameLabel,
                  controller: _name,
                  hint: l.auth.displayNameHint,
                  enabled: !_pushing,
                  palette: p,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: IgnorePointer(
                        ignoring: _pushing,
                        child: MintButton(
                          label: l.auth.save,
                          palette: p,
                          onTap: _save,
                        ),
                      ),
                    ),
                    if (_saved) ...[
                      const SizedBox(width: 14),
                      Text(l.auth.saved, style: mono(10, color: p.ashDim)),
                    ],
                  ],
                ),
                if (account.state is Guest) ...[
                  const SizedBox(height: 22),
                  Text(l.auth.guestBanner, style: mono(10, color: p.ashDim)),
                  const SizedBox(height: 10),
                  Text(l.auth.guestWarning, style: T.body(13, color: p.ash)),
                  const SizedBox(height: 22),
                  Text(
                    l.auth.upgradeTitle,
                    style: T.display(22, tracking: -0.8, color: p.text),
                  ),
                  const SizedBox(height: 10),
                  Text(l.auth.upgradeBlurb, style: T.body(13, color: p.ash)),
                  const SizedBox(height: 16),
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
                    child: GoldButton(
                      label: l.auth.keepMyGames,
                      palette: p,
                      wide: true,
                      onTap: _upgrade,
                    ),
                  ),
                ],
                if (account.state is Player) ...[
                  const SizedBox(height: 18),
                  Center(
                    child: IgnorePointer(
                      ignoring: _pushing,
                      child: TextLink(
                        label: l.auth.signOut,
                        palette: p,
                        onTap: _signOut,
                      ),
                    ),
                  ),
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
