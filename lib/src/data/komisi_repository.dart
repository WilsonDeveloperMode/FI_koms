import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';

class KomisiRepository {
  final auth = Supabase.instance.client.auth;
  SupabaseClient get _db => Supabase.instance.client;

  Future<void> signIn({
    required String usernameOrEmail,
    required String password,
  }) async {
    final input = usernameOrEmail.trim();
    final email = input.contains('@')
        ? input
        : await _resolveEmailFromUsername(input);
    if (email == null || email.isEmpty) {
      throw Exception('Username tidak ditemukan.');
    }
    await auth.signInWithPassword(email: email, password: password);
  }

  Future<String?> _resolveEmailFromUsername(String username) async {
    final value = await _db.rpc(
      'get_login_email',
      params: {'p_username': username},
    );
    return value as String?;
  }

  Future<void> signOut() => auth.signOut();

  Future<AppUserProfile?> getMyProfile() async {
    final id = auth.currentUser?.id;
    if (id == null) return null;
    final data = await _db.from('profiles').select().eq('id', id).maybeSingle();
    if (data == null) return null;
    return AppUserProfile.fromJson(data);
  }

  Future<List<AppUserProfile>> getStaffUsers() async {
    final data = await _db
        .from('profiles')
        .select()
        .eq('role', 'staff')
        .order('full_name');
    return (data as List)
        .map((e) => AppUserProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, int>> getStaffContractCounts() async {
    final data = await _db.from('contract_pics').select('staff_id');
    final counts = <String, int>{};
    for (final row in (data as List)) {
      final staffId = (row as Map<String, dynamic>)['staff_id'] as String;
      counts[staffId] = (counts[staffId] ?? 0) + 1;
    }
    return counts;
  }

  Stream<List<StaffCommissionRow>> watchMyCommissions() {
    final uid = auth.currentUser!.id;
    return watchStaffCommissions(uid);
  }

  Stream<List<StaffCommissionRow>> watchStaffCommissions(String staffId) {
    return _db
        .from('contract_pics')
        .stream(primaryKey: ['id'])
        .eq('staff_id', staffId)
        .order('updated_at')
        .asyncMap((rows) async {
          final list = <StaffCommissionRow>[];
          for (final row in rows) {
            final contractId = row['contract_id'] as String;
            final contract = await _db
                .from('contracts')
                .select(
                  'client_id, contract_name, contract_price, commission_month, contract_file_url',
                )
                .eq('id', contractId)
                .maybeSingle();
            String clientName = '-';
            final clientId = contract?['client_id'] as String?;
            if (clientId != null) {
              final client = await _db
                  .from('clients')
                  .select('name')
                  .eq('id', clientId)
                  .maybeSingle();
              clientName = (client?['name'] as String?) ?? '-';
            }
            final picCountResult = await _db.rpc(
              'get_contract_pic_count',
              params: {'p_contract_id': contractId},
            );
            final picCount = (picCountResult as num?)?.toInt() ?? 0;
            final safePicCount = picCount == 0 ? 1 : picCount;
            final allocationPercent = (row['allocation_percent'] as num?)
                ?.toDouble();

            list.add(
              StaffCommissionRow(
                contractPicId: row['id'] as String,
                clientName: clientName,
                contractName: (contract?['contract_name'] as String?) ?? '-',
                commissionMonth:
                    DateTime.tryParse(
                      contract?['commission_month'] as String? ?? '',
                    ) ??
                    DateTime.now(),
                contractAmount: ((contract?['contract_price'] as num?) ?? 0)
                    .toDouble(),
                weighingPercent: allocationPercent ?? (100 / safePicCount),
                commissionValue: (row['commission_value'] as num).toDouble(),
                picCount: picCount,
                paymentStatus: (row['payment_status'] as String) == 'paid'
                    ? PaymentStatus.paid
                    : PaymentStatus.outstanding,
                contractFileUrl: contract?['contract_file_url'] as String?,
                buktiBayarUrl: row['bukti_bayar_url'] as String?,
              ),
            );
          }
          return list;
        });
  }

  Future<void> updateStaffCommission({
    required String contractPicId,
    PaymentStatus? paymentStatus,
  }) async {
    await _db
        .from('contract_pics')
        .update({
          if (paymentStatus != null) 'payment_status': paymentStatus.name,
        })
        .eq('id', contractPicId);
  }

  Future<String> uploadBuktiBayar({
    required String contractPicId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final contractPic = await _db
        .from('contract_pics')
        .select('staff_id, contract_id')
        .eq('id', contractPicId)
        .single();
    final contract = await _db
        .from('contracts')
        .select('commission_month')
        .eq('id', contractPic['contract_id'] as String)
        .single();
    final monthKey =
        DateTime.tryParse(
          contract['commission_month'] as String? ?? '',
        )?.toIso8601String().split('T').first.substring(0, 7) ??
        DateTime.now().toIso8601String().split('T').first.substring(0, 7);
    final staffFolder = contractPic['staff_id'] as String;
    final path =
        'Proof of payment/Staffs/$staffFolder/Month-$monthKey/Photo/$fileName';
    await _db.storage
        .from('komisi-files')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final publicUrl = _db.storage.from('komisi-files').getPublicUrl(path);
    await _db
        .from('contract_pics')
        .update({'bukti_bayar_url': publicUrl})
        .eq('id', contractPicId);
    return publicUrl;
  }

  Future<List<ClientModel>> getClients() async {
    final data = await _db
        .from('clients')
        .select()
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => ClientModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addClient({
    required String name,
    required String address,
    required String phone,
  }) async {
    await _db.from('clients').insert({
      'name': name,
      'address': address,
      'phone_number': phone,
      'created_by': auth.currentUser!.id,
    });
  }

  Future<void> updateClient({
    required String clientId,
    required String name,
    required String address,
    required String phone,
  }) async {
    await _db
        .from('clients')
        .update({'name': name, 'address': address, 'phone_number': phone})
        .eq('id', clientId);
  }

  Future<List<ContractModel>> getContractsByClient(String clientId) async {
    final data = await _db
        .from('contracts')
        .select()
        .eq('client_id', clientId)
        .order('commission_month', ascending: false)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => ContractModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, int>> getPicCountsByContractIds(
    List<String> contractIds,
  ) async {
    if (contractIds.isEmpty) return <String, int>{};
    final data = await _db
        .from('contract_pics')
        .select('contract_id')
        .inFilter('contract_id', contractIds);
    final counts = <String, int>{};
    for (final row in (data as List)) {
      final contractId = (row as Map<String, dynamic>)['contract_id'] as String;
      counts[contractId] = (counts[contractId] ?? 0) + 1;
    }
    return counts;
  }

  Future<String> addContract({
    required String clientId,
    required String contractName,
    required double contractPrice,
    required double commissionPercent,
    required List<String> picStaffIds,
    Map<String, double>? customAllocations,
    DateTime? commissionMonth,
    String? contractFileUrl,
  }) async {
    final month = DateTime(
      (commissionMonth ?? DateTime.now()).year,
      (commissionMonth ?? DateTime.now()).month,
      1,
    );
    final contract = await _db
        .from('contracts')
        .insert({
          'client_id': clientId,
          'contract_name': contractName,
          'contract_price': contractPrice,
          'commission_percent': commissionPercent,
          'commission_month': month.toIso8601String().split('T').first,
          'contract_file_url': contractFileUrl,
          'created_by': auth.currentUser!.id,
        })
        .select()
        .single();

    if (picStaffIds.isEmpty) return contract['id'] as String;

    final totalCommission = contractPrice * (commissionPercent / 100);
    final allocations = _resolveAllocations(
      staffIds: picStaffIds,
      customAllocations: customAllocations,
    );

    final payload = picStaffIds
        .map(
          (staffId) => {
            'contract_id': contract['id'],
            'staff_id': staffId,
            'commission_value': totalCommission * (allocations[staffId]! / 100),
            'allocation_percent': allocations[staffId],
            'payment_status': 'outstanding',
          },
        )
        .toList();

    await _db.from('contract_pics').insert(payload);
    return contract['id'] as String;
  }

  Future<List<String>> getPicStaffIdsByContract(String contractId) async {
    final data = await _db
        .from('contract_pics')
        .select('staff_id')
        .eq('contract_id', contractId);
    return (data as List)
        .map((e) => (e as Map<String, dynamic>)['staff_id'] as String)
        .toList();
  }

  Future<Map<String, double?>> getPicAllocationsByContract(
    String contractId,
  ) async {
    final data = await _db
        .from('contract_pics')
        .select('staff_id, allocation_percent')
        .eq('contract_id', contractId);
    return {
      for (final row in (data as List))
        (row as Map<String, dynamic>)['staff_id'] as String:
            (row['allocation_percent'] as num?)?.toDouble(),
    };
  }

  Future<void> updateContractAndPics({
    required String contractId,
    required String contractName,
    required double contractPrice,
    required double commissionPercent,
    required List<String> picStaffIds,
    Map<String, double>? customAllocations,
    DateTime? commissionMonth,
    String? contractFileUrl,
  }) async {
    final month = DateTime(
      (commissionMonth ?? DateTime.now()).year,
      (commissionMonth ?? DateTime.now()).month,
      1,
    );
    await _db
        .from('contracts')
        .update({
          'contract_name': contractName,
          'contract_price': contractPrice,
          'commission_percent': commissionPercent,
          'commission_month': month.toIso8601String().split('T').first,
          'contract_file_url': contractFileUrl,
        })
        .eq('id', contractId);

    final existingData = await _db
        .from('contract_pics')
        .select('staff_id')
        .eq('contract_id', contractId);

    final existingStaffIds = (existingData as List)
        .map((e) => (e as Map<String, dynamic>)['staff_id'] as String)
        .toSet();
    final selectedStaffIds = picStaffIds.toSet();

    final toDelete = existingStaffIds.difference(selectedStaffIds).toList();
    if (toDelete.isNotEmpty) {
      await _db
          .from('contract_pics')
          .delete()
          .eq('contract_id', contractId)
          .inFilter('staff_id', toDelete);
    }

    if (selectedStaffIds.isEmpty) return;

    final totalCommission = contractPrice * (commissionPercent / 100);
    final orderedStaffIds = selectedStaffIds.toList();
    final allocations = _resolveAllocations(
      staffIds: orderedStaffIds,
      customAllocations: customAllocations,
    );

    for (final staffId in orderedStaffIds) {
      final allocation = allocations[staffId]!;
      if (existingStaffIds.contains(staffId)) {
        await _db
            .from('contract_pics')
            .update({
              'commission_value': totalCommission * (allocation / 100),
              'allocation_percent': allocation,
            })
            .eq('contract_id', contractId)
            .eq('staff_id', staffId);
      } else {
        await _db.from('contract_pics').insert({
          'contract_id': contractId,
          'staff_id': staffId,
          'commission_value': totalCommission * (allocation / 100),
          'allocation_percent': allocation,
          'payment_status': 'outstanding',
        });
      }
    }
  }

  Map<String, double> _resolveAllocations({
    required List<String> staffIds,
    Map<String, double>? customAllocations,
  }) {
    if (staffIds.isEmpty) {
      return <String, double>{};
    }

    final normalized = customAllocations == null
        ? <String, double>{}
        : {
            for (final entry in customAllocations.entries)
              entry.key: double.parse(entry.value.toStringAsFixed(2)),
          };
    if (normalized.isEmpty) {
      final each = 100 / staffIds.length;
      return {
        for (final id in staffIds) id: double.parse(each.toStringAsFixed(2)),
      };
    }

    for (final staffId in staffIds) {
      final value = normalized[staffId];
      if (value == null) {
        throw Exception(
          'Jika pakai alokasi custom, semua PIC wajib diisi persen.',
        );
      }
      if (value <= 0) {
        throw Exception('Persen alokasi harus lebih besar dari 0.');
      }
    }

    final total = staffIds.fold<double>(
      0,
      (sum, id) => sum + (normalized[id] ?? 0),
    );
    if ((total - 100).abs() > 0.01) {
      throw Exception('Total alokasi PIC harus tepat 100%.');
    }

    return {for (final id in staffIds) id: normalized[id]!};
  }

  Future<void> setMonthlyStatusForStaff({
    required String staffId,
    required DateTime month,
    required PaymentStatus status,
  }) async {
    final monthKey = DateTime(
      month.year,
      month.month,
      1,
    ).toIso8601String().split('T').first;
    final contracts = await _db
        .from('contracts')
        .select('id')
        .eq('commission_month', monthKey);
    final contractIds = (contracts as List)
        .map((e) => (e as Map<String, dynamic>)['id'] as String)
        .toList();
    if (contractIds.isEmpty) return;
    await _db
        .from('contract_pics')
        .update({'payment_status': status.name})
        .eq('staff_id', staffId)
        .inFilter('contract_id', contractIds);

    await _db.from('monthly_payouts').upsert({
      'staff_id': staffId,
      'payout_month': monthKey,
      'status': status.name,
    }, onConflict: 'staff_id,payout_month');
  }

  Stream<List<MonthlyPayout>> watchMonthlyPayoutsForStaff(String staffId) {
    return _db
        .from('monthly_payouts')
        .stream(primaryKey: ['id'])
        .eq('staff_id', staffId)
        .order('payout_month', ascending: false)
        .map((rows) => rows.map((e) => MonthlyPayout.fromJson(e)).toList());
  }

  Future<String> uploadMonthlyProof({
    required String staffId,
    required DateTime month,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final monthKey = DateTime(
      month.year,
      month.month,
      1,
    ).toIso8601String().split('T').first;
    final monthFolder = monthKey.substring(0, 7);
    final path =
        'Proof of payment/Staffs/$staffId/Month-$monthFolder/Photo/$fileName';
    await _db.storage
        .from('komisi-files')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final publicUrl = _db.storage.from('komisi-files').getPublicUrl(path);
    await _db.from('monthly_payouts').upsert({
      'staff_id': staffId,
      'payout_month': monthKey,
      'proof_url': publicUrl,
    }, onConflict: 'staff_id,payout_month');
    return publicUrl;
  }

  Future<String> uploadContractDocument({
    required String contractId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final path = 'Contracts/$contractId/File/$fileName';
    await _db.storage
        .from('komisi-files')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final publicUrl = _db.storage.from('komisi-files').getPublicUrl(path);
    await _db
        .from('contracts')
        .update({'contract_file_url': publicUrl})
        .eq('id', contractId);
    return publicUrl;
  }
}
