enum AppRole { direksi, staff }

enum PaymentStatus { paid, outstanding }

class AppUserProfile {
  const AppUserProfile({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    required this.role,
    this.phone,
  });

  final String id;
  final String fullName;
  final String username;
  final String email;
  final AppRole role;
  final String? phone;

  factory AppUserProfile.fromJson(Map<String, dynamic> json) {
    return AppUserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: (json['role'] as String) == 'direksi'
          ? AppRole.direksi
          : AppRole.staff,
      phone: json['phone'] as String?,
    );
  }
}

class ClientModel {
  const ClientModel({
    required this.id,
    required this.name,
    required this.address,
    required this.phoneNumber,
  });

  final String id;
  final String name;
  final String address;
  final String phoneNumber;

  factory ClientModel.fromJson(Map<String, dynamic> json) {
    return ClientModel(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      phoneNumber: json['phone_number'] as String,
    );
  }
}

class ContractModel {
  const ContractModel({
    required this.id,
    required this.contractName,
    required this.contractPrice,
    required this.commissionPercent,
    required this.commissionMonth,
    this.contractFileUrl,
  });
  //test

  final String id;
  final String contractName;
  final double contractPrice;
  final double commissionPercent;
  final DateTime commissionMonth;
  final String? contractFileUrl;

  factory ContractModel.fromJson(Map<String, dynamic> json) {
    return ContractModel(
      id: json['id'] as String,
      contractName: json['contract_name'] as String,
      contractPrice: (json['contract_price'] as num).toDouble(),
      commissionPercent: (json['commission_percent'] as num).toDouble(),
      commissionMonth:
          DateTime.tryParse(json['commission_month'] as String? ?? '') ??
          DateTime.now(),
      contractFileUrl: json['contract_file_url'] as String?,
    );
  }
}

class StaffCommissionRow {
  const StaffCommissionRow({
    required this.contractPicId,
    required this.clientName,
    required this.contractName,
    required this.commissionMonth,
    required this.contractAmount,
    required this.weighingPercent,
    required this.commissionValue,
    required this.picCount,
    required this.paymentStatus,
    this.contractFileUrl,
    this.buktiBayarUrl,
  });

  final String contractPicId;
  final String clientName;
  final String contractName;
  final DateTime commissionMonth;
  final double contractAmount;
  final double weighingPercent;
  final double commissionValue;
  final int picCount;
  final PaymentStatus paymentStatus;
  final String? contractFileUrl;
  final String? buktiBayarUrl;
}

class MonthlyPayout {
  const MonthlyPayout({
    required this.staffId,
    required this.payoutMonth,
    required this.status,
    this.proofUrl,
  });

  final String staffId;
  final DateTime payoutMonth;
  final PaymentStatus status;
  final String? proofUrl;

  factory MonthlyPayout.fromJson(Map<String, dynamic> json) {
    return MonthlyPayout(
      staffId: json['staff_id'] as String,
      payoutMonth:
          DateTime.tryParse(json['payout_month'] as String? ?? '') ??
          DateTime.now(),
      status: (json['status'] as String) == 'paid'
          ? PaymentStatus.paid
          : PaymentStatus.outstanding,
      proofUrl: json['proof_url'] as String?,
    );
  }
}
