/// ALOQA — public webinar registration (web /w/:code parity).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';

@immutable
class WebinarInfo {
  const WebinarInfo({
    required this.id,
    required this.code,
    required this.title,
    this.scheduledAt,
    this.status,
    this.hostName,
    this.registered = 0,
  });

  final String id;
  final String code;
  final String title;
  final DateTime? scheduledAt;
  final String? status;
  final String? hostName;
  final int registered;

  factory WebinarInfo.fromJson(Map<String, dynamic> j) {
    final host = j['host'] is Map ? j['host'] as Map : null;
    return WebinarInfo(
      id: (j['id'] ?? '').toString(),
      code: (j['code'] ?? '').toString(),
      title: (j['title'] ?? 'Webinar').toString(),
      scheduledAt: j['scheduled_at'] != null
          ? DateTime.tryParse(j['scheduled_at'].toString())
          : null,
      status: j['status']?.toString(),
      hostName: host?['name']?.toString(),
      registered: j['registered'] is num ? (j['registered'] as num).toInt() : 0,
    );
  }
}

class WebinarRepository {
  WebinarRepository(this._dio);
  final Dio _dio;

  static final WebinarRepository instance =
      WebinarRepository(DioClient.instance.dio);

  Future<WebinarInfo> get(String code) async {
    final res = await _dio.get<Map<String, dynamic>>('/webinars/$code');
    final body = res.data ?? <String, dynamic>{};
    final w = body['webinar'] is Map ? body['webinar'] as Map : body;
    return WebinarInfo.fromJson(Map<String, dynamic>.from(w));
  }

  Future<void> register(String code,
      {required String name, String? email, String? phone}) async {
    await _dio.post<dynamic>('/webinars/$code/register', data: {
      'name': name.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    });
  }
}

final webinarProvider =
    FutureProvider.autoDispose.family<WebinarInfo, String>((ref, code) async {
  return WebinarRepository.instance.get(code);
});
