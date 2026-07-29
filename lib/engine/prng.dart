/// A small deterministic PRNG.
///
/// `dart:math`'s `Random` gives no cross-platform reproducibility guarantee,
/// and this engine needs a shuffle that is bit-for-bit identical on the VM and
/// on the web so that `(config, seed, actionLog)` replays — and any future
/// authoritative server re-simulating a client's round — agree exactly.
///
/// xorshift32, kept inside 32 bits so JavaScript's doubles hold every
/// intermediate value exactly.
library;

class Prng {
  int _state;

  Prng(int seed) : _state = (seed & 0x7fffffff) == 0 ? 0x2545f491 : seed & 0x7fffffff;

  /// Next raw 32-bit value.
  int _next() {
    var x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    _state = x & 0xffffffff;
    return _state;
  }

  /// Uniform integer in `[0, bound)`.
  int nextInt(int bound) {
    if (bound <= 0) throw ArgumentError('bound must be positive');
    // Rejection sampling keeps the distribution exactly uniform.
    final limit = 0x100000000 - (0x100000000 % bound);
    int v;
    do {
      v = _next();
    } while (v >= limit);
    return v % bound;
  }

  double nextDouble() => _next() / 0x100000000;

  /// In-place Fisher-Yates shuffle.
  void shuffle<T>(List<T> items) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
  }
}
