const appTitle = 'Komisi';
const brandLogo = 'assets/images/francis_logo.png';

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://vznxoisgzlsuenzfjobw.supabase.co',
);
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_9zyOrno1JD69NpX39jLg2Q_4AToSWwd',
);
final isSupabaseConfigured = supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
bool supabaseInitialized = false;
