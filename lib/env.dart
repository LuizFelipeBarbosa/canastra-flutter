/// What this particular build was pointed at.
///
/// All of it is baked in at compile time rather than typed by the player:
/// `flutter build web --release --dart-define=GAME_HOST=wss://your-host ...`.
/// `tool/netlify_build.sh` is what actually passes them.
///
/// Nothing here is a secret. The Supabase anon key is a public credential whose
/// whole job is to be shipped in a client — row-level security in the database
/// is what decides who may read what, not possession of the key. The service
/// role key, which *is* a secret, lives only on the host as a Fly secret and
/// never appears in this file or in a web build.
library;

/// Where this build looks for its game host.
///
/// The default is what `dart run bin/server.dart` gives you during development.
/// A build served over https must use `wss://` — browsers refuse a plaintext
/// socket from a secure page.
const gameHost = String.fromEnvironment(
  'GAME_HOST',
  defaultValue: 'ws://localhost:8080',
);

/// The Supabase project this build signs in against.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// The public, RLS-gated key that goes with [supabaseUrl].
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Whether this build has an account backend at all.
///
/// False for a plain `flutter run`, for `flutter test`, and for any build whose
/// deploy forgot the defines. Everything that touches Supabase is expected to
/// check this and fall back to the offline path, because the game must deal a
/// hand with no network, no account and no configuration — which is also what
/// lets the test suite run without mocking anything.
const bool hasBackend = supabaseUrl != '' && supabaseAnonKey != '';
