/// Chooses a real identity provider only for builds configured with one.
///
/// Startup remains bounded and offline-safe: missing configuration or any
/// initialisation failure falls back to the same in-memory backend tests use.
library;

import '../env.dart';
import 'auth_backend.dart';
import 'fake_auth_backend.dart';
import 'supabase_auth_backend.dart';

Future<AuthBackend> openAuthBackend() async {
  if (!hasBackend) return FakeAuthBackend();

  try {
    await SupabaseAuthBackend.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    ).timeout(const Duration(seconds: 3));
    return SupabaseAuthBackend();
  } on Object {
    return FakeAuthBackend();
  }
}
