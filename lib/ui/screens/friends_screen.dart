/// Friends, requests, presence and room invitations in one compact sheet.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../account/account.dart';
import '../../account/auth_backend.dart';
import '../../engine/profiles.dart';
import '../../env.dart';
import '../../game/game_controller.dart';
import '../../multiplayer/transport.dart';
import '../../multiplayer/websocket_transport.dart';
import '../account_scope.dart';
import '../app_scope.dart';
import '../copy.dart';
import '../theme.dart';
import '../widgets/controls.dart';
import '../widgets/sheet.dart';
import '../widgets/stage.dart';
import 'game_screen.dart';

class FriendsScreen extends StatefulWidget {
  final String profileId;
  final int numPlayers;

  /// Test seam: widget tests must never open a real socket.
  @visibleForTesting
  final GameTransport Function(String roomCode, String playerName)?
  transportFactory;

  const FriendsScreen({
    super.key,
    this.profileId = 'buraco',
    this.numPlayers = 2,
    this.transportFactory,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _username = TextEditingController();
  StreamSubscription<RoomInviteEntry>? _inviteSubscription;
  List<FriendEntry> _friends = [];
  List<FriendRequestEntry> _requests = [];
  RoomInviteEntry? _invite;
  Object? _loadError;
  String? _actionError;
  bool _started = false;
  bool _loading = true;
  bool _acting = false;
  bool _pushing = false;

  @override
  void initState() {
    super.initState();
    final scope = context.getInheritedWidgetOfExactType<AccountScope>();
    assert(scope?.notifier != null, 'no AccountScope above this widget');
    _inviteSubscription = scope!.notifier!.roomInvites().listen(
      (invite) {
        if (mounted) setState(() => _invite = invite);
      },
      onError: (Object error, StackTrace _) {
        if (!mounted) return;
        setState(() => _actionError = _accountError(context.copy, error));
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final account = context.account;
      final values = await Future.wait<Object>([
        account.friends(),
        account.friendRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = values[0] as List<FriendEntry>;
        _requests = values[1] as List<FriendRequestEntry>;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _requestFriend() async {
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() => _actionError = context.copy.social.noSuchPlayer);
      return;
    }
    await _act(
      () => context.account.requestFriend(username),
      onSuccess: _username.clear,
    );
  }

  Future<void> _respond(FriendRequestEntry request, bool accept) => _act(
    () => context.account.respondFriendRequest(request.id, accept: accept),
  );

  Future<void> _cancel(FriendRequestEntry request) =>
      _act(() => context.account.cancelFriendRequest(request.id));

  Future<void> _block(FriendEntry friend) =>
      _act(() => context.account.blockUser(friend.userId));

  Future<void> _act(
    Future<void> Function() operation, {
    VoidCallback? onSuccess,
  }) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _actionError = null;
    });
    try {
      await operation();
      if (!mounted) return;
      onSuccess?.call();
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _actionError = _accountError(context.copy, error));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _joinInvite() async {
    final invite = _invite;
    if (invite == null || _acting || _pushing) return;
    setState(() {
      _acting = true;
      _actionError = null;
    });
    try {
      final roomCode = (await context.account.acceptRoomInvite(
        invite.id,
      )).trim();
      if (!mounted) return;
      setState(() => _invite = null);

      final uri = Uri.tryParse(gameHost);
      if (roomCode.isEmpty ||
          uri == null ||
          !uri.hasScheme ||
          !(uri.isScheme('ws') || uri.isScheme('wss'))) {
        setState(() {
          _acting = false;
          _actionError = context.copy.auth.somethingBroke;
        });
        return;
      }

      final l = context.copy;
      final accountName = context.account.displayName?.trim();
      final playerName = accountName == null || accountName.isEmpty
          ? l.onlineDefaultPlayer
          : accountName;
      final cfg = loadProfile(
        widget.profileId,
        numPlayers: widget.numPlayers,
      ).withMatchTarget(context.prefs.target);
      final controller = GameController(
        cfg: cfg,
        autoReady: false,
        transport:
            widget.transportFactory?.call(roomCode, playerName) ??
            WebSocketTransport(
              endpoint: uri,
              roomCode: roomCode,
              playerName: playerName,
            ),
      );
      setState(() {
        _pushing = true;
      });
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => GameScreen(controller: controller),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _actionError = _accountError(context.copy, error);
      });
    }
  }

  @override
  void dispose() {
    _username.dispose();
    unawaited(_inviteSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final l = context.copy;
    final incoming = _requests
        .where((request) => request.incoming)
        .toList(growable: false);
    final outgoing = _requests
        .where((request) => !request.incoming)
        .toList(growable: false);

    return Scaffold(
      body: Room(
        palette: p,
        child: SheetCard(
          width: 1000,
          palette: p,
          children: [
            BackLink(
              label: l.back,
              palette: p,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 12),
            Text(
              l.social.friends,
              style: T.display(34, tracking: -1.4, color: p.text),
            ),
            if (_invite case final invite?) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: p.panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.social.invitedBy(invite.inviterName),
                        style: T.title(12, color: p.text),
                      ),
                    ),
                    TextLink(
                      label: l.social.join,
                      palette: p,
                      color: p.mint,
                      onTap: _joinInvite,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextEntry(
                    label: l.social.add.toUpperCase(),
                    controller: _username,
                    hint: l.social.usernameHint,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _requestFriend(),
                    palette: p,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 130,
                  child: MintButton(
                    label: l.social.add,
                    palette: p,
                    onTap: _requestFriend,
                  ),
                ),
              ],
            ),
            if (_actionError != null) ...[
              const SizedBox(height: 8),
              Text(_actionError!, style: T.body(12, color: p.pink)),
            ],
            const SizedBox(height: 14),
            if (_loading)
              Center(child: CircularProgressIndicator(color: p.mint))
            else if (_loadError case final error?) ...[
              Text(_accountError(l, error), style: T.body(13, color: p.pink)),
              const SizedBox(height: 10),
              Center(
                child: TextLink(
                  label: l.social.friends,
                  palette: p,
                  onTap: _load,
                ),
              ),
            ] else ...[
              ..._requestRows(
                label: l.social.incoming,
                requests: incoming,
                incoming: true,
                palette: p,
                copy: l.social,
              ),
              ..._requestRows(
                label: l.social.outgoing,
                requests: outgoing,
                incoming: false,
                palette: p,
                copy: l.social,
              ),
              FieldLabel(label: l.social.friends.toUpperCase(), palette: p),
              const SizedBox(height: 6),
              if (_friends.isEmpty)
                Text(l.social.noFriends, style: T.body(12, color: p.ash))
              else
                _Columns(
                  target: 288,
                  spacing: 18,
                  maxColumns: 3,
                  children: [
                    // Compact columns keep 30 friends visible at once on a
                    // display wide enough to hold them.
                    for (final friend in _friends.take(30))
                      _FriendRow(
                        friend: friend,
                        palette: p,
                        copy: l.social,
                        onBlock: () => _block(friend),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _requestRows({
    required String label,
    required List<FriendRequestEntry> requests,
    required bool incoming,
    required Palette palette,
    required SocialCopy copy,
  }) {
    if (requests.isEmpty) return const [];
    return [
      FieldLabel(label: label, palette: palette),
      const SizedBox(height: 5),
      _Columns(
        target: 440,
        spacing: 20,
        maxColumns: 3,
        children: [
          for (final request in requests)
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.title(12, color: palette.text),
                  ),
                ),
                if (incoming) ...[
                  TextLink(
                    label: copy.accept,
                    palette: palette,
                    onTap: () => _respond(request, true),
                  ),
                  const SizedBox(width: 10),
                  TextLink(
                    label: copy.decline,
                    palette: palette,
                    onTap: () => _respond(request, false),
                  ),
                ] else
                  TextLink(
                    label: copy.cancel,
                    palette: palette,
                    onTap: () => _cancel(request),
                  ),
              ],
            ),
        ],
      ),
      const SizedBox(height: 12),
    ];
  }
}

/// As many equal columns of [target] width as the sheet can hold, never more
/// than [maxColumns], and one on a phone. The list is the same either way; only
/// how much of it fits on a line changes.
class _Columns extends StatelessWidget {
  final double target;
  final double spacing;
  final int maxColumns;
  final List<Widget> children;

  const _Columns({
    required this.target,
    required this.spacing,
    required this.maxColumns,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth / target).floor().clamp(
        1,
        maxColumns,
      );
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: 4,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _FriendRow extends StatelessWidget {
  final FriendEntry friend;
  final Palette palette;
  final SocialCopy copy;
  final VoidCallback onBlock;

  const _FriendRow({
    required this.friend,
    required this.palette,
    required this.copy,
    required this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    final status = switch (friend.status) {
      'in_lobby' => copy.inLobby,
      'in_game' => copy.inGame,
      _ when friend.online => copy.online,
      _ => null,
    };
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          Container(
            key: friend.online ? ValueKey('online-${friend.userId}') : null,
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: friend.online ? palette.mint : palette.line,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              status == null
                  ? friend.displayName
                  : '${friend.displayName} · $status',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.title(11, color: palette.text),
            ),
          ),
          const SizedBox(width: 6),
          TextLink(
            label: copy.block,
            palette: palette,
            color: palette.ashDim,
            fontSize: 9,
            onTap: onBlock,
          ),
        ],
      ),
    );
  }
}

String _accountError(Copy copy, Object error) {
  if (error is AccountException && error.message == 'no such player') {
    return copy.social.noSuchPlayer;
  }
  final kind = error is AccountException ? error.error : AccountError.unknown;
  final auth = copy.auth;
  return switch (kind) {
    AccountError.badEmail => auth.badEmail,
    AccountError.badCode => auth.badCode,
    AccountError.expiredCode => auth.expiredCode,
    AccountError.weakPassword => auth.weakPassword,
    AccountError.wrongPassword => auth.wrongPassword,
    AccountError.accountExists => auth.accountExists,
    AccountError.offline => auth.offline,
    AccountError.unknown => auth.somethingBroke,
  };
}
