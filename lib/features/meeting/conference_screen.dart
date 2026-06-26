/// ALOQA — conference room (M11). LiveKit SFU: video grid + control bar +
/// chat / reactions / raise-hand / whiteboard / Q&A / poll over the LiveKit
/// data channel. Data wire-format matches the web client (web/src/lib/livekit.ts
/// + Conference.tsx) so EVERYTHING interoperates across web ↔ mobile:
///   chat:     { kind:chat, id,sender,body,ts }
///   reaction: { kind:reaction, emoji }
///   hand:     { kind:hand, raised }
///   wb:       { kind:wb, op:stroke|clear, x0,y0,x1,y1, color:'#hex', width }
///   qa:       { kind:qa, op:ask|vote|answered, id, sender,text,ts }
///   poll:     { kind:poll, op:open|vote|close, id, question, options[], choice }
///
/// livekit_client 2.2.6 (flutter_webrtc 0.11.7) — pinned for Flutter 3.22.2.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../contacts/contacts_service.dart';
import 'meeting_models.dart';

class _ChatMsg {
  _ChatMsg({required this.sender, required this.body, required this.ts, required this.self});
  final String sender;
  final String body;
  final int ts;
  final bool self;
}

class _FloatReaction {
  _FloatReaction(this.id, this.emoji);
  final String id;
  final String emoji;
}

class _WbSeg {
  _WbSeg(this.x0, this.y0, this.x1, this.y1, this.color, this.width);
  final double x0, y0, x1, y1;
  final int color;
  final double width;
}

class _Question {
  _Question(this.id, this.sender, this.text, this.ts);
  final String id;
  final String sender;
  final String text;
  final int ts;
  int votes = 0;
  bool answered = false;
}

class _Poll {
  _Poll(this.id, this.question, this.options, this.counts);
  final String id;
  final String question;
  final List<String> options;
  final List<int> counts;
  bool closed = false;
  int? myVote;
}

class ConferenceScreen extends ConsumerStatefulWidget {
  const ConferenceScreen({
    super.key,
    required this.meetingId,
    required this.joinInfo,
    this.startCam = true,
    this.startMic = true,
  });

  final String meetingId;
  final JoinInfo joinInfo;
  final bool startCam;
  final bool startMic;

  @override
  ConsumerState<ConferenceScreen> createState() => _ConferenceScreenState();
}

/// Per-participant render info for the video tiles.
class _PInfo {
  _PInfo({
    required this.id,
    required this.name,
    this.video,
    required this.muted,
    required this.speaking,
    required this.hand,
    required this.local,
  });
  final String id;
  final String name;
  final VideoTrack? video;
  final bool muted;
  final bool speaking;
  final bool hand;
  final bool local;
}

class _ConferenceScreenState extends ConsumerState<ConferenceScreen> {
  /// Native bridge to the Android mediaProjection foreground service.
  static const MethodChannel _shareCh = MethodChannel('uz.aloqa.app/screenshare');

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _connecting = true;
  bool _micOn = true;
  bool _camOn = true;
  bool _sharing = false;
  bool _handRaised = false;
  String? _error;

  // 'grid' (Setka) | 'speaker' (So'zlovchi)
  String _layout = 'grid';
  bool _navigatingOut = false;
  bool _goneHome = false;
  final Set<String> _handsUp = <String>{};
  DateTime? _connectedAt;
  Timer? _ticker;
  final PageController _pageCtrl = PageController();
  int _page = 0;

  bool get _viewOnly => !widget.joinInfo.canPublish;
  bool get _isHost => widget.joinInfo.isHost;

  final List<_ChatMsg> _messages = [];
  final List<_FloatReaction> _reactions = [];
  int _unread = 0;

  // whiteboard
  bool _boardOpen = false;
  final List<_WbSeg> _wbSegs = [];
  Color _wbColor = const Color(0xFF111827);
  bool _erasing = false;
  Offset? _wbLast;

  // Q&A
  final List<_Question> _questions = [];
  int _qnaUnread = 0;

  // poll
  _Poll? _poll;

  // cloud recording (faqat host)
  bool _recording = false;
  bool _recordingBusy = false;

  static const _emojis = ['👍', '❤️', '😂', '👏', '🎉', '😮'];

  @override
  void initState() {
    super.initState();
    _micOn = widget.startMic && !_viewOnly;
    _camOn = widget.startCam && !_viewOnly;
    _connect();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _connect() async {
    final token = widget.joinInfo.livekitToken;
    final url = widget.joinInfo.livekitUrl ?? AppConfig.livekitUrl;
    if (token.isEmpty) {
      setState(() {
        _connecting = false;
        _error = 'LiveKit token mavjud emas';
      });
      return;
    }
    try {
      final room = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );
      _listener = room.createListener();
      _bindEvents();
      await room.connect(url, token);
      _room = room;
      if (!_viewOnly) {
        await room.localParticipant?.setMicrophoneEnabled(_micOn);
        await room.localParticipant?.setCameraEnabled(_camOn);
      }
      _connectedAt = DateTime.now();
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = e.toString();
        });
      }
    }
  }

  void _bindEvents() {
    _listener
      ?..on<TrackSubscribedEvent>((_) => _refresh())
      ..on<TrackUnsubscribedEvent>((_) => _refresh())
      ..on<ParticipantConnectedEvent>((_) => _refresh())
      ..on<ParticipantDisconnectedEvent>((_) => _refresh())
      ..on<LocalTrackPublishedEvent>((_) => _refresh())
      ..on<LocalTrackUnpublishedEvent>((_) => _refresh())
      ..on<DataReceivedEvent>(_onData)
      ..on<RoomDisconnectedEvent>((_) {
        // My own leave already navigates; an UNEXPECTED disconnect means the host
        // (any platform) ended the meeting / the server closed the room → send
        // everyone back to the dashboard.
        if (_navigatingOut) return;
        _goHome('Konferensiya yakunlandi');
      });
  }

  // --- data channel --------------------------------------------------------

  void _onData(DataReceivedEvent event) {
    try {
      final m = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
      switch (m['kind']) {
        case 'chat':
          setState(() {
            _messages.add(_ChatMsg(
              sender: (m['sender'] ?? '?').toString(),
              body: (m['body'] ?? '').toString(),
              ts: (m['ts'] is int) ? m['ts'] as int : DateTime.now().millisecondsSinceEpoch,
              self: false,
            ));
            _unread++;
          });
          break;
        case 'reaction':
          _pushReaction((m['emoji'] ?? '👍').toString());
          break;
        case 'hand':
          final sender = m['sender']?.toString();
          if (sender != null) {
            setState(() {
              if (m['raised'] == true) {
                _handsUp.add(sender);
              } else {
                _handsUp.remove(sender);
              }
            });
          }
          break;
        case 'wb':
          _onWbData(m);
          break;
        case 'qa':
          _onQaData(m);
          break;
        case 'poll':
          _onPollData(m);
          break;
        case 'end':
          // Host yakunladi — hammada yopiladi.
          _goHome('Konferensiya yakunlandi');
          break;
      }
    } catch (_) {
      /* malformed — ignore */
    }
  }

  Future<void> _publish(Map<String, dynamic> payload) async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    try {
      await lp.publishData(utf8.encode(jsonEncode(payload)), reliable: true);
    } catch (_) {}
  }

  String get _myName => _room?.localParticipant?.name.isNotEmpty == true
      ? _room!.localParticipant!.name
      : (_room?.localParticipant?.identity ?? 'Men');

  // --- chat ---
  Future<void> _sendChat(String body) async {
    if (body.trim().isEmpty) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    setState(() => _messages.add(_ChatMsg(sender: _myName, body: body.trim(), ts: ts, self: true)));
    await _publish({'kind': 'chat', 'id': ts.toString(), 'sender': _myName, 'body': body.trim(), 'ts': ts});
  }

  // --- reactions ---
  Future<void> _react(String emoji) async {
    _pushReaction(emoji);
    await _publish({'kind': 'reaction', 'emoji': emoji});
  }

  void _pushReaction(String emoji) {
    final r = _FloatReaction('${DateTime.now().microsecondsSinceEpoch}', emoji);
    setState(() => _reactions.add(r));
    Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _reactions.removeWhere((x) => x.id == r.id));
    });
  }

  Future<void> _toggleHand() async {
    final me = _room?.localParticipant?.identity;
    setState(() {
      _handRaised = !_handRaised;
      if (me != null) {
        if (_handRaised) {
          _handsUp.add(me);
        } else {
          _handsUp.remove(me);
        }
      }
    });
    await _publish({'kind': 'hand', 'raised': _handRaised, 'sender': me});
  }

  // --- whiteboard ---
  int _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16) ?? 0xFF111827;
    return v;
  }

  String _colorToHex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  void _onWbData(Map<String, dynamic> m) {
    if (m['op'] == 'clear') {
      setState(() => _wbSegs.clear());
    } else if (m['op'] == 'stroke') {
      setState(() => _wbSegs.add(_WbSeg(
            (m['x0'] as num).toDouble(),
            (m['y0'] as num).toDouble(),
            (m['x1'] as num).toDouble(),
            (m['y1'] as num).toDouble(),
            _hexToColor((m['color'] ?? '#111827').toString()),
            (m['width'] as num?)?.toDouble() ?? 3,
          )));
    }
  }

  void _wbStroke(Offset a, Offset b, Size size) {
    final col = _erasing ? const Color(0xFFFFFFFF) : _wbColor;
    final w = _erasing ? 24.0 : 3.0;
    final seg = _WbSeg(a.dx / size.width, a.dy / size.height, b.dx / size.width, b.dy / size.height, col.value, w);
    setState(() => _wbSegs.add(seg));
    _publish({
      'kind': 'wb', 'op': 'stroke',
      'x0': seg.x0, 'y0': seg.y0, 'x1': seg.x1, 'y1': seg.y1,
      'color': _colorToHex(col), 'width': w,
    });
  }

  void _wbClear() {
    setState(() => _wbSegs.clear());
    _publish({'kind': 'wb', 'op': 'clear'});
  }

  // --- Q&A ---
  void _onQaData(Map<String, dynamic> m) {
    final id = (m['id'] ?? '').toString();
    setState(() {
      if (m['op'] == 'ask') {
        if (!_questions.any((q) => q.id == id)) {
          _questions.add(_Question(id, (m['sender'] ?? '?').toString(), (m['text'] ?? '').toString(),
              (m['ts'] is int) ? m['ts'] as int : DateTime.now().millisecondsSinceEpoch));
        }
        _qnaUnread++;
      } else if (m['op'] == 'vote') {
        for (final q in _questions) {
          if (q.id == id) q.votes++;
        }
      } else if (m['op'] == 'answered') {
        for (final q in _questions) {
          if (q.id == id) q.answered = true;
        }
      }
    });
  }

  void _askQuestion(String text) {
    if (text.trim().isEmpty) return;
    final id = '${DateTime.now().millisecondsSinceEpoch}';
    setState(() => _questions.add(_Question(id, _myName, text.trim(), DateTime.now().millisecondsSinceEpoch)));
    _publish({'kind': 'qa', 'op': 'ask', 'id': id, 'sender': _myName, 'text': text.trim(), 'ts': DateTime.now().millisecondsSinceEpoch});
  }

  void _voteQuestion(String id) {
    setState(() {
      for (final q in _questions) {
        if (q.id == id) q.votes++;
      }
    });
    _publish({'kind': 'qa', 'op': 'vote', 'id': id});
  }

  void _answerQuestion(String id) {
    setState(() {
      for (final q in _questions) {
        if (q.id == id) q.answered = true;
      }
    });
    _publish({'kind': 'qa', 'op': 'answered', 'id': id});
  }

  // --- poll ---
  void _onPollData(Map<String, dynamic> m) {
    setState(() {
      if (m['op'] == 'open') {
        final opts = (m['options'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        _poll = _Poll((m['id'] ?? '').toString(), (m['question'] ?? '').toString(), opts,
            List<int>.filled(opts.length, 0));
      } else if (m['op'] == 'vote' && _poll != null && _poll!.id == (m['id'] ?? '').toString()) {
        final c = (m['choice'] as num?)?.toInt() ?? -1;
        if (c >= 0 && c < _poll!.counts.length) _poll!.counts[c]++;
      } else if (m['op'] == 'close' && _poll != null && _poll!.id == (m['id'] ?? '').toString()) {
        _poll!.closed = true;
      }
    });
  }

  void _createPoll(String question, List<String> options) {
    final id = '${DateTime.now().millisecondsSinceEpoch}';
    setState(() => _poll = _Poll(id, question, options, List<int>.filled(options.length, 0)));
    _publish({'kind': 'poll', 'op': 'open', 'id': id, 'question': question, 'options': options});
  }

  void _votePoll(int choice) {
    final p = _poll;
    if (p == null) return;
    setState(() {
      p.myVote = choice;
      p.counts[choice]++;
    });
    _publish({'kind': 'poll', 'op': 'vote', 'id': p.id, 'choice': choice});
  }

  void _closePoll() {
    final p = _poll;
    if (p == null) return;
    setState(() => p.closed = true);
    _publish({'kind': 'poll', 'op': 'close', 'id': p.id});
  }

  // --- media controls ------------------------------------------------------

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    await _room?.localParticipant?.setMicrophoneEnabled(_micOn);
    _refresh();
  }

  Future<void> _toggleCam() async {
    _camOn = !_camOn;
    await _room?.localParticipant?.setCameraEnabled(_camOn);
    _refresh();
  }

  /// Cross-platform screen share. Android needs a mediaProjection foreground
  /// service RUNNING before capture; desktop needs an explicit source id; iOS is
  /// gated off until a Broadcast Upload Extension exists.
  Future<void> _toggleShare() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;

    if (!_sharing && lkPlatformIs(PlatformType.iOS)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ekran ulashish iOS\'da hozircha mavjud emas')));
      }
      return;
    }

    try {
      if (!_sharing) {
        if (lkPlatformIsDesktop()) {
          final sources =
              await rtc.desktopCapturer.getSources(types: [rtc.SourceType.Screen]);
          if (sources.isEmpty) return;
          final track = await LocalVideoTrack.createScreenShareTrack(
            ScreenShareCaptureOptions(
                sourceId: sources.first.id, maxFrameRate: 15.0),
          );
          await lp.publishVideoTrack(track);
        } else if (lkPlatformIs(PlatformType.android)) {
          // 1) consent dialog  2) start FG service  3) publish (mandatory order)
          final granted = await rtc.Helper.requestCapturePermission();
          if (!granted) return;
          await _shareCh.invokeMethod<void>('start');
          await lp.setScreenShareEnabled(true);
        } else {
          await lp.setScreenShareEnabled(true, captureScreenAudio: true);
        }
        _sharing = true;
      } else {
        await lp.setScreenShareEnabled(false);
        if (lkPlatformIs(PlatformType.android)) {
          await _shareCh.invokeMethod<void>('stop');
        }
        _sharing = false;
      }
    } catch (e) {
      if (lkPlatformIs(PlatformType.android)) {
        try {
          await _shareCh.invokeMethod<void>('stop');
        } catch (_) {}
      }
      _sharing = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ekran ulashish xatosi: $e')));
      }
    }
    _refresh();
  }

  Future<void> _leave() async {
    _navigatingOut = true;
    try {
      await _room?.disconnect();
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  /// Red "end call" button. The host is offered a choice (leave vs end for all);
  /// everyone else just leaves.
  void _onEndPressed() {
    if (!_isHost) {
      _leave();
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.slate200,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 12),
              ListTile(
                onTap: () {
                  Navigator.pop(ctx);
                  _leave();
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.logout, color: AppColors.slate700),
                title: const Text('Chiqib ketish',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Faqat siz chiqasiz, konferensiya davom etadi'),
              ),
              ListTile(
                onTap: () {
                  Navigator.pop(ctx);
                  _endForAll();
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.call_end, color: AppColors.danger),
                title: const Text('Hamma uchun yakunlash',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
                subtitle: const Text('Konferensiya barcha ishtirokchilarda yopiladi'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Host ends the meeting for everyone: broadcast the signal + close the room.
  Future<void> _endForAll() async {
    _navigatingOut = true;
    await _publish({'kind': 'end'});
    try {
      await MeetingRepository.instance.endMeeting(widget.meetingId);
    } catch (_) {}
    await _goHome('Konferensiya yakunlandi');
  }

  /// Disconnect and send the user back to the dashboard (idempotent).
  Future<void> _goHome(String msg) async {
    if (_goneHome) return;
    _goneHome = true;
    _navigatingOut = true;
    try {
      await _room?.disconnect();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    context.go('/home');
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  int get _participantCount => _room == null ? 0 : _room!.remoteParticipants.length + 1;

  @override
  void dispose() {
    _ticker?.cancel();
    _pageCtrl.dispose();
    _listener?.dispose();
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate50,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            if (!_connecting && _error == null) _statusRow(),
            Expanded(
              child: Stack(
                children: [
                  _body(),
                  if (_boardOpen) Positioned.fill(child: _whiteboard()),
                  if (_poll != null) Positioned(right: 8, top: 8, child: _pollCard()),
                  _reactionsOverlay(),
                ],
              ),
            ),
            _controlBar(),
          ],
        ),
      ),
    );
  }

  // ── Top bar (mockup: collapse · shield · ALOQA+ID+copy · count · more) ──
  Widget _topBar() {
    final code = widget.joinInfo.roomName.isNotEmpty
        ? widget.joinInfo.roomName
        : '—';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.slate200)),
      ),
      child: Row(
        children: [
          _iconBtn(Icons.keyboard_arrow_down, _leave),
          const SizedBox(width: 8),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.verified_user, color: AppColors.brand600, size: 20),
          ),
          Expanded(
            child: Column(
              children: [
                const Text('ALOQA',
                    style: TextStyle(
                        color: AppColors.slate900,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        letterSpacing: 0.5)),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('ID nusxalandi'),
                        duration: Duration(seconds: 1)));
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(code,
                          style: const TextStyle(
                              color: AppColors.slate500, fontSize: 13)),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy, size: 13, color: AppColors.slate400),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_recording) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record,
                      size: 11, color: Color(0xFFDC2626)),
                  SizedBox(width: 4),
                  Text('REC',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFDC2626))),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          _countPill(),
          const SizedBox(width: 8),
          _iconBtn(Icons.more_vert, _moreSheet),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.slate200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 20, color: AppColors.slate700),
        ),
      ),
    );
  }

  Widget _countPill() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _openParticipants,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.slate200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 18, color: AppColors.slate700),
            const SizedBox(width: 4),
            Text('$_participantCount',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate900)),
          ],
        ),
      ),
    );
  }

  // ── Status row (rec timer · connection · participant count) ──
  Widget _statusRow() {
    final q = _connLabel();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: AppColors.danger, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(_elapsed(),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate900)),
                const SizedBox(width: 8),
                Container(width: 1, height: 14, color: AppColors.slate200),
                const SizedBox(width: 8),
                Icon(Icons.signal_cellular_alt, size: 15, color: q.$2),
                const SizedBox(width: 4),
                Text(q.$1,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: q.$2)),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_outline,
                    size: 16, color: AppColors.slate700),
                const SizedBox(width: 6),
                Text('$_participantCount ishtirokchi',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _elapsed() {
    final c = _connectedAt;
    if (c == null) return '00:00';
    final d = DateTime.now().difference(c);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  (String, Color) _connLabel() {
    final q = _room?.localParticipant?.connectionQuality.name ?? 'unknown';
    switch (q) {
      case 'excellent':
      case 'good':
        return ('Yaxshi', AppColors.brand600);
      case 'poor':
        return ('O\'rta', const Color(0xFFD97706));
      default:
        return ('Past', AppColors.slate400);
    }
  }

  Widget _reactionsOverlay() {
    if (_reactions.isEmpty) return const SizedBox.shrink();
    return Positioned(
      bottom: 12,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Wrap(
            spacing: 4,
            children: _reactions.map((r) => Text(r.emoji, style: const TextStyle(fontSize: 34))).toList(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_connecting) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.brand600));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.slate400, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.slate500)),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.brand600),
                onPressed: () {
                  setState(() {
                    _connecting = true;
                    _error = null;
                  });
                  _connect();
                },
                child: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      );
    }

    final infos = _pInfos();
    if (infos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, color: AppColors.slate300, size: 48),
            SizedBox(height: 12),
            Text('Ishtirokchilar kutilmoqda…',
                style: TextStyle(color: AppColors.slate400)),
          ],
        ),
      );
    }
    return _layout == 'speaker' ? _speakerView(infos) : _gridView(infos);
  }

  /// Best-effort phone of a participant: identity if it looks like a number, or
  /// a `phone` field inside its metadata JSON (set by the backend). Used to look
  /// the person up in the local contacts.
  String? _phoneOf(Participant p) {
    if (RegExp(r'^\+?\d{7,}$').hasMatch(p.identity)) return p.identity;
    final meta = p.metadata;
    if (meta != null && meta.isNotEmpty) {
      try {
        final m = jsonDecode(meta);
        if (m is Map && m['phone'] != null) return m['phone'].toString();
      } catch (_) {}
    }
    return null;
  }

  List<_PInfo> _pInfos() {
    final room = _room;
    final out = <_PInfo>[];
    if (room == null) return out;
    void add(Participant p, bool local) {
      VideoTrack? video;
      for (final pub in p.videoTrackPublications) {
        if (pub.source == TrackSource.camera &&
            (local || pub.subscribed) &&
            !pub.muted) {
          final t = pub.track;
          if (t is VideoTrack) video = t;
        }
      }
      final audio = p.audioTrackPublications;
      final muted =
          local ? !_micOn : (audio.isEmpty || audio.every((a) => a.muted));
      final registered = p.name.isNotEmpty ? p.name : (local ? 'Men' : p.identity);
      // For remote people, prefer the name saved in MY contacts (matched by phone).
      final name = local
          ? registered
          : ContactsStore.instance.resolveName(_phoneOf(p), registered);
      out.add(_PInfo(
        id: p.identity,
        name: name,
        video: video,
        muted: muted,
        speaking: p.isSpeaking,
        hand: _handsUp.contains(p.identity),
        local: local,
      ));
    }

    final local = room.localParticipant;
    if (local != null) add(local, true);
    for (final p in room.remoteParticipants.values) {
      add(p, false);
    }
    return out;
  }

  Widget _gridView(List<_PInfo> infos) {
    if (infos.length <= 9) {
      final cols = infos.length == 1
          ? 1
          : infos.length <= 4
              ? 2
              : 3;
      return GridView.count(
        crossAxisCount: cols,
        padding: const EdgeInsets.all(10),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: cols == 1 ? 0.92 : 0.82,
        children: [for (final p in infos) _tile(p)],
      );
    }
    const perPage = 9;
    final pageCount = (infos.length / perPage).ceil();
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: pageCount,
            itemBuilder: (_, page) {
              final slice = infos.skip(page * perPage).take(perPage).toList();
              return GridView.count(
                crossAxisCount: 3,
                padding: const EdgeInsets.all(10),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
                children: [for (final p in slice) _tile(p)],
              );
            },
          ),
        ),
        _dots(pageCount),
      ],
    );
  }

  Widget _speakerView(List<_PInfo> infos) {
    final main = infos.firstWhere((p) => p.speaking, orElse: () => infos.first);
    final others = infos.where((p) => p.id != main.id).toList();
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _tile(main, big: true),
          ),
        ),
        if (others.isNotEmpty)
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) =>
                  AspectRatio(aspectRatio: 0.82, child: _tile(others[i])),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _dots(int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _page ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == _page ? AppColors.brand600 : AppColors.slate300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(_PInfo p, {bool big = false}) {
    final hasVideo = p.video != null;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: p.speaking ? AppColors.brand500 : AppColors.slate200,
          width: p.speaking ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasVideo)
            VideoTrackRenderer(
              p.video!,
              fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            _avatarFallback(p.name, big: big),
          if (p.hand)
            Positioned(top: 8, right: 8, child: _cornerChip('✋'))
          else if (p.speaking)
            Positioned(
              top: 8,
              right: 8,
              child: _cornerIcon(Icons.graphic_eq, AppColors.brand600),
            ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: _namePill(p.name, p.muted),
          ),
        ],
      ),
    );
  }

  Widget _cornerChip(String emoji) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
        ],
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 15)),
    );
  }

  Widget _cornerIcon(IconData icon, Color color) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: color),
    );
  }

  Widget _namePill(String name, bool muted) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(muted ? Icons.mic_off : Icons.mic,
                size: 14, color: muted ? AppColors.danger : AppColors.brand600),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(String name, {bool big = false}) {
    final color = _avatarColor(name);
    final d = big ? 96.0 : 64.0;
    return Container(
      color: AppColors.slate100,
      alignment: Alignment.center,
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          _initials(name),
          style: TextStyle(
              color: Colors.white,
              fontSize: big ? 34 : 22,
              fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.elementAt(1)[0]).toUpperCase();
  }

  Color _avatarColor(String key) {
    const palette = [
      Color(0xFF10B981), // emerald
      Color(0xFF8B5CF6), // violet
      Color(0xFF3B82F6), // blue
      Color(0xFFF59E0B), // amber
      Color(0xFFEC4899), // pink
      Color(0xFF14B8A6), // teal
      Color(0xFFEF4444), // red
      Color(0xFF6366F1), // indigo
    ];
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }

  // --- whiteboard widget ---
  Widget _whiteboard() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF111318),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                for (final c in const [
                  Color(0xFF111827), Color(0xFFEF4444), Color(0xFF3B82F6), Color(0xFF22C55E), Color(0xFFEAB308),
                ])
                  GestureDetector(
                    onTap: () => setState(() {
                      _wbColor = c;
                      _erasing = false;
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: (!_erasing && _wbColor == c) ? Colors.white : Colors.white24, width: 2),
                      ),
                    ),
                  ),
                IconButton(
                  icon: Icon(Icons.cleaning_services,
                      color: _erasing ? const Color(0xFF3F51B5) : Colors.white60, size: 20),
                  onPressed: () => setState(() => _erasing = !_erasing),
                ),
                const Spacer(),
                TextButton(onPressed: _wbClear, child: const Text('Tozalash', style: TextStyle(color: Colors.redAccent))),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onPanStart: (d) => _wbLast = d.localPosition,
                  onPanUpdate: (d) {
                    final p = d.localPosition;
                    if (_wbLast != null) _wbStroke(_wbLast!, p, size);
                    _wbLast = p;
                  },
                  onPanEnd: (_) => _wbLast = null,
                  child: CustomPaint(painter: _WbPainter(_wbSegs), size: Size.infinite),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- poll card ---
  Widget _pollCard() {
    final p = _poll!;
    final total = p.counts.fold<int>(0, (a, b) => a + b);
    final showResults = p.closed || p.myVote != null || _isHost;
    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF111318), borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.question, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (var i = 0; i < p.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: showResults
                  ? _pollResultRow(p.options[i], p.counts[i], total, p.myVote == i)
                  : SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _votePoll(i),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                        child: Align(alignment: Alignment.centerLeft, child: Text(p.options[i])),
                      ),
                    ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$total ovoz', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              if (_isHost && !p.closed)
                GestureDetector(
                  onTap: _closePoll,
                  child: const Text('Yopish', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pollResultRow(String label, int count, int total, bool mine) {
    final pct = total == 0 ? 0 : (count / total * 100).round();
    return Stack(
      children: [
        Container(
          height: 30,
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
        ),
        FractionallySizedBox(
          widthFactor: total == 0 ? 0 : count / total,
          child: Container(
            height: 30,
            decoration: BoxDecoration(color: const Color(0x663F51B5), borderRadius: BorderRadius.circular(8)),
          ),
        ),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Expanded(child: Text('${mine ? '✓ ' : ''}$label', style: const TextStyle(color: Colors.white, fontSize: 12))),
              Text('$pct%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  // --- control bar (light, labeled) + red end-call button ---
  Widget _controlBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.slate200)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (!_viewOnly) ...[
                _ctlBtn(_micOn ? Icons.mic : Icons.mic_off, 'Mikrofon',
                    _toggleMic, danger: !_micOn),
                _ctlBtn(_camOn ? Icons.videocam : Icons.videocam_off, 'Kamera',
                    _toggleCam, danger: !_camOn),
                _ctlBtn(Icons.screen_share_outlined, 'Ekran ulashish',
                    _toggleShare, active: _sharing),
              ],
              _ctlBtn(Icons.people_outline, 'Ishtirokchilar', _openParticipants,
                  badge: _participantCount),
              _ctlBtn(Icons.chat_bubble_outline, 'Chat', _openChat, badge: _unread),
              _ctlBtn(Icons.emoji_emotions_outlined, 'Reaksiyalar', _showReactions),
              _ctlBtn(Icons.more_horiz, 'Yana', _moreSheet, badge: _qnaUnread),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: _onEndPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.call_end),
              label: const Text('Qo\'ng\'iroqni tugatish',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctlBtn(IconData icon, String label, VoidCallback onTap,
      {bool active = false, bool danger = false, int badge = 0}) {
    final color = danger
        ? AppColors.danger
        : (active ? AppColors.brand600 : AppColors.slate700);
    final bg = danger
        ? AppColors.danger.withOpacity(0.1)
        : (active ? AppColors.brand50 : AppColors.slate100);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: bg, borderRadius: BorderRadius.circular(13)),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        constraints:
                            const BoxConstraints(minWidth: 18, minHeight: 18),
                        decoration: const BoxDecoration(
                            color: AppColors.brand600, shape: BoxShape.circle),
                        child: Text('$badge',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.slate600, height: 1.1)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleRecording() async {
    if (_recordingBusy) return;
    final wasRecording = _recording;
    setState(() {
      _recordingBusy = true;
      _recording = !wasRecording;
    });
    try {
      if (wasRecording) {
        await MeetingRepository.instance.stopRecording(widget.meetingId);
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('Yozish to\'xtatildi')));
        }
      } else {
        final ok =
            await MeetingRepository.instance.startRecording(widget.meetingId);
        if (!mounted) return;
        if (!ok) {
          setState(() => _recording = false);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
                content: Text('Yozib bo\'lmadi (xona faolmi?)')));
        } else {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
                const SnackBar(content: Text('Yozib olish boshlandi')));
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _recording = wasRecording);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Xatolik yuz berdi')));
      }
    } finally {
      if (mounted) setState(() => _recordingBusy = false);
    }
  }

  void _moreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.slate200,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _segBtn('Setka', Icons.grid_view_outlined,
                        _layout == 'grid', () {
                      setState(() => _layout = 'grid');
                      Navigator.pop(ctx);
                    }),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _segBtn('So\'zlovchi', Icons.person_outline,
                        _layout == 'speaker', () {
                      setState(() => _layout = 'speaker');
                      Navigator.pop(ctx);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _sheetTile(
                  _handRaised ? Icons.front_hand : Icons.back_hand_outlined,
                  _handRaised ? 'Qo\'lni tushirish' : 'Qo\'l ko\'tarish', () {
                Navigator.pop(ctx);
                _toggleHand();
              }, active: _handRaised),
              if (!_viewOnly)
                _sheetTile(Icons.edit_outlined,
                    _boardOpen ? 'Doskani yopish' : 'Doska', () {
                  Navigator.pop(ctx);
                  setState(() => _boardOpen = !_boardOpen);
                }, active: _boardOpen),
              _sheetTile(Icons.help_outline, 'Savol-javob', () {
                Navigator.pop(ctx);
                _openQna();
              }),
              if (_isHost)
                _sheetTile(Icons.bar_chart, 'So\'rovnoma', () {
                  Navigator.pop(ctx);
                  _openPollComposer();
                }),
              if (_isHost)
                _sheetTile(
                  _recording
                      ? Icons.stop_circle_outlined
                      : Icons.fiber_manual_record,
                  _recording ? 'Yozishni to\'xtatish' : 'Yozib olish (bulut)',
                  () {
                    Navigator.pop(ctx);
                    _toggleRecording();
                  },
                  active: _recording,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segBtn(String label, IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: active ? AppColors.brand600 : AppColors.slate100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: active ? Colors.white : AppColors.slate600),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppColors.slate700)),
          ],
        ),
      ),
    );
  }

  Widget _sheetTile(IconData icon, String label, VoidCallback onTap,
      {bool active = false}) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading:
          Icon(icon, color: active ? AppColors.brand600 : AppColors.slate700),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w500,
              color: active ? AppColors.brand700 : AppColors.slate900)),
    );
  }

  void _openParticipants() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final infos = _pInfos();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.slate200,
                          borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 12),
                Text('Ishtirokchilar (${infos.length})',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.slate900)),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in infos)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _avatarColor(p.name),
                            child: Text(_initials(p.name),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                          ),
                          title: Text('${p.name}${p.local ? ' (siz)' : ''}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (p.hand) const Text('✋'),
                              const SizedBox(width: 8),
                              Icon(p.muted ? Icons.mic_off : Icons.mic,
                                  size: 18,
                                  color: p.muted
                                      ? AppColors.danger
                                      : AppColors.brand600),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showReactions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111318),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 8,
            children: _emojis
                .map((e) => GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _react(e);
                      },
                      child: Text(e, style: const TextStyle(fontSize: 40)),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  void _openChat() {
    setState(() => _unread = 0);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111318),
      builder: (_) => _ChatSheet(messages: _messages, onSend: _sendChat),
    );
  }

  void _openQna() {
    setState(() => _qnaUnread = 0);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111318),
      builder: (_) => _QnaSheet(
        questions: _questions,
        isHost: _isHost,
        onAsk: _askQuestion,
        onVote: _voteQuestion,
        onAnswered: _answerQuestion,
      ),
    );
  }

  void _openPollComposer() {
    final qCtrl = TextEditingController();
    final optCtrls = [TextEditingController(), TextEditingController(), TextEditingController(), TextEditingController()];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: const Text('So\'rovnoma', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: qCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Savol', hintStyle: TextStyle(color: Colors.white38))),
              for (var i = 0; i < optCtrls.length; i++)
                TextField(controller: optCtrls[i], style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Variant ${i + 1}', hintStyle: const TextStyle(color: Colors.white38))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Bekor')),
          FilledButton(
            onPressed: () {
              final opts = optCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
              if (qCtrl.text.trim().isEmpty || opts.length < 2) return;
              Navigator.pop(ctx);
              _createPoll(qCtrl.text.trim(), opts);
            },
            child: const Text('Yaratish'),
          ),
        ],
      ),
    );
  }
}

class _WbPainter extends CustomPainter {
  _WbPainter(this.segs);
  final List<_WbSeg> segs;

  @override
  void paint(Canvas c, Size s) {
    for (final seg in segs) {
      final p = Paint()
        ..color = Color(seg.color)
        ..strokeWidth = seg.width
        ..strokeCap = StrokeCap.round;
      c.drawLine(Offset(seg.x0 * s.width, seg.y0 * s.height), Offset(seg.x1 * s.width, seg.y1 * s.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WbPainter old) => true;
}

class _ChatSheet extends StatefulWidget {
  const _ChatSheet({required this.messages, required this.onSend});
  final List<_ChatMsg> messages;
  final Future<void> Function(String) onSend;

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Suhbat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            Expanded(
              child: widget.messages.isEmpty
                  ? const Center(child: Text('Hali xabar yo\'q', style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: widget.messages.length,
                      itemBuilder: (_, i) {
                        final m = widget.messages[widget.messages.length - 1 - i];
                        return Align(
                          alignment: m.self ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                            decoration: BoxDecoration(
                              color: m.self ? const Color(0xFF3F51B5) : Colors.white10,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!m.self)
                                  Text(m.sender, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                Text(m.body, style: const TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Xabar yozing...',
                        hintStyle: TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send, color: Color(0xFF3F51B5)), onPressed: _send),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _send() {
    final v = _ctrl.text;
    if (v.trim().isEmpty) return;
    _ctrl.clear();
    widget.onSend(v);
    setState(() {});
  }
}

class _QnaSheet extends StatefulWidget {
  const _QnaSheet({
    required this.questions,
    required this.isHost,
    required this.onAsk,
    required this.onVote,
    required this.onAnswered,
  });
  final List<_Question> questions;
  final bool isHost;
  final void Function(String) onAsk;
  final void Function(String) onVote;
  final void Function(String) onAnswered;

  @override
  State<_QnaSheet> createState() => _QnaSheetState();
}

class _QnaSheetState extends State<_QnaSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final sorted = [...widget.questions]..sort((a, b) {
        if (a.answered != b.answered) return a.answered ? 1 : -1;
        return b.votes - a.votes;
      });
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Q&A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            Expanded(
              child: sorted.isEmpty
                  ? const Center(child: Text('Hali savol yo\'q', style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: sorted.length,
                      itemBuilder: (_, i) {
                        final q = sorted[i];
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: q.answered ? const Color(0x3322C55E) : Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => setState(() => widget.onVote(q.id)),
                                child: Column(
                                  children: [
                                    const Icon(Icons.arrow_drop_up, color: Colors.white70),
                                    Text('${q.votes}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(q.sender, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                    Text(q.text, style: const TextStyle(color: Colors.white)),
                                    if (widget.isHost && !q.answered)
                                      TextButton(
                                        onPressed: () => setState(() => widget.onAnswered(q.id)),
                                        child: const Text('✓ Javob berildi', style: TextStyle(color: Color(0xFF22C55E), fontSize: 12)),
                                      ),
                                    if (q.answered)
                                      const Text('✓ Javob berilgan', style: TextStyle(color: Color(0xFF22C55E), fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Savol bering...',
                        hintStyle: TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _ask(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send, color: Color(0xFF3F51B5)), onPressed: _ask),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _ask() {
    final v = _ctrl.text;
    if (v.trim().isEmpty) return;
    _ctrl.clear();
    widget.onAsk(v);
    setState(() {});
  }
}
