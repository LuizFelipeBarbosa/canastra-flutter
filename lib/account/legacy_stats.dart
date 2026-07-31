/// One-time migration of local pre-account stats into a permanent profile.
library;

import 'dart:async';

import '../ui/app_scope.dart';
import 'account.dart';

/// Watches identity changes and uploads local counters for the first permanent
/// player, without delaying startup or account transitions.
void wireLegacyUpload({required Account account, required AppPrefs prefs}) {
  var uploadInProgress = false;

  Future<void> uploadIfNeeded() async {
    if (uploadInProgress ||
        account.state is! Player ||
        prefs.legacySent ||
        prefs.played <= 0) {
      return;
    }

    uploadInProgress = true;
    try {
      await account.uploadLegacyStats(
        played: prefs.played,
        won: prefs.won,
        best: prefs.best,
      );
      prefs.markLegacySent();
    } finally {
      uploadInProgress = false;
    }
  }

  void onAccountChanged() => unawaited(uploadIfNeeded());

  account.addListener(onAccountChanged);
  onAccountChanged();
}
