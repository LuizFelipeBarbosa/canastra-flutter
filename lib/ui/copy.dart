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
  final String left;
  final String left1;
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
  final String spotsOpen;

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
  final String onlineInvalidHost;
  final String onlineMissingTableName;
  final String onlineDefaultPlayer;

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
    required this.left,
    required this.left1,
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
    required this.onlineInvalidHost,
    required this.onlineMissingTableName,
    required this.onlineDefaultPlayer,
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
  });

  static Copy of(Lang lang) => lang == Lang.pt ? _pt : _en;

  /// "3 cards" / "1 card", with the right singular.
  String countCards(int n) => '$n ${n == 1 ? card1 : cards}';

  /// "24 left" / "1 left".
  String countLeft(int n) => '$n ${n == 1 ? left1 : left}';

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
    left: 'left',
    left1: 'left',
    cards: 'cards',
    card1: 'card',
    empty: 'empty',
    waiting: 'waiting',
    taken: 'taken',
    selected: 'SELECTED',
    clear: 'CLEAR',
    batida: 'GO OUT',
    roundOver: 'END THE ROUND',
    spotsOpen: 'SPOTS OPEN FOR WHAT YOU HOLD',
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
    onlineInvalidHost: 'This build has no usable host address.',
    onlineMissingTableName: 'Give the table a name so others can find it.',
    onlineDefaultPlayer: 'Player',
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
    left: 'restam',
    left1: 'resta',
    cards: 'cartas',
    card1: 'carta',
    empty: 'vazio',
    waiting: 'esperando',
    taken: 'pego',
    selected: 'SELECIONADAS',
    clear: 'LIMPAR',
    batida: 'BATER',
    roundOver: 'ENCERRAR A RODADA',
    spotsOpen: 'LUGARES ABERTOS PARA O QUE VOCÊ TEM',
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
    onlineInvalidHost: 'Esta versão não tem um endereço de servidor válido.',
    onlineMissingTableName: 'Dê um nome à mesa para os outros encontrarem.',
    onlineDefaultPlayer: 'Jogador',
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
  );
}

// Torn out as top-level functions because a const constructor cannot hold a
// closure.
String _enBotPlaying(String who) => '$who is playing.';
String _ptBotPlaying(String who) => '$who está jogando.';
String _enWentOut(String who) => '$who went out';
String _ptWentOut(String who) => '$who bateu';
String _enSeatFallback(int seat) => 'Seat $seat';
String _ptSeatFallback(int seat) => 'Assento $seat';

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

VariantCopy variantCopy(Lang lang, String id) =>
    kVariantCopy[lang]![id] ?? kVariantCopy[Lang.en]![id]!;
