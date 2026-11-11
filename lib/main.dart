import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'src/core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isSupabaseConfigured) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    supabaseInitialized = true;
  }

  runApp(const KomisiApp());
}
