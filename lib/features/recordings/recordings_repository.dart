/// ALOQA — cloud recordings (web /app/recordings parity).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';

@immutable
class RecordingRow {
  const RecordingRow({
    required this.id,
    required this.meetingId,
    this.type,
    this.duration,
    this.status,
    this.url,
    this.createdAt,
  });

  final String id;
  final String meetingId;
  final String? type;
  final int? duration; // seconds
  final String? status;
  final String? url; // playable/downloadable mp4 (null = not ready)
  final DateTime? createdAt;

  factory RecordingRow.fromJson(Map<String, dynamic> j) => RecordingRow(
        id: (j['id'] ?? '').toString(),
        meetingId: (j['meeting_id'] ?? '').toString(),
        type: j['type']?.toString(),
        duration: j['duration'] is num ? (j['duration'] as num).toInt() : null,
        status: j['status']?.toString(),
        url: (j['url'] != null && j['url'].toString().isNotEmpty)
            ? j['url'].toString()
            : null,
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'].toString())
            : null,
      );
}

class RecordingsRepository {
  RecordingsRepository(this._dio);
  final Dio _dio;

  static final RecordingsRepository instance =
      RecordingsRepository(DioClient.instance.dio);

  Future<List<RecordingRow>> list() async {
    final res = await _dio.get<Map<String, dynamic>>('/recordings');
    final items = res.data?['recordings'];
    if (items is List) {
      return items
          .whereType<Map<String, dynamic>>()
          .map(RecordingRow.fromJson)
          .toList();
    }
    return [];
  }
}

final recordingsProvider =
    FutureProvider.autoDispose<List<RecordingRow>>((ref) async {
  return RecordingsRepository.instance.list();
});
