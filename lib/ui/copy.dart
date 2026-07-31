/// Every word the app says, in both languages.
///
/// Buraco is a Brazilian game played in Portuguese at most tables, so PT is not
/// a translation of the EN — each side is written in the register the game is
/// actually spoken in. "Take the whole pile" and "pega o lixo inteiro" are both
/// how a player would say it, not renderings of one another.
///
/// The rules themselves live in `engine/`; this file only names them.
library;

/// The two languages, as the toggle sees them.
enum Lang {
  en,
  pt;

  /// What the toggle offers next — it shows the language you would switch to.
  String get toggleLabel => this == Lang.en ? 'PT' : 'EN';

  Lang get other => this == Lang.en ? Lang.pt : Lang.en;

  static Lang byName(String? name) =>
      Lang.values.firstWhere((l) => l.name == name, orElse: () => Lang.en);
}

class Copy {
  // --- landing ---
  final String kicker;
  final String headline;
  final String sub;
  final String play;
  final String free;

  // --- setup ---
  final String back;
  final String setupTitle;
  final String opponent;
  final String target;
  final String deal;
  final String online;

  /// Difficulty names, lowest first.
  final List<String> levels;

  // --- the table's chrome ---
  final String you;
  final String them;
  final String thinking;
  final String reconnecting;
  final String watching;
  final String round;

  /// The words between the round number and the match target: "FIRST TO".
  final String firstTo;

  // --- zones ---
  final String stock;
  final String pile;
  final String morto;
  final String theirMelds;
  final String myMelds;
  final String playArea;
  final String playIdle;
  final String playReady;
  final String pileDiscard;
  final String pileBatida;

  // --- counts ---

  /// Takes the stock count because languages put the number in different
  /// places around the word meaning "left".
  final String Function(int count) countLeft;

  final String cards;
  final String card1;
  final String empty;
  final String waiting;
  final String taken;

  // --- the action strip ---
  final String selected;
  final String clear;
  final String batida;
  final String roundOver;

  /// Takes the number of unused meld slots.
  final String Function(int count) spotsOpen;

  // --- cards and melds ---
  final List<String> rankNames;
  final List<String> suitNames;
  final String joker;
  final String faceDownCard;
  final String wild;
  final String through;
  final String setOf;
  final String canastra;

  // --- coaching ---
  final String coachDraw;
  final String coachPlay;
  final String coachReady;
  final String coachDiscard;

  /// Takes the opponent's name.
  final String Function(String who) coachBot;

  // --- refusals ---
  final String whyNot;
  final String wnShort;
  final String wnMixed;
  final String wnWilds;
  final String wnExtend;
  final String wnGoOut;
  final String wnMorto;
  final String wnNotAllowedYet;

  // --- what the opponent just did ---
  final String tookPile;
  final String discarded;
  final String melded;
  final String drew;
  final String tookMorto;

  // --- the round sheet ---
  final String youWent;

  /// Takes whoever went out — the opponent's name, or their team.
  final String Function(String who) theyWent;
  final String stockRanOut;
  final String youWinMatch;
  final String youLostMatch;
  final String matchLine;
  final String nextRound;
  final String newMatch;

  /// Score-sheet line names, keyed by the engine's own label for the line.
  final Map<String, String> scoreLines;

  // --- online setup ---
  final String onlineExplainer;
  final String onlinePlayers;
  final String onlineTwoPlayers;
  final String onlineFourPlayers;
  final String onlineTableName;
  final String onlineYourName;
  final String onlinePlayerNameHint;
  final String onlineJoinTable;
  final String onlineWatchTable;
  final String onlineInvalidHost;
  final String onlineMissingTableName;
  final String onlineDefaultPlayer;
  final String onlineCreateTable;
  final String onlineCreating;

  // --- shared controls ---
  final String themeLight;
  final String themeDark;

  // --- table fallbacks ---
  /// Takes the zero-based seat index used by the game state.
  final String Function(int seat) seatFallback;
  final String rotatePrompt;

  // --- the streak counters ---
  final String streak;
  final String won;
  final String played;
  final String best;
  final String soundOn;
  final String soundOff;

  /// Waiting for the rest of an online table to sit down and ready up.
  final LobbyCopy lobby;

  /// Ranked matchmaking and the ladder it feeds.
  final RankedCopy ranked;

  /// Signing in, and everything that hangs off having an account.
  ///
  /// Grouped rather than flattened in here: accounts alone are some forty
  /// strings, and a hundred-and-thirty-parameter constructor is a place
  /// mistakes hide. Read as `l.auth.sendCode`.
  final AuthCopy auth;

  const Copy({
    required this.kicker,
    required this.headline,
    required this.sub,
    required this.play,
    required this.free,
    required this.back,
    required this.setupTitle,
    required this.opponent,
    required this.target,
    required this.deal,
    required this.online,
    required this.levels,
    required this.you,
    required this.them,
    required this.thinking,
    required this.reconnecting,
    required this.watching,
    required this.round,
    required this.firstTo,
    required this.stock,
    required this.pile,
    required this.morto,
    required this.theirMelds,
    required this.myMelds,
    required this.playArea,
    required this.playIdle,
    required this.playReady,
    required this.pileDiscard,
    required this.pileBatida,
    required this.countLeft,
    required this.cards,
    required this.card1,
    required this.empty,
    required this.waiting,
    required this.taken,
    required this.selected,
    required this.clear,
    required this.batida,
    required this.roundOver,
    required this.spotsOpen,
    required this.rankNames,
    required this.suitNames,
    required this.joker,
    required this.faceDownCard,
    required this.wild,
    required this.through,
    required this.setOf,
    required this.canastra,
    required this.coachDraw,
    required this.coachPlay,
    required this.coachReady,
    required this.coachDiscard,
    required this.coachBot,
    required this.whyNot,
    required this.wnShort,
    required this.wnMixed,
    required this.wnWilds,
    required this.wnExtend,
    required this.wnGoOut,
    required this.wnMorto,
    required this.wnNotAllowedYet,
    required this.tookPile,
    required this.discarded,
    required this.melded,
    required this.drew,
    required this.tookMorto,
    required this.youWent,
    required this.theyWent,
    required this.stockRanOut,
    required this.youWinMatch,
    required this.youLostMatch,
    required this.matchLine,
    required this.nextRound,
    required this.newMatch,
    required this.scoreLines,
    required this.onlineExplainer,
    required this.onlinePlayers,
    required this.onlineTwoPlayers,
    required this.onlineFourPlayers,
    required this.onlineTableName,
    required this.onlineYourName,
    required this.onlinePlayerNameHint,
    required this.onlineJoinTable,
    required this.onlineWatchTable,
    required this.onlineInvalidHost,
    required this.onlineMissingTableName,
    required this.onlineDefaultPlayer,
    required this.onlineCreateTable,
    required this.onlineCreating,
    required this.themeLight,
    required this.themeDark,
    required this.seatFallback,
    required this.rotatePrompt,
    required this.streak,
    required this.won,
    required this.played,
    required this.best,
    required this.soundOn,
    required this.soundOff,
    required this.lobby,
    required this.ranked,
    required this.auth,
  });

  static Copy of(Lang lang) => lang == Lang.pt ? _pt : _en;

  /// "3 cards" / "1 card", with the right singular.
  String countCards(int n) => '$n ${n == 1 ? card1 : cards}';

  /// A full spoken card name, such as "Queen of hearts".
  String cardName(int rank, int suit) =>
      '${rankNames[rank]} ${suitNames[suit]}';

  /// A natural card used as a wild keeps its printed identity while also
  /// naming the role it is playing.
  String wildCardName(String name) => '$name, $wild';

  /// A run's spoken name. Keeping the connector in copy lets Portuguese say
  /// "dois a quatro" where English says "Two through Four".
  String runName(int lowRank, int highRank, int suit) {
    if (lowRank == highRank) return cardName(lowRank, suit);
    return '${rankNames[lowRank]} $through ${rankNames[highRank]} '
        '${suitNames[suit]}';
  }

  /// A set's spoken name; its card count is announced separately.
  String setName(int rank) => '$setOf ${rankNames[rank]}';

  /// The eyebrow over the table: "ROUND 2 · FIRST TO 3000".
  String roundLine(int number, int target) =>
      '$round $number · $firstTo $target';

  static const _en = Copy(
    kicker: 'FREE · NO CHIPS · NO ADS',
    headline: 'The table is always open.',
    sub:
        'Buraco the way it is played at home — twos wild, take the whole pile, '
        'and no going out until your morto is in your hand.',
    play: 'Play now',
    free: 'FREE FOREVER · PLAY IN THE BROWSER',
    back: 'Back',
    setupTitle: 'Set the table',
    opponent: 'OPPONENT',
    target: 'PLAY TO',
    deal: 'Deal',
    online: 'Play online',
    levels: ['Loose', 'Steady', 'Sharp'],
    you: 'YOU',
    them: 'THEM',
    thinking: 'THINKING',
    reconnecting: 'Reconnecting…',
    watching: 'WATCHING',
    round: 'ROUND',
    firstTo: 'FIRST TO',
    stock: 'STOCK',
    pile: 'DISCARD',
    morto: 'MORTO',
    theirMelds: 'THEIR MELDS',
    myMelds: 'YOUR MELDS',
    playArea: 'THE TABLE',
    playIdle: 'play cards here',
    playReady: 'click to lay it down',
    pileDiscard: 'click to discard',
    pileBatida: 'click to go out',
    countLeft: _enCountLeft,
    cards: 'cards',
    card1: 'card',
    empty: 'empty',
    waiting: 'waiting',
    taken: 'taken',
    selected: 'SELECTED',
    clear: 'CLEAR',
    batida: 'GO OUT',
    roundOver: 'END THE ROUND',
    spotsOpen: _enSpotsOpen,
    rankNames: [
      'Ace',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Jack',
      'Queen',
      'King',
    ],
    suitNames: ['of clubs', 'of diamonds', 'of hearts', 'of spades'],
    joker: 'Joker',
    faceDownCard: 'Face-down card',
    wild: 'wild',
    through: 'through',
    setOf: 'Set of',
    canastra: 'canastra',
    coachDraw: 'Draw one from the stock, or take the whole discard pile.',
    coachPlay:
        'Pick cards, then click the table to lay them down — or a meld to '
        'extend it.',
    coachReady: 'Click the table to lay these down.',
    coachDiscard:
        'Click the discard pile to put this card down and end your turn.',
    coachBot: _enBotPlaying,
    whyNot: 'WHY NOT',
    wnShort: 'You need at least three cards — two of them real.',
    wnMixed: "Those don't make a set or a run in one suit.",
    wnWilds: 'Only one two per meld.',
    wnExtend: "That doesn't fit this meld.",
    wnGoOut: 'You need one canastra and an empty hand to go out.',
    wnMorto: 'Your morto comes to your hand first.',
    wnNotAllowedYet: "The rules don't allow that right now.",
    tookPile: 'TOOK THE PILE',
    discarded: 'DISCARDED',
    melded: 'MELDED',
    drew: 'DREW',
    tookMorto: 'TOOK THE MORTO',
    youWent: 'You went out',
    theyWent: _enWentOut,
    stockRanOut: 'The stock ran out',
    youWinMatch: 'You win the match',
    youLostMatch: 'You lost the match',
    matchLine: 'MATCH · FIRST TO ',
    nextRound: 'Deal the next round',
    newMatch: 'New match',
    scoreLines: {
      'Melded cards': 'Melded cards',
      'Canastra bonuses': 'Canastra bonuses',
      'Went out': 'Went out',
      'Concealed': 'Concealed',
      'Red threes': 'Red threes',
      'Morto not taken': 'Morto not taken',
      'Cards left in hand': 'Cards left in hand',
      "Opponents' cards": "Opponents' cards",
    },
    onlineExplainer:
        'Everyone playing together joins the same table name. Pick one and '
        'share it — play starts once every seat is ready.',
    onlinePlayers: 'PLAYERS',
    onlineTwoPlayers: '2 · HEAD TO HEAD',
    onlineFourPlayers: '4 · TEAMS',
    onlineTableName: 'TABLE NAME',
    onlineYourName: 'YOUR NAME',
    onlinePlayerNameHint: 'How others see you',
    onlineJoinTable: 'Join the table',
    onlineWatchTable: 'Watch a table',
    onlineInvalidHost: 'This build has no usable host address.',
    onlineMissingTableName: 'Give the table a name so others can find it.',
    onlineDefaultPlayer: 'Player',
    onlineCreateTable: 'Create a table',
    onlineCreating: 'Setting the table…',
    themeLight: 'LIGHT',
    themeDark: 'DARK',
    seatFallback: _enSeatFallback,
    rotatePrompt: 'Turn your device sideways to see the table.',
    streak: 'STREAK ',
    won: 'WON',
    played: 'PLAYED',
    best: 'BEST',
    soundOn: 'SOUND ON',
    soundOff: 'SOUND OFF',
    lobby: _enLobby,
    ranked: _enRanked,
    auth: _enAuth,
  );

  static const _pt = Copy(
    kicker: 'GRÁTIS · SEM FICHAS · SEM ANÚNCIOS',
    headline: 'A mesa está sempre aberta.',
    sub:
        'Buraco como se joga em casa — dois é curinga, pega o lixo inteiro, e '
        'ninguém bate sem pegar o morto.',
    play: 'Jogar agora',
    free: 'GRÁTIS PARA SEMPRE · JOGUE NO NAVEGADOR',
    back: 'Voltar',
    setupTitle: 'Prepare a mesa',
    opponent: 'ADVERSÁRIO',
    target: 'JOGAR ATÉ',
    deal: 'Distribuir',
    online: 'Jogar online',
    levels: ['Solto', 'Firme', 'Afiado'],
    you: 'VOCÊ',
    them: 'ELES',
    thinking: 'PENSANDO',
    reconnecting: 'Reconectando…',
    watching: 'ASSISTINDO',
    round: 'RODADA',
    firstTo: 'ATÉ',
    stock: 'MONTE',
    pile: 'LIXO',
    morto: 'MORTO',
    theirMelds: 'JOGOS DELES',
    myMelds: 'SEUS JOGOS',
    playArea: 'A MESA',
    playIdle: 'baixe as cartas aqui',
    playReady: 'clique para baixar',
    pileDiscard: 'clique para descartar',
    pileBatida: 'clique para bater',
    countLeft: _ptCountLeft,
    cards: 'cartas',
    card1: 'carta',
    empty: 'vazio',
    waiting: 'esperando',
    taken: 'pego',
    selected: 'SELECIONADAS',
    clear: 'LIMPAR',
    batida: 'BATER',
    roundOver: 'ENCERRAR A RODADA',
    spotsOpen: _ptSpotsOpen,
    rankNames: [
      'ás',
      'dois',
      'três',
      'quatro',
      'cinco',
      'seis',
      'sete',
      'oito',
      'nove',
      'dez',
      'valete',
      'dama',
      'rei',
    ],
    suitNames: ['de paus', 'de ouros', 'de copas', 'de espadas'],
    joker: 'coringa',
    faceDownCard: 'carta virada para baixo',
    wild: 'curinga',
    through: 'a',
    setOf: 'Jogo de',
    canastra: 'canastra',
    coachDraw: 'Compre uma do monte, ou pegue o lixo inteiro.',
    coachPlay:
        'Escolha as cartas e clique na mesa para baixar — ou num jogo para '
        'aumentar.',
    coachReady: 'Clique na mesa para baixar essas cartas.',
    coachDiscard: 'Clique no lixo para descartar e encerrar sua vez.',
    coachBot: _ptBotPlaying,
    whyNot: 'POR QUE NÃO',
    wnShort: 'São necessárias três cartas — duas delas naturais.',
    wnMixed: 'Isso não forma trinca nem sequência do mesmo naipe.',
    wnWilds: 'Só um dois por jogo.',
    wnExtend: 'Isso não encaixa nesse jogo.',
    wnGoOut: 'Para bater você precisa de uma canastra e da mão vazia.',
    wnMorto: 'O morto vem para a sua mão primeiro.',
    wnNotAllowedYet: 'As regras não permitem isso agora.',
    tookPile: 'PEGOU O LIXO',
    discarded: 'DESCARTOU',
    melded: 'BAIXOU',
    drew: 'COMPROU',
    tookMorto: 'PEGOU O MORTO',
    youWent: 'Você bateu',
    theyWent: _ptWentOut,
    stockRanOut: 'O monte acabou',
    youWinMatch: 'Você ganhou a partida',
    youLostMatch: 'Você perdeu a partida',
    matchLine: 'PARTIDA · ATÉ ',
    nextRound: 'Distribuir a próxima',
    newMatch: 'Nova partida',
    scoreLines: {
      'Melded cards': 'Cartas baixadas',
      'Canastra bonuses': 'Bônus de canastra',
      'Went out': 'Bateu',
      'Concealed': 'Batida seca',
      'Red threes': 'Três vermelhos',
      'Morto not taken': 'Morto não pego',
      'Cards left in hand': 'Cartas na mão',
      "Opponents' cards": 'Cartas dos adversários',
    },
    onlineExplainer:
        'Todo mundo que vai jogar junto entra com o mesmo nome de mesa. '
        'Escolha um e compartilhe — a partida começa quando todos estiverem '
        'prontos.',
    onlinePlayers: 'JOGADORES',
    onlineTwoPlayers: '2 · UM CONTRA UM',
    onlineFourPlayers: '4 · DUPLAS',
    onlineTableName: 'NOME DA MESA',
    onlineYourName: 'SEU NOME',
    onlinePlayerNameHint: 'Como os outros veem você',
    onlineJoinTable: 'Entrar na mesa',
    onlineWatchTable: 'Assistir uma mesa',
    onlineInvalidHost: 'Esta versão não tem um endereço de servidor válido.',
    onlineMissingTableName: 'Dê um nome à mesa para os outros encontrarem.',
    onlineDefaultPlayer: 'Jogador',
    onlineCreateTable: 'Criar uma mesa',
    onlineCreating: 'Preparando a mesa…',
    themeLight: 'CLARO',
    themeDark: 'ESCURO',
    seatFallback: _ptSeatFallback,
    rotatePrompt: 'Gire o aparelho para ver a mesa.',
    streak: 'SEQUÊNCIA ',
    won: 'GANHAS',
    played: 'JOGADAS',
    best: 'MELHOR',
    soundOn: 'SOM LIGADO',
    soundOff: 'SOM DESLIGADO',
    lobby: _ptLobby,
    ranked: _ptRanked,
    auth: _ptAuth,
  );
}

class LobbyCopy {
  final String title;
  final String codeLabel;
  final String copyCode;
  final String codeCopied;
  final String openSeat;
  final String ready;
  final String unready;
  final String waiting;
  final String leave;
  final String connected;
  final String disconnected;
  final String Function(String profile, int target) tableLine;
  final String Function(int count) spectators;

  const LobbyCopy({
    required this.title,
    required this.codeLabel,
    required this.copyCode,
    required this.codeCopied,
    required this.openSeat,
    required this.ready,
    required this.unready,
    required this.waiting,
    required this.leave,
    required this.connected,
    required this.disconnected,
    required this.tableLine,
    required this.spectators,
  });
}

const _enLobby = LobbyCopy(
  title: 'The table is set',
  codeLabel: 'TABLE CODE',
  copyCode: 'Copy code',
  codeCopied: 'Code copied',
  openSeat: 'Open seat',
  ready: 'Ready',
  unready: 'Not ready',
  waiting: 'waiting for the table…',
  leave: 'Leave table',
  connected: 'Connected',
  disconnected: 'Disconnected',
  tableLine: _enLobbyTableLine,
  spectators: _enSpectators,
);

const _ptLobby = LobbyCopy(
  title: 'A mesa está posta',
  codeLabel: 'CÓDIGO DA MESA',
  copyCode: 'Copiar código',
  codeCopied: 'Código copiado',
  openSeat: 'Lugar aberto',
  ready: 'Estou pronto',
  unready: 'Ainda não',
  waiting: 'esperando a mesa…',
  leave: 'Sair da mesa',
  connected: 'Conectado',
  disconnected: 'Desconectado',
  tableLine: _ptLobbyTableLine,
  spectators: _ptSpectators,
);

class RankedCopy {
  final String findMatch;
  final String searching;
  final String cancel;
  final String leaderboard;
  final String Function(int rank, int percentile) yourRank;
  final String rating;
  final String wins;
  final String losses;
  final String unranked;
  final String matchFound;

  const RankedCopy({
    required this.findMatch,
    required this.searching,
    required this.cancel,
    required this.leaderboard,
    required this.yourRank,
    required this.rating,
    required this.wins,
    required this.losses,
    required this.unranked,
    required this.matchFound,
  });
}

const _enRanked = RankedCopy(
  findMatch: 'Find a match',
  searching: 'Looking for an opponent',
  cancel: 'Cancel',
  leaderboard: 'Leaderboard',
  yourRank: _enYourRank,
  rating: 'RATING',
  wins: 'W',
  losses: 'L',
  unranked: 'Play 10 ranked matches to be listed.',
  matchFound: 'Match found!',
);

const _ptRanked = RankedCopy(
  findMatch: 'Procurar partida',
  searching: 'Procurando adversário',
  cancel: 'Cancelar',
  leaderboard: 'Ranking',
  yourRank: _ptYourRank,
  rating: 'RATING',
  wins: 'V',
  losses: 'D',
  unranked: 'Jogue 10 partidas ranqueadas para entrar no ranking.',
  matchFound: 'Achou!',
);

/// Everything the app says about accounts.
///
/// A guest is a real account that happens to have no way back into it — so the
/// copy never calls it "your account", and never promises more than the browser
/// it lives in can keep.
class AuthCopy {
  // --- the account pill and the sign-in screen ---
  final String signIn;
  final String signOut;
  final String account;
  final String guest;
  final String title;
  final String blurb;
  final String playAsGuest;
  final String withGoogle;
  final String withApple;
  final String or;

  // --- email ---
  final String emailLabel;
  final String emailHint;
  final String sendCode;
  final String usePassword;
  final String passwordLabel;
  final String passwordHint;
  final String forgotPassword;
  final String createAccount;

  // --- the one-time code ---
  final String codeTitle;

  /// Takes the address the code went to.
  final String Function(String email) codeSentTo;
  final String codeLabel;
  final String verify;
  final String resend;
  final String changeEmail;

  // --- the profile ---
  final String profileTitle;
  final String displayNameLabel;
  final String displayNameHint;
  final String save;
  final String saved;

  // --- guest, and leaving guest behind ---
  final String guestBanner;
  final String guestWarning;
  final String keepMyGames;
  final String upgradeTitle;
  final String upgradeBlurb;

  // --- what went wrong ---
  final String badEmail;
  final String badCode;
  final String expiredCode;
  final String weakPassword;
  final String wrongPassword;
  final String accountExists;
  final String offline;
  final String somethingBroke;

  const AuthCopy({
    required this.signIn,
    required this.signOut,
    required this.account,
    required this.guest,
    required this.title,
    required this.blurb,
    required this.playAsGuest,
    required this.withGoogle,
    required this.withApple,
    required this.or,
    required this.emailLabel,
    required this.emailHint,
    required this.sendCode,
    required this.usePassword,
    required this.passwordLabel,
    required this.passwordHint,
    required this.forgotPassword,
    required this.createAccount,
    required this.codeTitle,
    required this.codeSentTo,
    required this.codeLabel,
    required this.verify,
    required this.resend,
    required this.changeEmail,
    required this.profileTitle,
    required this.displayNameLabel,
    required this.displayNameHint,
    required this.save,
    required this.saved,
    required this.guestBanner,
    required this.guestWarning,
    required this.keepMyGames,
    required this.upgradeTitle,
    required this.upgradeBlurb,
    required this.badEmail,
    required this.badCode,
    required this.expiredCode,
    required this.weakPassword,
    required this.wrongPassword,
    required this.accountExists,
    required this.offline,
    required this.somethingBroke,
  });
}

const _enAuth = AuthCopy(
  signIn: 'SIGN IN',
  signOut: 'Sign out',
  account: 'ACCOUNT',
  guest: 'GUEST',
  title: 'Keep your table',
  blurb:
      'An account carries your streak, your record and your friends from one '
      'device to the next. You can also just sit down and play.',
  playAsGuest: 'Play as guest',
  withGoogle: 'Continue with Google',
  withApple: 'Continue with Apple',
  or: 'or',
  emailLabel: 'EMAIL',
  emailHint: 'you@example.com',
  sendCode: 'Send me a code',
  usePassword: 'Use a password instead',
  passwordLabel: 'PASSWORD',
  passwordHint: 'At least eight characters',
  forgotPassword: 'Forgot your password?',
  createAccount: 'Create account',
  codeTitle: 'Check your email',
  codeSentTo: _enCodeSentTo,
  codeLabel: 'SIX-DIGIT CODE',
  verify: 'Sign in',
  resend: 'Send another',
  changeEmail: 'Use a different address',
  profileTitle: 'Your account',
  displayNameLabel: 'NAME AT THE TABLE',
  displayNameHint: 'How others see you',
  save: 'Save',
  saved: 'Saved',
  guestBanner: 'You are playing as a guest.',
  guestWarning:
      'A guest game lives in this browser only. Clear your browsing data and it '
      'is gone for good — there is no way to get it back.',
  keepMyGames: 'Keep my games',
  upgradeTitle: 'Keep your games',
  upgradeBlurb:
      'Add an email and everything you have played so far comes with you — same '
      'record, same streak, same friends, on any device.',
  badEmail: 'That does not look like an email address.',
  badCode: 'That code is not right. Check it and try again.',
  expiredCode: 'That code has expired. Ask for another.',
  weakPassword: 'Use at least eight characters.',
  wrongPassword: 'That email and password do not match.',
  accountExists:
      'An account with that email already exists. Signing into it will leave '
      'this guest game behind.',
  offline: 'No connection. You can still play offline.',
  somethingBroke: 'That did not work. Try again in a moment.',
);

const _ptAuth = AuthCopy(
  signIn: 'ENTRAR',
  signOut: 'Sair',
  account: 'CONTA',
  guest: 'VISITANTE',
  title: 'Guarde a sua mesa',
  blurb:
      'Com uma conta a sua sequência, o seu retrospecto e os seus parceiros vão '
      'com você para qualquer aparelho. Ou senta e joga, do mesmo jeito.',
  playAsGuest: 'Jogar como visitante',
  withGoogle: 'Continuar com o Google',
  withApple: 'Continuar com a Apple',
  or: 'ou',
  emailLabel: 'E-MAIL',
  emailHint: 'voce@exemplo.com',
  sendCode: 'Me manda um código',
  usePassword: 'Usar senha',
  passwordLabel: 'SENHA',
  passwordHint: 'No mínimo oito caracteres',
  forgotPassword: 'Esqueceu a senha?',
  createAccount: 'Criar conta',
  codeTitle: 'Olhe o seu e-mail',
  codeSentTo: _ptCodeSentTo,
  codeLabel: 'CÓDIGO DE SEIS DÍGITOS',
  verify: 'Entrar',
  resend: 'Mandar outro',
  changeEmail: 'Usar outro endereço',
  profileTitle: 'Sua conta',
  displayNameLabel: 'NOME NA MESA',
  displayNameHint: 'Como os outros veem você',
  save: 'Salvar',
  saved: 'Salvo',
  guestBanner: 'Você está jogando como visitante.',
  guestWarning:
      'Um jogo de visitante fica só neste navegador. Se limpar os dados de '
      'navegação, acabou — não tem como recuperar.',
  keepMyGames: 'Guardar meus jogos',
  upgradeTitle: 'Guarde os seus jogos',
  upgradeBlurb:
      'Coloque um e-mail e tudo que você já jogou vai junto — mesmo retrospecto, '
      'mesma sequência, mesmos parceiros, em qualquer aparelho.',
  badEmail: 'Isso não parece um endereço de e-mail.',
  badCode: 'Esse código não confere. Veja de novo e tente outra vez.',
  expiredCode: 'Esse código venceu. Peça outro.',
  weakPassword: 'Use no mínimo oito caracteres.',
  wrongPassword: 'Esse e-mail e essa senha não batem.',
  accountExists:
      'Já existe uma conta com esse e-mail. Se entrar nela, este jogo de '
      'visitante fica para trás.',
  offline: 'Sem conexão. Dá para jogar offline do mesmo jeito.',
  somethingBroke: 'Não deu certo. Tente de novo daqui a pouco.',
);

// Torn out as top-level functions because a const constructor cannot hold a
// closure.
String _enCodeSentTo(String email) => 'We sent a six-digit code to $email.';
String _ptCodeSentTo(String email) =>
    'Mandamos um código de seis dígitos para $email.';
String _enYourRank(int rank, int percentile) => '#$rank - top $percentile%';
String _ptYourRank(int rank, int percentile) => '#$rank - top $percentile%';
String _enBotPlaying(String who) => '$who is playing.';
String _ptBotPlaying(String who) => '$who está jogando.';
String _enWentOut(String who) => '$who went out';
String _ptWentOut(String who) => '$who bateu';
String _enLobbyTableLine(String profile, int target) =>
    '$profile · first to $target';
String _ptLobbyTableLine(String profile, int target) =>
    '$profile · até $target';
String _enSpectators(int count) =>
    '$count ${count == 1 ? 'spectator' : 'spectators'}';
String _ptSpectators(int count) => '$count assistindo';
String _enSeatFallback(int seat) => 'Seat $seat';
String _ptSeatFallback(int seat) => 'Assento $seat';
String _enCountLeft(int count) => '$count left';
String _ptCountLeft(int count) => '${count == 1 ? 'resta' : 'restam'} $count';
String _enSpotsOpen(int count) =>
    '$count ${count == 1 ? 'SPOT OPEN' : 'SPOTS OPEN'} FOR WHAT YOU HOLD';
String _ptSpotsOpen(int count) =>
    '$count ${count == 1 ? 'LUGAR ABERTO' : 'LUGARES ABERTOS'} '
    'PARA O QUE VOCÊ TEM';

/// How a variant is sold on the landing screen.
///
/// The rules these describe live in `engine/profiles.dart`; this is only the
/// pitch, which is why it is shorter than the blurb the engine's profile carries
/// and why it has to be translated.
class VariantCopy {
  final String tagline;
  final String blurb;
  const VariantCopy(this.tagline, this.blurb);
}

/// Keyed by `GameProfile.id`.
const Map<Lang, Map<String, VariantCopy>> kVariantCopy = {
  Lang.en: {
    'buraco': VariantCopy(
      'BRAZILIAN HOUSE RULES',
      'Sequences and sets, twos are wild, take the whole discard pile, and '
          'pick up your morto before you can go out.',
    ),
    'canasta': VariantCopy(
      'CLASSIC AMERICAN',
      'Sets only, and the pile is frozen until you meld.',
    ),
    'biriba': VariantCopy(
      'GREEK COUSIN',
      'Buraco with jokers in the deck and a dead hand that becomes fresh stock.',
    ),
    'rummy': VariantCopy(
      'QUICK AND SIMPLE',
      'One deck, no morto, first to empty their hand.',
    ),
  },
  Lang.pt: {
    'buraco': VariantCopy(
      'REGRA DA CASA',
      'Sequências e trincas, dois é curinga, pega o lixo inteiro, e pegue o '
          'morto antes de bater.',
    ),
    'canasta': VariantCopy(
      'CLÁSSICO AMERICANO',
      'Só trincas, e o lixo fica congelado até você baixar.',
    ),
    'biriba': VariantCopy(
      'PRIMO GREGO',
      'Buraco com curingas no baralho e uma mão morta que vira monte novo.',
    ),
    'rummy': VariantCopy(
      'RÁPIDO E SIMPLES',
      'Um baralho, sem morto, o primeiro a esvaziar a mão.',
    ),
  },
};

VariantCopy variantCopy(Lang lang, String id) {
  final known = kVariantCopy[lang]?[id] ?? kVariantCopy[Lang.en]?[id];
  if (known != null) return known;

  final words = id
      .trim()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  final name = words.isEmpty
      ? (lang == Lang.pt ? 'VARIANTE' : 'VARIANT')
      : words.toUpperCase();
  final description = lang == Lang.pt
      ? 'Uma variante personalizada de ${words.isEmpty ? 'jogo' : words}.'
      : 'A custom ${words.isEmpty ? 'game' : words} variant.';
  return VariantCopy(name, description);
}
