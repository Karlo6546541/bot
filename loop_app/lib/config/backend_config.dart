/// Postavke online baze (Supabase).
///
/// Vrijednosti se predaju pri pokretanju, npr.:
/// ```
/// flutter run -d windows \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_KEY=sb_publishable_...
/// ```
/// Bez njih aplikacija radi lokalno (offline), kao i prije.
class BackendConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Javni ključ projekta ("Publishable key", ranije "anon key").
  /// Smije biti u aplikaciji — pristup štite pravila u bazi (RLS).
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  static bool get isOnline => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
