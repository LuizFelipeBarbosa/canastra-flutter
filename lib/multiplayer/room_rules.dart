/// The compact rule declaration shared by multiplayer clients and hosts.
library;

import '../engine/config.dart';
import '../engine/profiles.dart';

/// The three knobs that define what game a room is playing.
///
/// Deliberately not the whole [RulesConfig] tree: serialising the tree would
/// create a second source of rule truth that can drift from
/// `lib/engine/profiles.dart`. These three rebuild the tree through the same
/// [loadProfile] everyone uses.
class RoomRules {
  final String profileId;
  final int numPlayers;
  final int matchTarget;

  const RoomRules({
    required this.profileId,
    required this.numPlayers,
    required this.matchTarget,
  });

  RulesConfig toConfig() => loadProfile(
    profileId,
    numPlayers: numPlayers,
  ).withMatchTarget(matchTarget);

  /// Validates a client-supplied declaration before a room is created.
  ///
  /// Throws [FormatException] for an unknown profile id, a player count the
  /// profile does not offer, or a target outside 500..10000.
  static RoomRules validated({
    required String profileId,
    required int numPlayers,
    required int matchTarget,
  }) {
    final profileIndex = kProfiles.indexWhere(
      (profile) => profile.id == profileId,
    );
    if (profileIndex == -1) {
      throw FormatException('unknown profile id: $profileId');
    }
    if (!kProfiles[profileIndex].playerCounts.contains(numPlayers)) {
      throw FormatException('$profileId does not support $numPlayers players');
    }
    if (matchTarget < 500 || matchTarget > 10000) {
      throw FormatException('match target must be between 500 and 10000');
    }
    return RoomRules(
      profileId: profileId,
      numPlayers: numPlayers,
      matchTarget: matchTarget,
    );
  }
}
