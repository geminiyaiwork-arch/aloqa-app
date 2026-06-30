/// ALOQA — employees / attendance roster (web /app/employees parity).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../meeting/meeting_models.dart' show AttendanceItem;

/// Kontakt (uchrashuv ishtirokchisi) — davomatga hodim qo'shishda tanlash uchun.
@immutable
class MeetingContact {
  const MeetingContact({required this.name, this.phone, this.email, this.avatar});
  final String name;
  final String? phone;
  final String? email;
  final String? avatar;

  factory MeetingContact.fromJson(Map<String, dynamic> j) => MeetingContact(
        name: (j['name'] ?? '').toString(),
        phone: j['phone']?.toString(),
        email: j['email']?.toString(),
        avatar: j['avatar']?.toString(),
      );
}

/// Davomat hisoboti (Davomat menyusi ro'yxati + Batafsil).
@immutable
class AttendanceHistoryReport {
  const AttendanceHistoryReport({
    this.id = 0,
    this.meetingId = 0,
    this.sessionNo = 1,
    this.meetingTitle = '',
    this.meetingCode,
    this.total = 0,
    this.present = 0,
    this.absent = 0,
    this.percent = 0,
    this.startedAt,
    this.endedAt,
    this.generatedAt,
    this.generatedByName,
    this.items = const [],
  });

  final int id;
  final int meetingId;
  final int sessionNo;
  final String meetingTitle;
  final String? meetingCode;
  final int total;
  final int present;
  final int absent;
  final double percent;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? generatedAt;
  final String? generatedByName;
  final List<AttendanceItem> items;

  factory AttendanceHistoryReport.fromJson(Map<String, dynamic> j) {
    DateTime? dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    int i(dynamic v) => v is num ? v.toInt() : 0;
    return AttendanceHistoryReport(
      id: i(j['id']),
      meetingId: i(j['meeting_id']),
      sessionNo: j['session_no'] is num ? (j['session_no'] as num).toInt() : 1,
      meetingTitle: (j['meeting_title'] ?? '').toString(),
      meetingCode: j['meeting_code']?.toString(),
      total: i(j['total']),
      present: i(j['present']),
      absent: i(j['absent']),
      percent: j['percent'] is num ? (j['percent'] as num).toDouble() : 0,
      startedAt: dt(j['started_at']),
      endedAt: dt(j['ended_at']),
      generatedAt: dt(j['generated_at']),
      generatedByName: j['generated_by_name']?.toString(),
      items: j['items'] is List
          ? (j['items'] as List)
              .whereType<Map<String, dynamic>>()
              .map(AttendanceItem.fromJson)
              .toList()
          : const [],
    );
  }
}

@immutable
class Employee {
  const Employee({
    required this.id,
    required this.name,
    this.position,
    this.phone,
    this.photo,
    this.linked = false,
  });
  final int id;
  final String name;
  final String? position;
  final String? phone;
  final String? photo;

  /// True when this employee's phone is bound to a login account → attendance
  /// matching is STABLE (account-based), not just name-string (#10).
  final bool linked;

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: j['id'] is num ? (j['id'] as num).toInt() : 0,
        name: (j['name'] ?? '').toString(),
        position: j['position']?.toString(),
        phone: j['phone']?.toString(),
        photo: j['photo']?.toString(),
        linked: j['linked'] == true,
      );
}

@immutable
class EmployeesResult {
  const EmployeesResult({
    this.employees = const [],
    this.attendanceEnabled = false,
    this.maxEmployees = 0,
  });

  final List<Employee> employees;
  final bool attendanceEnabled;
  final int maxEmployees;

  factory EmployeesResult.fromJson(Map<String, dynamic> j) => EmployeesResult(
        employees: j['employees'] is List
            ? (j['employees'] as List)
                .whereType<Map<String, dynamic>>()
                .map(Employee.fromJson)
                .toList()
            : const [],
        attendanceEnabled: j['attendance_enabled'] == true,
        maxEmployees:
            j['max_employees'] is num ? (j['max_employees'] as num).toInt() : 0,
      );
}

class EmployeesRepository {
  EmployeesRepository(this._dio);
  final Dio _dio;

  static final EmployeesRepository instance =
      EmployeesRepository(DioClient.instance.dio);

  Future<EmployeesResult> list() async {
    final res = await _dio.get<Map<String, dynamic>>('/employees');
    return EmployeesResult.fromJson(res.data ?? {});
  }

  Future<void> create({
    required String name,
    String? position,
    String? phone,
    List<int>? photoBytes,
    String? photoFilename,
  }) async {
    final form = FormData.fromMap({
      'name': name.trim(),
      if (position != null && position.trim().isNotEmpty)
        'position': position.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (photoBytes != null)
        'photo': MultipartFile.fromBytes(photoBytes,
            filename: photoFilename ?? 'photo.jpg'),
    });
    await _dio.post<dynamic>('/employees', data: form);
  }

  /// Edit an employee — name/position/phone + optional photo replace. Sent as a
  /// multipart POST to /employees/{id} (web parity). Empty position/phone clear
  /// the field server-side (and clearing phone unlinks the account).
  Future<void> update(
    int id, {
    required String name,
    String? position,
    String? phone,
    List<int>? photoBytes,
    String? photoFilename,
  }) async {
    final form = FormData.fromMap({
      'name': name.trim(),
      'position': position?.trim() ?? '',
      'phone': phone?.trim() ?? '',
      if (photoBytes != null)
        'photo': MultipartFile.fromBytes(photoBytes,
            filename: photoFilename ?? 'photo.jpg'),
    });
    await _dio.post<dynamic>('/employees/$id', data: form);
  }

  Future<void> delete(int id) async {
    await _dio.delete<dynamic>('/employees/$id');
  }

  /// Uchrashuv kontaktlari (davomatga hodim qo'shishda tanlash uchun).
  Future<List<MeetingContact>> meetingContacts() async {
    final res = await _dio.get<Map<String, dynamic>>('/me/meeting-contacts');
    final list = res.data?['contacts'];
    return list is List
        ? list
            .whereType<Map<String, dynamic>>()
            .map(MeetingContact.fromJson)
            .toList()
        : <MeetingContact>[];
  }

  /// Davomat hisobotlari tarixi (Davomat menyusi).
  Future<List<AttendanceHistoryReport>> attendanceHistory() async {
    final res = await _dio.get<Map<String, dynamic>>('/attendance/history');
    final list = res.data?['reports'];
    return list is List
        ? list
            .whereType<Map<String, dynamic>>()
            .map(AttendanceHistoryReport.fromJson)
            .toList()
        : <AttendanceHistoryReport>[];
  }
}

final employeesProvider =
    FutureProvider.autoDispose<EmployeesResult>((ref) async {
  return EmployeesRepository.instance.list();
});

final attendanceHistoryProvider =
    FutureProvider.autoDispose<List<AttendanceHistoryReport>>((ref) async {
  return EmployeesRepository.instance.attendanceHistory();
});
