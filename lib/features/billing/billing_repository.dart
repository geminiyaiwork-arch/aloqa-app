/// ALOQA — billing: wallet, subscription, transactions, plans (web /app/billing).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';

@immutable
class Subscription {
  const Subscription({this.plan, this.status = '', this.expiresAt});
  final String? plan;
  final String status;
  final DateTime? expiresAt;

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        plan: j['plan']?.toString(),
        status: (j['status'] ?? '').toString(),
        expiresAt: j['expires_at'] != null
            ? DateTime.tryParse(j['expires_at'].toString())
            : null,
      );
}

@immutable
class WalletTx {
  const WalletTx({
    required this.id,
    required this.amount,
    required this.currency,
    required this.provider,
    required this.status,
    required this.type,
    this.createdAt,
  });

  final int id;
  final int amount;
  final String currency;
  final String provider;
  final String status;
  final String type;
  final DateTime? createdAt;

  bool get isTopup => type == 'topup';

  factory WalletTx.fromJson(Map<String, dynamic> j) => WalletTx(
        id: j['id'] is num ? (j['id'] as num).toInt() : 0,
        amount: j['amount'] is num ? (j['amount'] as num).toInt() : 0,
        currency: (j['currency'] ?? 'UZS').toString(),
        provider: (j['provider'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'].toString())
            : null,
      );
}

@immutable
class WalletInfo {
  const WalletInfo({
    this.balance = 0,
    this.currency = 'UZS',
    this.subscription,
    this.providers = const [],
    this.transactions = const [],
  });

  final int balance;
  final String currency;
  final Subscription? subscription;
  final List<String> providers;
  final List<WalletTx> transactions;

  factory WalletInfo.fromJson(Map<String, dynamic> j) => WalletInfo(
        balance: j['balance'] is num ? (j['balance'] as num).toInt() : 0,
        currency: (j['currency'] ?? 'UZS').toString(),
        subscription: j['subscription'] is Map
            ? Subscription.fromJson(
                Map<String, dynamic>.from(j['subscription'] as Map))
            : null,
        providers: j['providers'] is List
            ? (j['providers'] as List).map((e) => e.toString()).toList()
            : const [],
        transactions: j['transactions'] is List
            ? (j['transactions'] as List)
                .whereType<Map<String, dynamic>>()
                .map(WalletTx.fromJson)
                .toList()
            : const [],
      );
}

@immutable
class Plan {
  const Plan({
    required this.id,
    required this.name,
    this.slug,
    this.maxParticipants = 0,
    this.maxDuration = 0,
    this.cloudStorageGb = 0,
    this.price = 0,
    this.currency,
    this.features = const [],
    this.attendanceEnabled = false,
  });

  final String id;
  final String name;
  final String? slug;
  final int maxParticipants; // 0 = unlimited
  final int maxDuration; // minutes, 0 = unlimited
  final int cloudStorageGb; // 0 = local only
  final num price;
  final String? currency;
  final List<String> features;
  final bool attendanceEnabled; // davomat moduli tarifda yoqilganmi

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        slug: j['slug']?.toString(),
        attendanceEnabled: j['attendance_enabled'] == true ||
            j['attendance_enabled'] == 1 ||
            j['attendance_enabled'] == '1',
        maxParticipants: j['max_participants'] is num
            ? (j['max_participants'] as num).toInt()
            : 0,
        maxDuration:
            j['max_duration'] is num ? (j['max_duration'] as num).toInt() : 0,
        cloudStorageGb: j['cloud_storage_gb'] is num
            ? (j['cloud_storage_gb'] as num).toInt()
            : 0,
        price: j['price'] is num
            ? j['price'] as num
            : num.tryParse((j['price'] ?? '0').toString()) ?? 0,
        currency: j['currency']?.toString(),
        features: j['features_json'] is List
            ? (j['features_json'] as List).map((e) => e.toString()).toList()
            : const [],
      );
}

class BillingRepository {
  BillingRepository(this._dio);
  final Dio _dio;

  static final BillingRepository instance =
      BillingRepository(DioClient.instance.dio);

  Future<WalletInfo> wallet() async {
    final res = await _dio.get<Map<String, dynamic>>('/wallet');
    return WalletInfo.fromJson(res.data ?? {});
  }

  Future<List<Plan>> plans() async {
    final res = await _dio.get<dynamic>('/plans');
    final data = res.data;
    final items = data is Map ? data['plans'] : data;
    if (items is List) {
      return items
          .whereType<Map<String, dynamic>>()
          .map(Plan.fromJson)
          .toList();
    }
    return [];
  }

  Future<void> topup({required int amount, required String provider}) async {
    await _dio.post<dynamic>('/wallet/topup',
        data: {'amount': amount, 'provider': provider});
  }

  Future<void> subscribe(
      {required String planId, required String provider}) async {
    await _dio.post<dynamic>('/subscriptions',
        data: {'plan_id': planId, 'provider': provider});
  }

  /// Davomat moduli statistikasi (tarifda yoqilgan bo'lsa). Yoqilmasa enabled=false.
  Future<AttendanceStats> attendanceStats() async {
    final res = await _dio.get<Map<String, dynamic>>('/attendance/stats');
    return AttendanceStats.fromJson(res.data ?? const {});
  }
}

@immutable
class AttendanceStats {
  const AttendanceStats({
    this.enabled = false,
    this.employeesTotal = 0,
    this.maxEmployees = 0,
    this.reportsCount = 0,
    this.avgPercent = 0,
    this.lastPercent,
    this.lastTitle,
    this.lastPresent = 0,
    this.lastTotal = 0,
  });

  final bool enabled;
  final int employeesTotal;
  final int maxEmployees;
  final int reportsCount;
  final num avgPercent;
  final num? lastPercent;
  final String? lastTitle;
  final int lastPresent;
  final int lastTotal;

  factory AttendanceStats.fromJson(Map<String, dynamic> j) {
    final last = j['last'] is Map ? Map<String, dynamic>.from(j['last'] as Map) : null;
    int asInt(dynamic v) => v is num ? v.toInt() : 0;
    return AttendanceStats(
      enabled: j['enabled'] == true,
      employeesTotal: asInt(j['employees_total']),
      maxEmployees: asInt(j['max_employees']),
      reportsCount: asInt(j['reports_count']),
      avgPercent: j['avg_percent'] is num ? j['avg_percent'] as num : 0,
      lastPercent: last != null && last['percent'] is num ? last['percent'] as num : null,
      lastTitle: last?['meeting_title']?.toString(),
      lastPresent: last != null ? asInt(last['present']) : 0,
      lastTotal: last != null ? asInt(last['total']) : 0,
    );
  }
}

typedef BillingData = ({WalletInfo wallet, List<Plan> plans});

final billingProvider = FutureProvider.autoDispose<BillingData>((ref) async {
  final r = BillingRepository.instance;
  final results = await Future.wait([r.wallet(), r.plans()]);
  return (wallet: results[0] as WalletInfo, plans: results[1] as List<Plan>);
});

/// "Boshqa tarif sotib olish" bosilganda TRUE — to'liq tariflar ro'yxati ko'rinadi.
final showAllPlansProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Davomat statistikasi (tarifda yoqilgan klientlar uchun).
final attendanceStatsProvider = FutureProvider.autoDispose<AttendanceStats>((ref) async {
  try {
    return await BillingRepository.instance.attendanceStats();
  } catch (_) {
    return const AttendanceStats(enabled: false);
  }
});
