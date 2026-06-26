/// ALOQA — providers for the meeting-manage screen (detail + 5s live polling).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'meeting_models.dart';

/// The signed-in user's meetings (Dashboard list, refreshable).
final meetingsProvider = FutureProvider.autoDispose<List<Meeting>>((ref) async {
  return MeetingRepository.instance.list();
});

final meetingDetailProvider =
    FutureProvider.autoDispose.family<Meeting, String>((ref, id) async {
  return MeetingRepository.instance.get(id);
});

/// Polls participants + waiting room every 5s (mirrors web setInterval).
final meetingLiveProvider =
    StreamProvider.autoDispose.family<MeetingLive, String>((ref, id) async* {
  final repo = MeetingRepository.instance;

  Future<MeetingLive> fetch() async {
    try {
      final results =
          await Future.wait([repo.participants(id), repo.waiting(id)]);
      return MeetingLive(
        participants: results[0] as List<ParticipantHistory>,
        waiting: results[1] as List<WaitingPerson>,
      );
    } catch (_) {
      return const MeetingLive();
    }
  }

  yield await fetch();
  await for (final _ in Stream<void>.periodic(const Duration(seconds: 5))) {
    yield await fetch();
  }
});
