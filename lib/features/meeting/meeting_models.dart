/// ALOQA — meeting domain models + repository (TZ §9 meetings/rtc).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/dio_client.dart';

@immutable
class Meeting {
  const Meeting({
    required this.id,
    required this.title,
    this.code,
    this.scheduledAt,
    this.status,
    this.pmi,
  });

  final String id;
  final String title;
  final String? code; // qisqa konferensiya ID (ulashish uchun)
  final DateTime? scheduledAt;
  final String? status;
  final String? pmi;

  factory Meeting.fromJson(Map<String, dynamic> j) => Meeting(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] as String?) ?? 'Untitled',
        code: j['code']?.toString(),
        scheduledAt: j['scheduled_at'] != null
            ? DateTime.tryParse(j['scheduled_at'].toString())
            : null,
        status: j['status'] as String?,
        pmi: j['pmi']?.toString(),
      );
}

/// Result of joining a meeting — carries the LiveKit token + room (TZ §3.2).
@immutable
class JoinInfo {
  const JoinInfo({
    required this.roomName,
    required this.livekitToken,
    this.livekitUrl,
    this.isHost = false,
    this.canPublish = true,
  });

  final String roomName;
  final String livekitToken;
  final String? livekitUrl;
  final bool isHost;
  final bool canPublish; // webinar attendee → false (faqat ko'rish)

  factory JoinInfo.fromJson(Map<String, dynamic> j) => JoinInfo(
        roomName: (j['room'] ?? j['room_name'] ?? '').toString(),
        livekitToken: (j['token'] ?? j['livekit_token'] ?? '').toString(),
        livekitUrl: (j['livekit_url'] ?? j['url']) as String?,
        isHost: j['is_host'] == true,
        canPublish: j['can_publish'] == null ? true : j['can_publish'] == true,
      );
}

class MeetingRepository {
  MeetingRepository(this._dio);
  final Dio _dio;

  static final MeetingRepository instance =
      MeetingRepository(DioClient.instance.dio);

  Future<List<Meeting>> list() async {
    final res = await _dio.get<dynamic>('/meetings');
    final data = res.data;
    final items = data is Map ? (data['meetings'] ?? data['data']) : data;
    if (items is List) {
      return items
          .whereType<Map<String, dynamic>>()
          .map(Meeting.fromJson)
          .toList();
    }
    return [];
  }

  /// GET /meetings/{id|code} → konferensiyani topish (qo'shilishdan oldin tekshirish).
  Future<Meeting> get(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/meetings/$id');
    final body = res.data ?? <String, dynamic>{};
    final m = body['meeting'] is Map ? body['meeting'] as Map : body;
    return Meeting.fromJson(Map<String, dynamic>.from(m));
  }

  Future<Meeting> create({required String title, DateTime? scheduledAt}) async {
    final res = await _dio.post<Map<String, dynamic>>('/meetings', data: {
      'title': title,
      if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
      'type': scheduledAt == null ? 'instant' : 'scheduled',
    });
    // Backend javobi { meeting: {...} } ko'rinishida
    final body = res.data ?? <String, dynamic>{};
    final m = body['meeting'] is Map ? body['meeting'] as Map : body;
    return Meeting.fromJson(Map<String, dynamic>.from(m));
  }

  /// POST /meetings/{id}/join → join info (TZ §9). Then POST /rtc/token if the
  /// join payload didn't already include a LiveKit token.
  Future<JoinInfo> join(String meetingId, {String? guestName}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/meetings/$meetingId/join',
      data: {if (guestName != null) 'guest_name': guestName},
    );
    var info = JoinInfo.fromJson(res.data ?? {});
    if (info.livekitToken.isEmpty) {
      final tok = await _dio.post<Map<String, dynamic>>('/rtc/token', data: {
        'meeting_id': meetingId,
      });
      info = JoinInfo.fromJson({
        'room': tok.data?['room'] ?? meetingId,
        'token': tok.data?['token'] ?? '',
        'livekit_url': tok.data?['livekit_url'],
      });
    }
    return info;
  }
}
