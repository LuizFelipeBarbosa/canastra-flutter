/// Carries client identity through the presentation tree.
///
/// Account state is deliberately separate from theme preferences so only
/// widgets that read identity rebuild when a session changes.
library;

import 'package:flutter/widgets.dart';

import '../account/account.dart';

/// Carries [Account] down the tree and rebuilds whatever reads it.
class AccountScope extends InheritedNotifier<Account> {
  const AccountScope({
    super.key,
    required Account account,
    required super.child,
  }) : super(notifier: account);

  static Account of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AccountScope>();
    assert(scope?.notifier != null, 'no AccountScope above this widget');
    return scope!.notifier!;
  }
}

extension AccountContext on BuildContext {
  Account get account => AccountScope.of(this);
}
