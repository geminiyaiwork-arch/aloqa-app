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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/i18n_service.dart';
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
  _FloatReaction(this.id, this.emoji, this.effect);
  final String id;
  final String emoji;
  final int effect; // 0..5 — random animatsiya turi
}

/// (C6) Reaksiya markazга uchib, random effekt bilan portlaydi:
/// 0 aylanib, 1 sochilib, 2 yonib, 3 kattalashib, 4 romb, 5 shamol.
class _ReactionBurst extends StatefulWidget {
  const _ReactionBurst({super.key, required this.emoji, required this.effect});
  final String emoji;
  final int effect;

  @override
  State<_ReactionBurst> createState() => _ReactionBurstState();
}

class _ReactionBurstState extends State<_ReactionBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _fadeOut(double t, [double start = 0.7]) =>
      t < start ? 1.0 : (1 - (t - start) / (1 - start)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height / 2;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_c.value);
        switch (widget.effect) {
          case 0:
            return _spin(t, cx, cy);
          case 1:
            return _scatter(t, cx, cy);
          case 2:
            return _burn(t, cx, cy);
          case 3:
            return _zoom(t, cx, cy);
          case 4:
            return _rhombus(t, cx, cy);
          default:
            return _wind(t, cx, cy);
        }
      },
    );
  }

  Widget _emoji(double size, [List<Shadow>? shadows]) => Text(widget.emoji,
      style: TextStyle(fontSize: size, shadows: shadows));

  // 0 — aylanib chiqib ketish
  Widget _spin(double t, double cx, double cy) {
    final y = cy + (1 - t) * cy * 0.85;
    final scale = 0.5 + t * 1.4;
    return Positioned(
      left: cx - 30,
      top: y - 30,
      child: Opacity(
        opacity: _fadeOut(t, 0.75),
        child: Transform.rotate(
          angle: t * 4 * math.pi,
          child: Transform.scale(scale: scale, child: _emoji(46)),
        ),
      ),
    );
  }

  // 1 — markazдан sochilib ketish (7 ta nusxa)
  Widget _scatter(double t, double cx, double cy) {
    const n = 7;
    final op = (1 - t).clamp(0.0, 1.0);
    return Stack(
      children: List.generate(n, (i) {
        final ang = (i / n) * 2 * math.pi;
        final dist = t * 170;
        return Positioned(
          left: cx + math.cos(ang) * dist - 16,
          top: cy + math.sin(ang) * dist - 16,
          child: Opacity(
            opacity: op,
            child: Transform.scale(scale: 0.7 + t * 0.7, child: _emoji(30)),
          ),
        );
      }),
    );
  }

  // 2 — yonib ketish (sariq nur + kattalashib o'chish)
  Widget _burn(double t, double cx, double cy) {
    final scale = 0.6 + t * 1.9;
    return Positioned(
      left: cx - 40,
      top: cy - 40 - t * 70,
      child: Opacity(
        opacity: (1 - t * t).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          child: _emoji(50, [
            Shadow(
                color: Colors.orange.withOpacity(0.85 * (1 - t)),
                blurRadius: 22 + t * 34),
            Shadow(
                color: Colors.red.withOpacity(0.6 * (1 - t)),
                blurRadius: 10 + t * 20),
          ]),
        ),
      ),
    );
  }

  // 3 — markazда kattalashib (zoom) — pulse
  Widget _zoom(double t, double cx, double cy) {
    final scale = 0.3 + t * 2.1;
    return Positioned(
      left: cx - 40,
      top: cy - 40,
      child: Opacity(
        opacity: _fadeOut(t, 0.65),
        child: Transform.scale(scale: scale, child: _emoji(50)),
      ),
    );
  }

  // 4 — romb shaklida aylanib chiqish
  Widget _rhombus(double t, double cx, double cy) {
    return Positioned(
      left: cx - 30,
      top: cy - 30 - t * 60,
      child: Opacity(
        opacity: _fadeOut(t, 0.7),
        child: Transform.rotate(
          angle: math.pi / 4 + t * math.pi,
          child: Transform.scale(scale: 0.7 + t, child: _emoji(42)),
        ),
      ),
    );
  }

  // 5 — shamolда uchib (yon tomonga tebranib)
  Widget _wind(double t, double cx, double cy) {
    final y = cy + (1 - t) * cy * 0.75;
    final x = cx + math.sin(t * 6) * 70;
    return Positioned(
      left: x - 24,
      top: y - 24,
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: math.sin(t * 8) * 0.4,
          child: Transform.scale(scale: 0.8 + t * 0.8, child: _emoji(40)),
        ),
      ),
    );
  }
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

  // host mikrofon nazorati
  bool _forceMuted = false; // host meni majburiy o'chirdimi (yoqa olmayman)
  bool _allMuted = false;   // host: hammani o'chirdimmi (tugma holati)

  // reaksiya (C7): host yashirsa — reaksiyalar faqat yuboruvchiда ko'rinadi
  bool _reactLocked = false;
  final _rnd = math.Random();

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
        _error = ref.tt('mobile.conf.tokenMissing');
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
        _goHome(ref.tt('mobile.conf.ended'));
      });
  }

  // --- data channel --------------------------------------------------------

  void _onData(DataReceivedEvent event) {
    try {
      final m = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
      final kind = m['kind'];
      // Boshqaruv xabarlari (mute/end/reactlock) FAQAT haqiqiy hostdan qabul qilinadi.
      // LiveKit `participant.identity` = server imzolagan identity (spoof qilib bo'lmaydi) →
      // oddiy ishtirokchi hammani majburan o'chira / chiqara / reaksiyani qulflay olmaydi.
      const privileged = {'mute', 'end', 'reactlock'};
      if (privileged.contains(kind) &&
          event.participant?.identity != widget.joinInfo.hostIdentity) {
        return;
      }
      switch (kind) {
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
          final remoji = (m['emoji'] ?? '👍').toString();
          _pushReaction(remoji);
          // (C8) kim yuborgani chatga
          final rsender = m['sender']?.toString();
          if (rsender != null && rsender.isNotEmpty) {
            _logReactionToChat(rsender, remoji);
          }
          break;
        case 'reactlock':
          setState(() => _reactLocked = m['locked'] == true);
          _toast(_reactLocked
              ? ref.tt('mobile.conf.reactLockedToast')
              : ref.tt('mobile.conf.reactUnlockedToast'));
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
        case 'mute':
          // Host majburiy mikrofon nazorati.
          final target = m['target']?.toString();
          final me = _room?.localParticipant?.identity;
          final muted = m['muted'] == true;
          if (target == 'all' || target == me) {
            setState(() => _forceMuted = muted);
            if (muted) {
              if (_micOn) {
                _micOn = false;
                _room?.localParticipant?.setMicrophoneEnabled(false);
              }
              _toast(ref.tt('mobile.conf.muteByAdmin'));
            } else {
              _toast(ref.tt('mobile.conf.unmuteByAdmin'));
            }
            if (mounted) setState(() {});
          }
          break;
        case 'end':
          // Host yakunladi — hammada yopiladi.
          _goHome(ref.tt('mobile.conf.ended'));
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
      : (_room?.localParticipant?.identity ?? ref.tt('mobile.conf.myNameFallback'));

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
    // (C8) kim yuborganini chatga yozamiz
    _logReactionToChat(_myName, emoji, self: true);
    // (C7) host yashirgan bo'lsa — boshqaларга yubormaymiz (faqat o'zимда)
    if (!_reactLocked) {
      await _publish({'kind': 'reaction', 'emoji': emoji, 'sender': _myName});
    }
  }

  void _pushReaction(String emoji) {
    final r = _FloatReaction(
      '${DateTime.now().microsecondsSinceEpoch}_${_rnd.nextInt(9999)}',
      emoji,
      _rnd.nextInt(6), // random effekt
    );
    setState(() => _reactions.add(r));
    Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _reactions.removeWhere((x) => x.id == r.id));
    });
  }

  // (C8) reaksiyani chatga yozish (kim yubordi)
  void _logReactionToChat(String sender, String emoji, {bool self = false}) {
    setState(() {
      _messages.add(_ChatMsg(
        sender: sender,
        body: emoji,
        ts: DateTime.now().millisecondsSinceEpoch,
        self: self,
      ));
    });
  }

  // (C7) host: reaksiyalarni yashirish/yoqish
  Future<void> _toggleReactLock() async {
    setState(() => _reactLocked = !_reactLocked);
    await _publish({'kind': 'reactlock', 'locked': _reactLocked});
    _toast(_reactLocked
        ? ref.tt('mobile.conf.reactLockedSelfOnly')
        : ref.tt('mobile.conf.reactEnabled'));
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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _toggleMic() async {
    // (B4) Host majburiy o'chirgan bo'lsa — o'zi yoqa olmaydi.
    if (_forceMuted && !_micOn) {
      _toast(ref.tt('mobile.conf.micBlockedToast'));
      return;
    }
    _micOn = !_micOn;
    await _room?.localParticipant?.setMicrophoneEnabled(_micOn);
    _refresh();
  }

  /// (B3/B5) Host: hammaning mikrofonини o'chirish/yoqish.
  Future<void> _muteAll(bool mute) async {
    setState(() => _allMuted = mute);
    await _publish({'kind': 'mute', 'target': 'all', 'muted': mute});
    // Host o'zi ham (agar o'zini ham qo'shsa) — lekin host o'zini boshqaradi.
    _toast(mute ? ref.tt('mobile.conf.allMuted') : ref.tt('mobile.conf.allUnmuted'));
  }

  /// (B3/B5) Host: bitta ishtirokchini o'chirish.
  Future<void> _muteParticipant(String identity, bool mute) async {
    await _publish({'kind': 'mute', 'target': identity, 'muted': mute});
    _toast(mute ? ref.tt('mobile.conf.micMuted') : ref.tt('mobile.conf.micAllowed'));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ref.tt('mobile.conf.shareIosUnavailable'))));
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
            SnackBar(content: Text(ref.tt('mobile.conf.shareError', {'error': e.toString()}))));
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
                title: Text(ref.tt('mobile.conf.leaveTitle'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(ref.tt('mobile.conf.leaveSub')),
              ),
              ListTile(
                onTap: () {
                  Navigator.pop(ctx);
                  _endForAll();
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.call_end, color: AppColors.danger),
                title: Text(ref.tt('mobile.conf.endForAll'),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
                subtitle: Text(ref.tt('mobile.conf.endForAllSub')),
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
    await _goHome(ref.tt('mobile.conf.ended'));
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
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ref.tt('mobile.conf.idCopied')),
                        duration: const Duration(seconds: 1)));
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
                Text(ref.t('mobile.conf.participantsCount', {'count': '$_participantCount'}),
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
        return (ref.t('mobile.conn.good'), AppColors.brand600);
      case 'poor':
        return (ref.t('mobile.conn.medium'), const Color(0xFFD97706));
      default:
        return (ref.t('mobile.conn.poor'), AppColors.slate400);
    }
  }

  Widget _reactionsOverlay() {
    if (_reactions.isEmpty) return const SizedBox.shrink();
    // (C6) Har reaksiya markazга uchib, random effekt bilan portlaydi.
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: _reactions
              .map((r) => _ReactionBurst(
                    key: ValueKey(r.id),
                    emoji: r.emoji,
                    effect: r.effect,
                  ))
              .toList(),
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
                child: Text(ref.t('action.retry')),
              ),
            ],
          ),
        ),
      );
    }

    final infos = _pInfos();
    if (infos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, color: AppColors.slate300, size: 48),
            const SizedBox(height: 12),
            Text(ref.t('mobile.conf.waitingParticipants'),
                style: const TextStyle(color: AppColors.slate400)),
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
      final registered = p.name.isNotEmpty ? p.name : (local ? ref.tt('mobile.conf.myNameFallback') : p.identity);
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
                TextButton(onPressed: _wbClear, child: Text(ref.t('mobile.conf.wbClear'), style: const TextStyle(color: Colors.redAccent))),
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
              Text(ref.t('mobile.conf.pollVotes', {'count': '$total'}), style: const TextStyle(color: Colors.white38, fontSize: 11)),
              if (_isHost && !p.closed)
                GestureDetector(
                  onTap: _closePoll,
                  child: Text(ref.t('mobile.conf.pollClose'), style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
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
                _ctlBtn(
                    _forceMuted
                        ? Icons.mic_off
                        : (_micOn ? Icons.mic : Icons.mic_off),
                    _forceMuted ? ref.t('mobile.conf.ctlMicBlocked') : ref.t('mobile.conf.ctlMic'),
                    _toggleMic,
                    danger: !_micOn || _forceMuted),
                _ctlBtn(_camOn ? Icons.videocam : Icons.videocam_off, ref.t('mobile.conf.ctlCamera'),
                    _toggleCam, danger: !_camOn),
                _ctlBtn(Icons.screen_share_outlined, ref.t('mobile.conf.ctlShare'),
                    _toggleShare, active: _sharing),
              ],
              _ctlBtn(Icons.people_outline, ref.t('mobile.conf.ctlParticipants'), _openParticipants,
                  badge: _participantCount),
              _ctlBtn(Icons.chat_bubble_outline, ref.t('mobile.conf.ctlChat'), _openChat, badge: _unread),
              _ctlBtn(Icons.emoji_emotions_outlined, ref.t('mobile.conf.ctlReactions'), _showReactions),
              _ctlBtn(Icons.more_horiz, ref.t('mobile.conf.ctlMore'), _moreSheet, badge: _qnaUnread),
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
              label: Text(ref.t('mobile.conf.endCall'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
            ..showSnackBar(SnackBar(content: Text(ref.tt('mobile.conf.recordingStopped'))));
        }
      } else {
        final ok =
            await MeetingRepository.instance.startRecording(widget.meetingId);
        if (!mounted) return;
        if (!ok) {
          setState(() => _recording = false);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
                content: Text(ref.tt('mobile.conf.recordingFailed'))));
        } else {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
                SnackBar(content: Text(ref.tt('mobile.conf.recordingStarted'))));
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _recording = wasRecording);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(ref.tt('common.error'))));
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
                    child: _segBtn(ref.tt('mobile.conf.layoutGrid'), Icons.grid_view_outlined,
                        _layout == 'grid', () {
                      setState(() => _layout = 'grid');
                      Navigator.pop(ctx);
                    }),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _segBtn(ref.tt('mobile.conf.layoutSpeaker'), Icons.person_outline,
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
                  _handRaised ? ref.tt('mobile.conf.lowerHand') : ref.tt('mobile.conf.raiseHand'), () {
                Navigator.pop(ctx);
                _toggleHand();
              }, active: _handRaised),
              if (!_viewOnly)
                _sheetTile(Icons.edit_outlined,
                    _boardOpen ? ref.tt('mobile.conf.boardClose') : ref.tt('mobile.conf.board'), () {
                  Navigator.pop(ctx);
                  setState(() => _boardOpen = !_boardOpen);
                }, active: _boardOpen),
              _sheetTile(Icons.help_outline, ref.tt('mobile.conf.qna'), () {
                Navigator.pop(ctx);
                _openQna();
              }),
              if (_isHost)
                _sheetTile(Icons.bar_chart, ref.tt('mobile.conf.poll'), () {
                  Navigator.pop(ctx);
                  _openPollComposer();
                }),
              if (_isHost)
                _sheetTile(
                  _recording
                      ? Icons.stop_circle_outlined
                      : Icons.fiber_manual_record,
                  _recording ? ref.tt('mobile.conf.recordStop') : ref.tt('mobile.conf.recordCloud'),
                  () {
                    Navigator.pop(ctx);
                    _toggleRecording();
                  },
                  active: _recording,
                ),
              if (_isHost)
                _sheetTile(
                  _allMuted ? Icons.mic : Icons.mic_off,
                  _allMuted
                      ? ref.tt('mobile.conf.unmuteAll')
                      : ref.tt('mobile.conf.muteAll'),
                  () {
                    Navigator.pop(ctx);
                    _muteAll(!_allMuted);
                  },
                  active: _allMuted,
                ),
              if (_isHost)
                _sheetTile(
                  _reactLocked
                      ? Icons.emoji_emotions
                      : Icons.emoji_emotions_outlined,
                  _reactLocked
                      ? ref.tt('mobile.conf.reactEnable')
                      : ref.tt('mobile.conf.reactHide'),
                  () {
                    Navigator.pop(ctx);
                    _toggleReactLock();
                  },
                  active: _reactLocked,
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
                Text(ref.tt('mobile.conf.participantsTitle', {'count': '${infos.length}'}),
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
                          title: Text(
                              p.local
                                  ? ref.tt('mobile.conf.youSuffix', {'name': p.name})
                                  : p.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (p.hand) const Text('✋'),
                              // (B3) Host bitta ishtirokchini o'chiradi/yoqadi
                              if (_isHost && !p.local)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 36, minHeight: 36),
                                  icon: Icon(
                                      p.muted
                                          ? Icons.mic_off_outlined
                                          : Icons.mic_none,
                                      size: 20,
                                      color: AppColors.slate500),
                                  tooltip: p.muted
                                      ? ref.tt('mobile.conf.tooltipUnmute')
                                      : ref.tt('mobile.conf.tooltipMute'),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _muteParticipant(p.id, !p.muted);
                                  },
                                ),
                              const SizedBox(width: 4),
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
        title: Text(ref.tt('mobile.conf.pollComposerTitle'), style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: qCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: ref.tt('mobile.conf.pollQuestionHint'), hintStyle: const TextStyle(color: Colors.white38))),
              for (var i = 0; i < optCtrls.length; i++)
                TextField(controller: optCtrls[i], style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: ref.tt('mobile.conf.pollOptionHint', {'n': '${i + 1}'}), hintStyle: const TextStyle(color: Colors.white38))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ref.tt('mobile.action.cancelShort'))),
          FilledButton(
            onPressed: () {
              final opts = optCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
              if (qCtrl.text.trim().isEmpty || opts.length < 2) return;
              Navigator.pop(ctx);
              _createPoll(qCtrl.text.trim(), opts);
            },
            child: Text(ref.tt('mobile.action.createShort')),
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

// ── chat yordamchilari (premium bubble) ──
bool _chatIsEmoji(String s) {
  final t = s.trim();
  if (t.isEmpty || t.runes.length > 3) return false;
  return t.runes.every((r) => r > 0x2000); // emoji/symbol = yuqori kod-nuqta
}

String _chatInitials(String name) {
  final p = name.trim().split(RegExp(r'\s+'));
  final a = p.isNotEmpty && p[0].isNotEmpty ? p[0][0] : '?';
  final b = p.length > 1 && p[1].isNotEmpty ? p[1][0] : '';
  return (a + b).toUpperCase();
}

Color _chatColor(String name) {
  const colors = [
    Color(0xFF6366F1),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
  ];
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return colors[h % colors.length];
}

String _chatTime(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _ChatSheet extends ConsumerStatefulWidget {
  const _ChatSheet({required this.messages, required this.onSend});
  final List<_ChatMsg> messages;
  final Future<void> Function(String) onSend;

  @override
  ConsumerState<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends ConsumerState<_ChatSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final h = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: h * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Row(children: [
                const Icon(Icons.forum_rounded, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text(ref.t('mobile.conf.chatTitle'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ]),
            ),
            Expanded(
              child: widget.messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('💬', style: TextStyle(fontSize: 36)),
                          const SizedBox(height: 8),
                          Text(ref.t('mobile.conf.chatEmpty'),
                              style: const TextStyle(color: Colors.white38)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                      itemCount: widget.messages.length,
                      itemBuilder: (_, i) {
                        final m =
                            widget.messages[widget.messages.length - 1 - i];
                        return _bubble(m, context);
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white12))),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(color: Colors.white),
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: ref.t('mobile.conf.chatHint'),
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                          color: AppColors.brand600, shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(_ChatMsg m, BuildContext context) {
    final emojiOnly = _chatIsEmoji(m.body);
    final maxW = MediaQuery.of(context).size.width * 0.72;
    final Widget content = emojiOnly
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: Text(m.body, style: const TextStyle(fontSize: 30)))
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            constraints: BoxConstraints(maxWidth: maxW),
            decoration: BoxDecoration(
              color: m.self ? AppColors.brand600 : Colors.white12,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(m.self ? 16 : 4),
                bottomRight: Radius.circular(m.self ? 4 : 16),
              ),
            ),
            child: Text(m.body,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            m.self ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!m.self) ...[
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: _chatColor(m.sender), shape: BoxShape.circle),
              child: Text(_chatInitials(m.sender),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  m.self ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!m.self)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(m.sender,
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                content,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  child: Text(_chatTime(m.ts),
                      style:
                          const TextStyle(color: Colors.white30, fontSize: 9.5)),
                ),
              ],
            ),
          ),
        ],
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

class _QnaSheet extends ConsumerStatefulWidget {
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
  ConsumerState<_QnaSheet> createState() => _QnaSheetState();
}

class _QnaSheetState extends ConsumerState<_QnaSheet> {
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
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(ref.t('mobile.conf.qnaTitle'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            Expanded(
              child: sorted.isEmpty
                  ? Center(child: Text(ref.t('mobile.conf.qnaEmpty'), style: const TextStyle(color: Colors.white38)))
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
                                        child: Text(ref.t('mobile.conf.qnaAnswered'), style: const TextStyle(color: Color(0xFF22C55E), fontSize: 12)),
                                      ),
                                    if (q.answered)
                                      Text(ref.t('mobile.conf.qnaAnsweredDone'), style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11)),
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
                      decoration: InputDecoration(
                        hintText: ref.t('mobile.conf.qnaHint'),
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        border: const OutlineInputBorder(borderSide: BorderSide.none),
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
