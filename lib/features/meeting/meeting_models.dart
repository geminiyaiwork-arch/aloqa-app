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
    this.room,
    this.scheduledAt,
    this.autoEndAt,
    this.status,
    this.pmi,
    this.type,
    this.participantsCount,
    this.settings,
  });

  final String id;
  final String title;
  final String? code; // qisqa konferensiya ID (ulashish uchun)
  final String? room;
  final DateTime? scheduledAt;
  final DateTime? autoEndAt;
  final String? status;
  final String? pmi;
  final String? type;
  final int? participantsCount;
  final Map<String, dynamic>? settings;

  bool get waitingRoom => settings?['waiting_room'] == true;

  factory Meeting.fromJson(Map<String, dynamic> j) => Meeting(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] as String?) ?? 'Untitled',
        code: j['code']?.toString(),
        room: j['room']?.toString(),
        scheduledAt: j['scheduled_at'] != null
            ? DateTime.tryParse(j['scheduled_at'].toString())
            : null,
        autoEndAt: j['auto_end_at'] != null
            ? DateTime.tryParse(j['auto_end_at'].toString())
            : null,
        status: j['status'] as String?,
        pmi: j['pmi']?.toString(),
        type: j['type'] as String?,
        participantsCount: j['participants_count'] is num
            ? (j['participants_count'] as num).toInt()
            : null,
        settings: j['settings'] is Map
            ? Map<String, dynamic>.from(j['settings'] as Map)
            : null,
      );
}

/// One row of a meeting's participant history (manage screen).
@immutable
class ParticipantHistory {
  const ParticipantHistory({
    required this.id,
    required this.name,
    this.avatar,
    this.isGuest = false,
    this.role = '',
    this.usedCam = false,
    this.usedMic = false,
    this.joinedAt,
    this.leftAt,
    this.active = false,
    this.durationMin = 0,
  });

  final int id;
  final String name;
  final String? avatar;
  final bool isGuest;
  final String role;
  final bool usedCam;
  final bool usedMic;
  final DateTime? joinedAt;
  final DateTime? leftAt;
  final bool active;
  final int durationMin;

  factory ParticipantHistory.fromJson(Map<String, dynamic> j) =>
      ParticipantHistory(
        id: j['id'] is num ? (j['id'] as num).toInt() : 0,
        name: (j['name'] ?? 'Foydalanuvchi').toString(),
        avatar: j['avatar']?.toString(),
        isGuest: j['is_guest'] == true,
        role: (j['role'] ?? '').toString(),
        usedCam: j['used_cam'] == true,
        usedMic: j['used_mic'] == true,
        joinedAt: j['joined_at'] != null
            ? DateTime.tryParse(j['joined_at'].toString())
            : null,
        leftAt: j['left_at'] != null
            ? DateTime.tryParse(j['left_at'].toString())
            : null,
        active: j['active'] == true,
        durationMin:
            j['duration_min'] is num ? (j['duration_min'] as num).toInt() : 0,
      );
}

/// Someone in the waiting room.
@immutable
class WaitingPerson {
  const WaitingPerson({required this.id, required this.name, this.avatar});

  final int id;
  final String name;
  final String? avatar;

  factory WaitingPerson.fromJson(Map<String, dynamic> j) => WaitingPerson(
        id: j['id'] is num ? (j['id'] as num).toInt() : 0,
        name: (j['name'] ?? 'Foydalanuvchi').toString(),
        avatar: j['avatar']?.toString(),
      );
}

/// Transcript state for a meeting (manage screen).
@immutable
class TranscriptInfo {
  const TranscriptInfo({
    required this.allowed,
    this.id,
    this.status = '',
    this.language,
    this.hasText = false,
    this.text,
  });

  final bool allowed;
  final int? id;
  final String status;
  final String? language;
  final bool hasText;
  final String? text;

  factory TranscriptInfo.fromJson(Map<String, dynamic> j) {
    final t = j['transcript'] is Map ? j['transcript'] as Map : null;
    return TranscriptInfo(
      allowed: j['allowed'] == true,
      id: t != null && t['id'] is num ? (t['id'] as num).toInt() : null,
      status: (t?['status'] ?? '').toString(),
      language: t?['language']?.toString(),
      hasText: t?['has_text'] == true,
      text: t?['text']?.toString(),
    );
  }
}

/// Live snapshot of a meeting's participants + waiting room (5s poll).
@immutable
class MeetingLive {
  const MeetingLive({this.participants = const [], this.waiting = const []});
  final List<ParticipantHistory> participants;
  final List<WaitingPerson> waiting;
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
    this.hostIdentity,
  });

  final String roomName;
  final String livekitToken;
  final String? livekitUrl;
  final bool isHost;
  final bool canPublish; // webinar attendee → false (faqat ko'rish)
  final String? hostIdentity; // serverdan: haqiqiy host identity (boshqaruv xabarlari faqat shundan)

  factory JoinInfo.fromJson(Map<String, dynamic> j) => JoinInfo(
        roomName: (j['room'] ?? j['room_name'] ?? '').toString(),
        livekitToken: (j['token'] ?? j['livekit_token'] ?? '').toString(),
        livekitUrl: (j['livekit_url'] ?? j['url']) as String?,
        isHost: j['is_host'] == true,
        canPublish: j['can_publish'] == null ? true : j['can_publish'] == true,
        hostIdentity: j['host_identity'] as String?,
      );
}

/// One row in an attendance report — an employee matched (or not) to a joined
/// participant. `verified` is false when only a guest-name matched (#10).
@immutable
class AttendanceItem {
  const AttendanceItem({
    required this.name,
    this.position,
    this.photo,
    this.present = false,
    this.minutes = 0,
    this.verified = false,
  });

  final String name;
  final String? position;
  final String? photo;
  final bool present;
  final int minutes;
  final bool verified;

  factory AttendanceItem.fromJson(Map<String, dynamic> j) => AttendanceItem(
        name: (j['name'] ?? '').toString(),
        position: j['position']?.toString(),
        photo: j['photo']?.toString(),
        present: j['present'] == true,
        minutes: j['minutes'] is num ? (j['minutes'] as num).toInt() : 0,
        verified: j['verified'] == true,
      );
}

/// Conference attendance report (host counts roster employees against joiners).
@immutable
class AttendanceReport {
  const AttendanceReport({
    this.total = 0,
    this.present = 0,
    this.absent = 0,
    this.percent = 0,
    this.items = const [],
    this.generatedByName,
  });

  final int total;
  final int present;
  final int absent;
  final double percent;
  final List<AttendanceItem> items;
  final String? generatedByName;

  factory AttendanceReport.fromJson(Map<String, dynamic> j) => AttendanceReport(
        total: j['total'] is num ? (j['total'] as num).toInt() : 0,
        present: j['present'] is num ? (j['present'] as num).toInt() : 0,
        absent: j['absent'] is num ? (j['absent'] as num).toInt() : 0,
        percent: j['percent'] is num ? (j['percent'] as num).toDouble() : 0,
        items: j['items'] is List
            ? (j['items'] as List)
                .whereType<Map<String, dynamic>>()
                .map(AttendanceItem.fromJson)
                .toList()
            : const [],
        generatedByName: j['generated_by_name']?.toString(),
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

  /// POST /meetings {type:'instant'} → instant meeting.
  Future<Meeting> createInstant({String? title}) async {
    final t = (title ?? '').trim();
    return create(title: t.isNotEmpty ? t : 'Yangi uchrashuv');
  }

  /// POST /meetings {type:'scheduled', scheduled_at, auto_end_at, recurrence?}.
  Future<Meeting> createScheduled({
    required String title,
    DateTime? when,
    int? durationMinutes,
    String? recurrence,
  }) async {
    final t = title.trim();
    final res = await _dio.post<Map<String, dynamic>>('/meetings', data: {
      'title': t.isNotEmpty ? t : 'Rejalashtirilgan uchrashuv',
      'type': 'scheduled',
      'scheduled_at': when?.toUtc().toIso8601String(),
      'auto_end_at': (when != null && (durationMinutes ?? 0) > 0)
          ? when.add(Duration(minutes: durationMinutes!)).toUtc().toIso8601String()
          : null,
      if (recurrence != null && recurrence.isNotEmpty) 'recurrence': recurrence,
    });
    final body = res.data ?? <String, dynamic>{};
    final m = body['meeting'] is Map ? body['meeting'] as Map : body;
    return Meeting.fromJson(Map<String, dynamic>.from(m));
  }

  /// PATCH /meetings/{id} — rename / settings / status / auto_end_at.
  Future<Meeting> patch(String id, Map<String, dynamic> body) async {
    final res =
        await _dio.patch<Map<String, dynamic>>('/meetings/$id', data: body);
    final data = res.data ?? <String, dynamic>{};
    final m = data['meeting'] is Map ? data['meeting'] as Map : data;
    return Meeting.fromJson(Map<String, dynamic>.from(m));
  }

  Future<void> endMeeting(String id) async {
    await _dio.post<dynamic>('/meetings/$id/end');
  }

  /// Bulutli yozib olishni boshlash. Server xona faol bo'lsa egress qaytaradi.
  /// `true` = yozish boshlandi.
  Future<bool> startRecording(String id) async {
    final res =
        await _dio.post<Map<String, dynamic>>('/meetings/$id/recording/start');
    final rec = res.data?['recording'];
    return rec is Map && rec['status'] == 'recording';
  }

  Future<void> stopRecording(String id) async {
    await _dio.post<dynamic>('/meetings/$id/recording/stop');
  }

  Future<void> delete(String id) async {
    await _dio.delete<dynamic>('/meetings/$id');
  }

  Future<List<ParticipantHistory>> participants(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/meetings/$id/participants');
    final list = res.data?['participants'];
    if (list is List) {
      return list
          .whereType<Map<String, dynamic>>()
          .map(ParticipantHistory.fromJson)
          .toList();
    }
    return [];
  }

  Future<List<WaitingPerson>> waiting(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/meetings/$id/waiting');
    final list = res.data?['waiting'];
    if (list is List) {
      return list
          .whereType<Map<String, dynamic>>()
          .map(WaitingPerson.fromJson)
          .toList();
    }
    return [];
  }

  Future<void> admit(String id,
      {required int participantId, required String decision}) async {
    await _dio.post<dynamic>('/meetings/$id/admit',
        data: {'participant_id': participantId, 'decision': decision});
  }

  /// Host-only: count attendance for this meeting (matches roster employees
  /// against joiners) and persist a report. Returns the generated report.
  Future<AttendanceReport> attendance(String id) async {
    final res =
        await _dio.post<Map<String, dynamic>>('/meetings/$id/attendance');
    final rep = res.data?['report'];
    return AttendanceReport.fromJson(
        rep is Map<String, dynamic> ? rep : <String, dynamic>{});
  }

  Future<void> kick(String id, {required int participantId}) async {
    await _dio.post<dynamic>('/meetings/$id/kick',
        data: {'participant_id': participantId});
  }

  Future<TranscriptInfo> transcript(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/meetings/$id/transcript');
    return TranscriptInfo.fromJson(res.data ?? {});
  }

  Future<void> transcribe(String id) async {
    await _dio.post<dynamic>('/meetings/$id/transcribe');
  }

  /// GET /meetings/{id}/transcript/download?format=txt|srt → raw bytes.
  Future<List<int>> transcriptDownload(String id, {required String format}) async {
    final res = await _dio.get<List<int>>(
      '/meetings/$id/transcript/download',
      queryParameters: {'format': format},
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? const [];
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
