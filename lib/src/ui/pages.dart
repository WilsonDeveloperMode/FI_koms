import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../data/komisi_repository.dart';
import '../domain/models.dart';

final _moneyFormat = NumberFormat.decimalPattern('en_US');

class _MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final formatted = _moneyFormat.format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

double _parseMoneyInput(String value) {
  final cleaned = value.replaceAll(',', '').trim();
  return double.tryParse(cleaned) ?? 0;
}

String _capitalizedName(String value) {
  final parts = value.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
  return parts
      .map((word) {
        final lower = word.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}

Future<void> _openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Widget _statusChip(PaymentStatus status) {
  final isPaid = status == PaymentStatus.paid;
  final color = isPaid ? Colors.green : Colors.red;
  return Text(
    status.name,
    style: TextStyle(color: color, fontWeight: FontWeight.w700),
  );
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  KomisiRepository? _repo;

  @override
  void initState() {
    super.initState();
    if (isSupabaseConfigured && supabaseInitialized) {
      _repo = KomisiRepository();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isSupabaseConfigured || !supabaseInitialized) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(
                  width: 180,
                  child: Image(image: AssetImage(brandLogo)),
                ),
                SizedBox(height: 12),
                Text('Supabase belum dikonfigurasi.'),
                SizedBox(height: 8),
                Text(
                  'Jalankan aplikasi dengan --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    final repo = _repo!;

    return StreamBuilder<AuthState>(
      stream: repo.auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        repo.auth.currentSession,
      ),
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        if (session == null) return LoginPage(repo: repo);
        return FutureBuilder<AppUserProfile?>(
          future: repo.getMyProfile(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final profile = profileSnapshot.data;
            if (profile == null) {
              return Scaffold(
                appBar: AppBar(title: const Text(appTitle)),
                body: const Center(
                  child: Text('Profil tidak ditemukan. Hubungi admin direksi.'),
                ),
              );
            }
            if (profile.role == AppRole.direksi) {
              return DireksiHomePage(repo: repo, me: profile);
            }
            return StaffHomePage(repo: repo, me: profile);
          },
        );
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({required this.repo, super.key});
  final KomisiRepository repo;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  String _friendlyLoginError(Object error) {
    if (error is AuthException) {
      return 'Username atau kata sandi salah.';
    }
    final message = error.toString().toLowerCase();
    if (message.contains('username tidak ditemukan')) {
      return 'Username atau kata sandi salah.';
    }
    return 'Login gagal. Periksa kembali username dan kata sandi.';
  }

  Future<void> _login() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      _showError('Username dan kata sandi wajib diisi.');
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.repo.signIn(
        usernameOrEmail: _username.text.trim(),
        password: _password.text,
      );
    } catch (e) {
      _showError(_friendlyLoginError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/fi_login_bg.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF5A5146),
                    Color(0xFF8A7A68),
                    Color(0xFFB9A791),
                  ],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.04),
                  Colors.black.withValues(alpha: 0.12),
                ],
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 900;
              return Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: isCompact ? constraints.maxWidth : 520,
                  height: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isCompact ? 0 : 28),
                      bottomLeft: Radius.circular(isCompact ? 0 : 28),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.90),
                          border: Border(
                            left: BorderSide(
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 36,
                              vertical: 34,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 430),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 24,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.58),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.72),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Selamat Datang',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Masuk ke dashboard komisi Francis Interior',
                                      style: TextStyle(
                                        color: Colors.black.withValues(
                                          alpha: 0.62,
                                        ),
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    TextField(
                                      controller: _username,
                                      decoration: const InputDecoration(
                                        labelText: 'Username',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _password,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Kata Sandi',
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: _loading ? null : _login,
                                        child: _loading
                                            ? const SizedBox(
                                                height: 16,
                                                width: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Text('Masuk'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class StaffHomePage extends StatefulWidget {
  const StaffHomePage({required this.repo, required this.me, super.key});
  final KomisiRepository repo;
  final AppUserProfile me;

  @override
  State<StaffHomePage> createState() => _StaffHomePageState();
}

class _StaffHomePageState extends State<StaffHomePage> {
  int _refreshKey = 0;
  String _monthLabel(DateTime month) => DateFormat('MMMM yyyy').format(month);

  void _refreshPage() => setState(() => _refreshKey++);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            SizedBox(width: 120, child: Image(image: AssetImage(brandLogo))),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(_capitalizedName(widget.me.fullName)),
            ),
          ),
          IconButton(
            onPressed: _refreshPage,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: widget.repo.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<List<StaffCommissionRow>>(
        key: ValueKey('staff-home-$_refreshKey'),
        stream: widget.repo.watchMyCommissions(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          final monthKeys =
              rows
                  .map(
                    (e) => DateTime(
                      e.commissionMonth.year,
                      e.commissionMonth.month,
                      1,
                    ),
                  )
                  .toSet()
                  .toList()
                ..sort((a, b) => b.compareTo(a));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Komisi Saya',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<MonthlyPayout>>(
                stream: widget.repo.watchMonthlyPayoutsForStaff(widget.me.id),
                builder: (context, payoutSnapshot) {
                  final payouts =
                      payoutSnapshot.data ?? const <MonthlyPayout>[];
                  final payoutMap = <String, MonthlyPayout>{
                    for (final p in payouts)
                      DateFormat('yyyy-MM').format(
                        DateTime(p.payoutMonth.year, p.payoutMonth.month, 1),
                      ): p,
                  };
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Bulan')),
                                    DataColumn(label: Text('Kontrak')),
                                    DataColumn(label: Text('Total Dibayar')),
                                    DataColumn(label: Text('Status Bayar')),
                                    DataColumn(label: Text('Bukti Bayar')),
                                  ],
                                  rows: monthKeys.map((month) {
                                    final key = DateFormat(
                                      'yyyy-MM',
                                    ).format(month);
                                    final monthRows = rows.where(
                                      (r) =>
                                          r.commissionMonth.year ==
                                              month.year &&
                                          r.commissionMonth.month ==
                                              month.month,
                                    );
                                    final contractCount = monthRows.length;
                                    final totalPayable = monthRows.fold<double>(
                                      0,
                                      (sum, row) => sum + row.commissionValue,
                                    );
                                    final payout = payoutMap[key];
                                    final status = payout?.status;
                                    final proofUrl = payout?.proofUrl;
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(_monthLabel(month))),
                                        DataCell(
                                          Text(contractCount.toString()),
                                        ),
                                        DataCell(
                                          Text(
                                            _moneyFormat.format(totalPayable),
                                          ),
                                        ),
                                        DataCell(
                                          status == null
                                              ? const Text('-')
                                              : _statusChip(status),
                                        ),
                                        DataCell(
                                          proofUrl == null
                                              ? const Text('-')
                                              : InkWell(
                                                  onTap: () => _openExternalUrl(
                                                    proofUrl,
                                                  ),
                                                  child: const Text(
                                                    'Lihat file',
                                                    style: TextStyle(
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Klien')),
                        DataColumn(label: Text('Nama Kontrak')),
                        DataColumn(label: Text('Nilai Kontrak')),
                        DataColumn(label: Text('Komisi')),
                        DataColumn(label: Text('Jumlah PIC')),
                        DataColumn(label: Text('Bulan')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: rows
                          .map(
                            (row) => DataRow(
                              cells: [
                                DataCell(Text(row.clientName)),
                                DataCell(Text(row.contractName)),
                                DataCell(
                                  Text(_moneyFormat.format(row.contractAmount)),
                                ),
                                DataCell(
                                  Text(
                                    _moneyFormat.format(row.commissionValue),
                                  ),
                                ),
                                DataCell(Text(row.picCount.toString())),
                                DataCell(
                                  Text(
                                    DateFormat(
                                      'MMM yyyy',
                                    ).format(row.commissionMonth),
                                  ),
                                ),
                                DataCell(_statusChip(row.paymentStatus)),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class DireksiHomePage extends StatefulWidget {
  const DireksiHomePage({required this.repo, required this.me, super.key});
  final KomisiRepository repo;
  final AppUserProfile me;

  @override
  State<DireksiHomePage> createState() => _DireksiHomePageState();
}

class _DireksiHomePageState extends State<DireksiHomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      StaffManagementPage(repo: widget.repo),
      ClientsPage(repo: widget.repo),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            SizedBox(width: 120, child: Image(image: AssetImage(brandLogo))),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(_capitalizedName(widget.me.fullName)),
            ),
          ),
          IconButton(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: widget.repo.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people), label: 'Staf'),
          NavigationDestination(icon: Icon(Icons.business), label: 'Klien'),
        ],
        onDestinationSelected: (value) => setState(() => _index = value),
      ),
    );
  }
}

class StaffManagementPage extends StatelessWidget {
  const StaffManagementPage({required this.repo, super.key});
  final KomisiRepository repo;

  void _openStaffDetail(BuildContext context, AppUserProfile user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffDetailPage(repo: repo, staff: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<AppUserProfile>, Map<String, int>)>(
      future: (() async =>
          (await repo.getStaffUsers(), await repo.getStaffContractCounts()))(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final staff = snapshot.data!.$1;
        final contractCounts = snapshot.data!.$2;
        final maxContractCount = contractCounts.values.isEmpty
            ? 0
            : contractCounts.values.reduce((a, b) => a > b ? a : b);
        final topStaff = staff
            .where((u) => (contractCounts[u.id] ?? 0) == maxContractCount)
            .toList();

        return Container(
          color: const Color(0xFFF6F2EC),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFFFFFFFF),
                  border: Border.all(color: const Color(0xFFE5D8C9)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manajemen Staf',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pilih staf untuk melihat rincian kontrak, komisi, dan status pembayaran.',
                      style: TextStyle(
                        color: const Color(0xFF6E6255),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (topStaff.isNotEmpty && maxContractCount > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Staf dengan kontrak terbanyak: ${topStaff.map((e) => _capitalizedName(e.fullName)).join(', ')}',
                        style: TextStyle(
                          color: const Color(0xFF4B3C2E),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (staff.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5D8C9)),
                  ),
                  child: const Text('Belum ada data staf.'),
                ),
              ...staff.map((user) {
                final count = contractCounts[user.id] ?? 0;
                final initials = user.fullName.trim().isEmpty
                    ? '?'
                    : user.fullName
                          .trim()
                          .split(RegExp(r'\s+'))
                          .take(2)
                          .map((e) => e.substring(0, 1).toUpperCase())
                          .join();
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFE5D8C9)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x331C130A),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () => _openStaffDetail(context, user),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 23,
                            backgroundColor: const Color(0xFFEADCCB),
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4B3C2E),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _capitalizedName(user.fullName),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF4EEE5),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '$count kontrak',
                                        style: const TextStyle(
                                          color: Color(0xFF6B5E52),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _openStaffDetail(context, user),
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('Lihat'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class StaffDetailPage extends StatefulWidget {
  const StaffDetailPage({required this.repo, required this.staff, super.key});
  final KomisiRepository repo;
  final AppUserProfile staff;

  @override
  State<StaffDetailPage> createState() => _StaffDetailPageState();
}

class _StaffDetailPageState extends State<StaffDetailPage> {
  int _refreshKey = 0;
  String _monthLabel(DateTime month) => DateFormat('MMMM yyyy').format(month);
  void _forceRefresh() => setState(() => _refreshKey++);

  Future<void> _setMonthlyStatus(DateTime month, PaymentStatus status) async {
    await widget.repo.setMonthlyStatusForStaff(
      staffId: widget.staff.id,
      month: month,
      status: status,
    );
    _forceRefresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Semua kontrak ${_monthLabel(month)} diubah ke ${status.name}.',
        ),
      ),
    );
  }

  Future<void> _uploadMonthlyProof(DateTime month) async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    if (file.bytes == null) return;
    try {
      final url = await widget.repo.uploadMonthlyProof(
        staffId: widget.staff.id,
        month: month,
        fileName: file.name,
        bytes: file.bytes!,
      );
      _forceRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Bukti terunggah: $url')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unggah gagal: $e')));
    }
  }

  Future<void> _openProof(String url) async {
    await _openExternalUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_capitalizedName(widget.staff.fullName)),
        actions: [
          IconButton(
            onPressed: _forceRefresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: StreamBuilder<List<StaffCommissionRow>>(
        key: ValueKey('staff-comm-$_refreshKey'),
        stream: widget.repo.watchStaffCommissions(widget.staff.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          final monthKeys =
              rows
                  .map(
                    (e) => DateTime(
                      e.commissionMonth.year,
                      e.commissionMonth.month,
                      1,
                    ),
                  )
                  .toSet()
                  .toList()
                ..sort((a, b) => b.compareTo(a));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StreamBuilder<List<MonthlyPayout>>(
                key: ValueKey('staff-monthly-$_refreshKey'),
                stream: widget.repo.watchMonthlyPayoutsForStaff(
                  widget.staff.id,
                ),
                builder: (context, payoutSnapshot) {
                  final payouts =
                      payoutSnapshot.data ?? const <MonthlyPayout>[];
                  final payoutMap = <String, MonthlyPayout>{
                    for (final p in payouts)
                      DateFormat('yyyy-MM').format(
                        DateTime(p.payoutMonth.year, p.payoutMonth.month, 1),
                      ): p,
                  };
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Bulan')),
                                    DataColumn(label: Text('Kontrak')),
                                    DataColumn(label: Text('Total Dibayar')),
                                    DataColumn(label: Text('Status Bayar')),
                                    DataColumn(label: Text('Bukti Bayar')),
                                    DataColumn(label: Text('Aksi')),
                                  ],
                                  rows: monthKeys.map((month) {
                                    final key = DateFormat(
                                      'yyyy-MM',
                                    ).format(month);
                                    final monthRows = rows.where(
                                      (r) =>
                                          r.commissionMonth.year ==
                                              month.year &&
                                          r.commissionMonth.month ==
                                              month.month,
                                    );
                                    final contractCount = monthRows.length;
                                    final totalPayable = monthRows.fold<double>(
                                      0,
                                      (sum, row) => sum + row.commissionValue,
                                    );
                                    final payout = payoutMap[key];
                                    final status = payout?.status;
                                    final proofUrl = payout?.proofUrl;
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(_monthLabel(month))),
                                        DataCell(
                                          Text(contractCount.toString()),
                                        ),
                                        DataCell(
                                          Text(
                                            _moneyFormat.format(totalPayable),
                                          ),
                                        ),
                                        DataCell(
                                          status == null
                                              ? const Text('-')
                                              : _statusChip(status),
                                        ),
                                        DataCell(
                                          proofUrl == null
                                              ? const Text('-')
                                              : InkWell(
                                                  onTap: () =>
                                                      _openProof(proofUrl),
                                                  child: const Text(
                                                    'Lihat file',
                                                    style: TextStyle(
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                        DataCell(
                                          Wrap(
                                            spacing: 4,
                                            children: [
                                              IconButton(
                                                onPressed: () =>
                                                    _setMonthlyStatus(
                                                      month,
                                                      PaymentStatus.paid,
                                                    ),
                                                icon: const Icon(
                                                  Icons.check_circle_outline,
                                                ),
                                                tooltip: 'Set lunas',
                                              ),
                                              IconButton(
                                                onPressed: () =>
                                                    _setMonthlyStatus(
                                                      month,
                                                      PaymentStatus.outstanding,
                                                    ),
                                                icon: const Icon(
                                                  Icons.pending_actions,
                                                ),
                                                tooltip: 'Set tertunda',
                                              ),
                                              IconButton(
                                                onPressed: () =>
                                                    _uploadMonthlyProof(month),
                                                icon: const Icon(
                                                  Icons.upload_file,
                                                ),
                                                tooltip: 'Unggah bukti',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Klien')),
                        DataColumn(label: Text('Nama Kontrak')),
                        DataColumn(label: Text('Bobot')),
                        DataColumn(label: Text('Nilai Kontrak')),
                        DataColumn(label: Text('Komisi')),
                        DataColumn(label: Text('Jumlah PIC')),
                        DataColumn(label: Text('Bulan')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: rows
                          .map(
                            (row) => DataRow(
                              cells: [
                                DataCell(Text(row.clientName)),
                                DataCell(
                                  row.contractFileUrl == null
                                      ? Text(row.contractName)
                                      : InkWell(
                                          onTap: () => _openExternalUrl(
                                            row.contractFileUrl!,
                                          ),
                                          child: Text(
                                            row.contractName,
                                            style: const TextStyle(
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                ),
                                DataCell(
                                  Text(
                                    '${row.weighingPercent.toStringAsFixed(0)}%',
                                  ),
                                ),
                                DataCell(
                                  Text(_moneyFormat.format(row.contractAmount)),
                                ),
                                DataCell(
                                  Text(
                                    _moneyFormat.format(row.commissionValue),
                                  ),
                                ),
                                DataCell(Text(row.picCount.toString())),
                                DataCell(
                                  Text(
                                    DateFormat(
                                      'MMM yyyy',
                                    ).format(row.commissionMonth),
                                  ),
                                ),
                                DataCell(_statusChip(row.paymentStatus)),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ClientsPage extends StatefulWidget {
  const ClientsPage({required this.repo, super.key});
  final KomisiRepository repo;

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  bool _tableView = false;

  Future<void> _addClient() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Klien'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nama'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(labelText: 'Alamat'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'Nomor Telepon'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await widget.repo.addClient(
      name: name.text.trim(),
      address: address.text.trim(),
      phone: phone.text.trim(),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _editClient(ClientModel client) async {
    final name = TextEditingController(text: client.name);
    final address = TextEditingController(text: client.address);
    final phone = TextEditingController(text: client.phoneNumber);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ubah Klien'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nama'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(labelText: 'Alamat'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'Nomor Telepon'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repo.updateClient(
      clientId: client.id,
      name: name.text.trim(),
      address: address.text.trim(),
      phone: phone.text.trim(),
    );
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Klien diperbarui')));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClientModel>>(
      future: widget.repo.getClients(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final clients = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Klien', style: Theme.of(context).textTheme.headlineSmall),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('Daftar'),
                          icon: Icon(Icons.view_agenda_outlined),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('Tabel'),
                          icon: Icon(Icons.table_rows),
                        ),
                      ],
                      selected: {_tableView},
                      onSelectionChanged: (value) =>
                          setState(() => _tableView = value.first),
                    ),
                    FilledButton.icon(
                      onPressed: _addClient,
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah Klien'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_tableView)
              ...clients.map(
                (client) => Card(
                  child: ListTile(
                    title: Text(client.name),
                    subtitle: Text('${client.address}\n${client.phoneNumber}'),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _editClient(client),
                          icon: const Icon(Icons.edit),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClientContractsPage(
                            repo: widget.repo,
                            client: client,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Nama')),
                        DataColumn(label: Text('Alamat')),
                        DataColumn(label: Text('Telepon')),
                        DataColumn(label: Text('Aksi')),
                      ],
                      rows: clients
                          .map(
                            (client) => DataRow(
                              cells: [
                                DataCell(
                                  Text(client.name),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ClientContractsPage(
                                          repo: widget.repo,
                                          client: client,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                DataCell(Text(client.address)),
                                DataCell(Text(client.phoneNumber)),
                                DataCell(
                                  Wrap(
                                    spacing: 4,
                                    children: [
                                      IconButton(
                                        onPressed: () => _editClient(client),
                                        icon: const Icon(Icons.edit),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ClientContractsPage(
                                                    repo: widget.repo,
                                                    client: client,
                                                  ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.open_in_new),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class ClientContractsPage extends StatefulWidget {
  const ClientContractsPage({
    required this.repo,
    required this.client,
    super.key,
  });
  final KomisiRepository repo;
  final ClientModel client;

  @override
  State<ClientContractsPage> createState() => _ClientContractsPageState();
}

class _ClientContractsPageState extends State<ClientContractsPage> {
  bool _tableView = false;
  DateTime _selectedCommissionMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  Future<DateTime?> _pickCommissionMonth(DateTime initialValue) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initialValue,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Pilih Bulan Komisi',
    );
    if (picked == null) return null;
    return DateTime(picked.year, picked.month, 1);
  }

  Map<String, double>? _extractCustomAllocations({
    required Set<String> selectedStaffIds,
    required Map<String, TextEditingController> allocationControllers,
  }) {
    if (selectedStaffIds.isEmpty) return null;
    final custom = <String, double>{};
    var hasAnyCustom = false;

    for (final staffId in selectedStaffIds) {
      final rawText = allocationControllers[staffId]?.text.trim() ?? '';
      if (rawText.isEmpty) continue;
      hasAnyCustom = true;
      final parsed = double.tryParse(rawText.replaceAll(',', '.'));
      if (parsed == null || parsed <= 0) {
        throw Exception('Persen alokasi PIC harus angka lebih besar dari 0.');
      }
      custom[staffId] = parsed;
    }

    if (!hasAnyCustom) return null;
    if (custom.length != selectedStaffIds.length) {
      throw Exception(
        'Jika memakai custom alokasi, semua PIC wajib diisi persentasenya.',
      );
    }
    final total = custom.values.fold<double>(0, (sum, value) => sum + value);
    if ((total - 100).abs() > 0.01) {
      throw Exception('Total alokasi PIC harus tepat 100%.');
    }
    return custom;
  }

  Widget _buildPicAllocationSection({
    required List<AppUserProfile> staff,
    required Set<String> selected,
    required Map<String, TextEditingController> allocationControllers,
    required StateSetter setStateDialog,
    String? allocationWarning,
  }) {
    final customTotal = selected.fold<double>(0, (sum, id) {
      final value = double.tryParse(
        (allocationControllers[id]?.text.trim() ?? '').replaceAll(',', '.'),
      );
      return sum + (value ?? 0);
    });

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3D7C8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PIC & Alokasi Komisi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pilih PIC. Isi persen hanya jika ingin custom. Jika dikosongkan, sistem akan bagi rata otomatis.',
            style: TextStyle(color: Color(0xFF6E6255), fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          if (selected.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF4EEE5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Total custom saat ini: ${customTotal.toStringAsFixed(2)}%',
                style: const TextStyle(
                  color: Color(0xFF5E5246),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 8),
          ...staff.map((s) {
            final isSelected = selected.contains(s.id);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFCF9F4) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFD5B890)
                      : const Color(0xFFE6DBCE),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _capitalizedName(s.fullName),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Checkbox(
                        value: isSelected,
                        onChanged: (v) {
                          setStateDialog(() {
                            if (v == true) {
                              selected.add(s.id);
                            } else {
                              selected.remove(s.id);
                              allocationControllers[s.id]?.clear();
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  if (isSelected)
                    TextField(
                      controller: allocationControllers[s.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Alokasi PIC (%)',
                        hintText: 'Contoh: 50',
                        suffixText: '%',
                      ),
                    ),
                ],
              ),
            );
          }),
          if (allocationWarning != null) ...[
            const SizedBox(height: 4),
            Text(
              allocationWarning,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommissionInputs({
    required TextEditingController priceController,
    required TextEditingController percentController,
    required StateSetter setStateDialog,
  }) {
    final contractValue = _parseMoneyInput(priceController.text);
    final percentValue = double.tryParse(percentController.text.trim()) ?? 0;
    final totalCommission = contractValue * (percentValue / 100);

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: percentController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setStateDialog(() {}),
            decoration: const InputDecoration(
              labelText: 'Persentase Komisi (%)',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Total Komisi (Rp)'),
            child: Text(
              _moneyFormat.format(totalCommission),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addContract() async {
    final name = TextEditingController();
    final price = TextEditingController();
    final percent = TextEditingController();
    String? selectedFileName;
    List<int>? selectedFileBytes;
    final staff = await widget.repo.getStaffUsers();
    if (!mounted) return;
    final selected = <String>{};
    Map<String, double>? customAllocations;
    String? allocationWarning;
    bool isSaving = false;
    final allocationControllers = <String, TextEditingController>{
      for (final s in staff) s.id: TextEditingController(),
    };

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => PopScope(
          canPop: !isSaving,
          child: AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('Tambah Kontrak')),
                if (isSaving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Nama Kontrak',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: price,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_MoneyInputFormatter()],
                      onChanged: (_) => setStateDialog(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Nilai Kontrak',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCommissionInputs(
                      priceController: price,
                      percentController: percent,
                      setStateDialog: setStateDialog,
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await _pickCommissionMonth(
                          _selectedCommissionMonth,
                        );
                        if (picked == null) return;
                        setStateDialog(() {
                          _selectedCommissionMonth = picked;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Bulan Komisi',
                          suffixIcon: Icon(Icons.calendar_month),
                        ),
                        child: Text(
                          DateFormat(
                            'MMMM yyyy',
                          ).format(_selectedCommissionMonth),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await FilePicker.platform.pickFiles(
                              withData: true,
                            );
                            if (picked == null || picked.files.isEmpty) return;
                            final file = picked.files.single;
                            if (file.bytes == null) return;
                            setStateDialog(() {
                              selectedFileName = file.name;
                              selectedFileBytes = file.bytes;
                            });
                          },
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Lampirkan File Kontrak'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedFileName ?? 'Belum ada file',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildPicAllocationSection(
                      staff: staff,
                      selected: selected,
                      allocationControllers: allocationControllers,
                      setStateDialog: setStateDialog,
                      allocationWarning: allocationWarning,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () {
                        try {
                          customAllocations = _extractCustomAllocations(
                            selectedStaffIds: selected,
                            allocationControllers: allocationControllers,
                          );
                          setStateDialog(() => allocationWarning = null);
                          setStateDialog(() => isSaving = true);
                          Navigator.pop(context, true);
                        } catch (e) {
                          setStateDialog(() {
                            allocationWarning = e.toString().replaceFirst(
                              'Exception: ',
                              '',
                            );
                          });
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;

    final contractId = await widget.repo.addContract(
      clientId: widget.client.id,
      contractName: name.text.trim(),
      contractPrice: _parseMoneyInput(price.text),
      commissionPercent: double.tryParse(percent.text.trim()) ?? 0,
      commissionMonth: _selectedCommissionMonth,
      contractFileUrl: null,
      picStaffIds: selected.toList(),
      customAllocations: customAllocations,
    );
    if (selectedFileBytes != null && selectedFileName != null) {
      await widget.repo.uploadContractDocument(
        contractId: contractId,
        fileName: selectedFileName!,
        bytes: Uint8List.fromList(selectedFileBytes!),
      );
    }

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Contract ditambahkan')));
  }

  Future<void> _editContract(ContractModel contract) async {
    final name = TextEditingController(text: contract.contractName);
    final price = TextEditingController(
      text: _moneyFormat.format(contract.contractPrice),
    );
    final percent = TextEditingController(
      text: contract.commissionPercent.toString(),
    );
    String? selectedFileName;
    List<int>? selectedFileBytes;
    DateTime selectedCommissionMonth = DateTime(
      contract.commissionMonth.year,
      contract.commissionMonth.month,
      1,
    );
    final staff = await widget.repo.getStaffUsers();
    final selected = (await widget.repo.getPicStaffIdsByContract(
      contract.id,
    )).toSet();
    Map<String, double>? customAllocations;
    String? allocationWarning;
    bool isSaving = false;
    final existingAllocations = await widget.repo.getPicAllocationsByContract(
      contract.id,
    );
    final allocationControllers = <String, TextEditingController>{
      for (final s in staff)
        s.id: TextEditingController(
          text: (existingAllocations[s.id] == null)
              ? ''
              : existingAllocations[s.id]!.toStringAsFixed(2),
        ),
    };
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => PopScope(
          canPop: !isSaving,
          child: AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('Ubah Kontrak')),
                if (isSaving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Nama Kontrak',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: price,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_MoneyInputFormatter()],
                      onChanged: (_) => setStateDialog(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Nilai Kontrak',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCommissionInputs(
                      priceController: price,
                      percentController: percent,
                      setStateDialog: setStateDialog,
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await _pickCommissionMonth(
                          selectedCommissionMonth,
                        );
                        if (picked == null) return;
                        setStateDialog(() {
                          selectedCommissionMonth = picked;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Bulan Komisi',
                          suffixIcon: Icon(Icons.calendar_month),
                        ),
                        child: Text(
                          DateFormat(
                            'MMMM yyyy',
                          ).format(selectedCommissionMonth),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await FilePicker.platform.pickFiles(
                              withData: true,
                            );
                            if (picked == null || picked.files.isEmpty) return;
                            final file = picked.files.single;
                            if (file.bytes == null) return;
                            setStateDialog(() {
                              selectedFileName = file.name;
                              selectedFileBytes = file.bytes;
                            });
                          },
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Ganti File Kontrak'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedFileName ??
                                (contract.contractFileUrl == null
                                    ? 'Belum ada file'
                                    : 'File saat ini terlampir'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildPicAllocationSection(
                      staff: staff,
                      selected: selected,
                      allocationControllers: allocationControllers,
                      setStateDialog: setStateDialog,
                      allocationWarning: allocationWarning,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () {
                        try {
                          customAllocations = _extractCustomAllocations(
                            selectedStaffIds: selected,
                            allocationControllers: allocationControllers,
                          );
                          setStateDialog(() => allocationWarning = null);
                          setStateDialog(() => isSaving = true);
                          Navigator.pop(context, true);
                        } catch (e) {
                          setStateDialog(() {
                            allocationWarning = e.toString().replaceFirst(
                              'Exception: ',
                              '',
                            );
                          });
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;

    await widget.repo.updateContractAndPics(
      contractId: contract.id,
      contractName: name.text.trim(),
      contractPrice: _parseMoneyInput(price.text),
      commissionPercent: double.tryParse(percent.text.trim()) ?? 0,
      commissionMonth: selectedCommissionMonth,
      picStaffIds: selected.toList(),
      customAllocations: customAllocations,
      contractFileUrl: contract.contractFileUrl,
    );
    if (selectedFileBytes != null && selectedFileName != null) {
      await widget.repo.uploadContractDocument(
        contractId: contract.id,
        fileName: selectedFileName!,
        bytes: Uint8List.fromList(selectedFileBytes!),
      );
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Contract updated')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Kontrak - ${widget.client.name}'),
        actions: [
          IconButton(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<(List<ContractModel>, Map<String, int>)>(
        future: (() async {
          final contracts = await widget.repo.getContractsByClient(
            widget.client.id,
          );
          final picCounts = await widget.repo.getPicCountsByContractIds(
            contracts.map((c) => c.id).toList(),
          );
          return (contracts, picCounts);
        })(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final contracts = snapshot.data!.$1;
          final picCounts = snapshot.data!.$2;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Daftar'),
                        icon: Icon(Icons.view_agenda_outlined),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Tabel'),
                        icon: Icon(Icons.table_rows),
                      ),
                    ],
                    selected: {_tableView},
                    onSelectionChanged: (value) =>
                        setState(() => _tableView = value.first),
                  ),
                  FilledButton.icon(
                    onPressed: _addContract,
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah Kontrak'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!_tableView)
                ...contracts.map(
                  (c) => Card(
                    child: ListTile(
                      title: Text(c.contractName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Nilai: ${_moneyFormat.format(c.contractPrice)} | Komisi: ${c.commissionPercent}%',
                          ),
                          Text(
                            'Bulan: ${DateFormat('MMM yyyy').format(c.commissionMonth)}',
                          ),
                          Text('PIC: ${picCounts[c.id] ?? 0}'),
                          if (c.contractFileUrl != null)
                            InkWell(
                              onTap: () => _openExternalUrl(c.contractFileUrl!),
                              child: const Text(
                                'Lihat lampiran',
                                style: TextStyle(
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        onPressed: () => _editContract(c),
                        icon: const Icon(Icons.edit),
                      ),
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Nama Kontrak')),
                          DataColumn(label: Text('Nilai')),
                          DataColumn(label: Text('Komisi %')),
                          DataColumn(label: Text('Bulan')),
                          DataColumn(label: Text('File Kontrak')),
                          DataColumn(label: Text('Aksi')),
                        ],
                        rows: contracts
                            .map(
                              (c) => DataRow(
                                cells: [
                                  DataCell(Text(c.contractName)),
                                  DataCell(
                                    Text(_moneyFormat.format(c.contractPrice)),
                                  ),
                                  DataCell(
                                    Text(c.commissionPercent.toString()),
                                  ),
                                  DataCell(
                                    Text(
                                      DateFormat(
                                        'MMM yyyy',
                                      ).format(c.commissionMonth),
                                    ),
                                  ),
                                  DataCell(
                                    c.contractFileUrl == null
                                        ? const Text('-')
                                        : InkWell(
                                            onTap: () => _openExternalUrl(
                                              c.contractFileUrl!,
                                            ),
                                            child: const Text(
                                              'Lihat file',
                                              style: TextStyle(
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      onPressed: () => _editContract(c),
                                      icon: const Icon(Icons.edit),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
