/// ALOQA — public announcements banner (web AppLayout parity).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/dio_client.dart';

@immutable
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    this.body,
    this.level = 'info',
  });

  final int id;
  final String title;
  final String? body;
  final String level; // info | success | warning

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id'] is num ? (j['id'] as num).toInt() : 0,
        title: (j['title'] ?? '').toString(),
        body: j['body']?.toString(),
        level: (j['level'] ?? 'info').toString(),
      );
}

class AnnouncementsRepository {
  AnnouncementsRepository(this._dio);
  final Dio _dio;

  static final AnnouncementsRepository instance =
      AnnouncementsRepository(DioClient.instance.dio);

  Future<List<Announcement>> list() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/announcements');
      final items = res.data?['announcements'];
      if (items is List) {
        return items
            .whereType<Map<String, dynamic>>()
            .map(Announcement.fromJson)
            .toList();
      }
    } catch (_) {
      // banner is best-effort — hide on error
    }
    return [];
  }
}

final announcementsProvider =
    FutureProvider.autoDispose<List<Announcement>>((ref) async {
  return AnnouncementsRepository.instance.list();
});
