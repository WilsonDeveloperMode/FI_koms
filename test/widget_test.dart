import 'package:fi_koms/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows setup message when Supabase is not configured', (tester) async {
    await tester.pumpWidget(const KomisiApp());
    expect(find.textContaining('Supabase belum dikonfigurasi'), findsOneWidget);
  });
}
