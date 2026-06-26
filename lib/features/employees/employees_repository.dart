/// ALOQA — employees / attendance roster (web /app/employees parity).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';

@immutable
class Employee {
  const Employee({required this.id, required this.name, this.position, this.photo});
  final int id;
  final String name;
  final String? position;
  final String? photo;

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: j['id'] is num ? (j['id'] as num).toInt() : 0,
        name: (j['name'] ?? '').toString(),
        position: j['position']?.toString(),
        photo: j['photo']?.toString(),
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
    List<int>? photoBytes,
    String? photoFilename,
  }) async {
    final form = FormData.fromMap({
      'name': name.trim(),
      if (position != null && position.trim().isNotEmpty)
        'position': position.trim(),
      if (photoBytes != null)
        'photo': MultipartFile.fromBytes(photoBytes,
            filename: photoFilename ?? 'photo.jpg'),
    });
    await _dio.post<dynamic>('/employees', data: form);
  }

  Future<void> delete(int id) async {
    await _dio.delete<dynamic>('/employees/$id');
  }
}

final employeesProvider =
    FutureProvider.autoDispose<EmployeesResult>((ref) async {
  return EmployeesRepository.instance.list();
});
