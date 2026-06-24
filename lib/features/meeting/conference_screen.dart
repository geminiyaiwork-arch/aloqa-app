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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/i18n_service.dart';
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

class _ConferenceScreenState extends ConsumerState<ConferenceScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _connecting = true;
  bool _micOn = true;
  bool _camOn = true;
  bool _sharing = false;
  bool _handRaised = false;
  String? _error;

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

  static const _emojis = ['👍', '❤️', '😂', '👏', '🎉', '😮'];

  @override
  void initState() {
    super.initState();
    _micOn = widget.startMic && !_viewOnly;
    _camOn = widget.startCam && !_viewOnly;
    _connect();
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
        if (mounted) Navigator.of(context).maybePop();
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
          if (m['raised'] == true && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✋ Ishtirokchi qo\'l ko\'tardi'), duration: Duration(seconds: 2)),
            );
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
    setState(() => _handRaised = !_handRaised);
    await _publish({'kind': 'hand', 'raised': _handRaised});
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

  Future<void> _toggleShare() async {
    _sharing = !_sharing;
    try {
      await _room?.localParticipant?.setScreenShareEnabled(_sharing);
    } catch (_) {
      _sharing = !_sharing;
    }
    _refresh();
  }

  Future<void> _leave() async {
    await _room?.disconnect();
    if (mounted) Navigator.of(context).maybePop();
  }

  List<VideoTrack> _videoTracks() {
    final out = <VideoTrack>[];
    final room = _room;
    if (room == null) return out;
    final local = room.localParticipant;
    if (local != null) {
      for (final pub in local.videoTrackPublications) {
        final t = pub.track;
        if (t != null) out.add(t);
      }
    }
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        final t = pub.track;
        if (t != null && pub.subscribed) out.add(t);
      }
    }
    return out;
  }

  int get _participantCount => _room == null ? 0 : _room!.remoteParticipants.length + 1;

  @override
  void dispose() {
    _listener?.dispose();
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
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

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Text('ALOQA',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1)),
          if (_viewOnly)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text('· faqat ko\'rish', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          const Spacer(),
          const Icon(Icons.people_outline, color: Colors.white70, size: 20),
          const SizedBox(width: 6),
          Text('$_participantCount', style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
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
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _connecting = true;
                    _error = null;
                  });
                  _connect();
                },
                child: Text(ref.t('common.retry')),
              ),
            ],
          ),
        ),
      );
    }

    final tracks = _videoTracks();
    if (tracks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, color: Colors.white38, size: 48),
            SizedBox(height: 12),
            Text('—', style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }

    final crossAxis = tracks.length == 1 ? 1 : 2;
    return GridView.count(
      crossAxisCount: crossAxis,
      padding: const EdgeInsets.all(8),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3 / 4,
      children: tracks
          .map((t) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(color: const Color(0xFF1A1A1A), child: VideoTrackRenderer(t)),
              ))
          .toList(),
    );
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

  // --- control bar ---
  Widget _controlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.black,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (!_viewOnly) ...[
              _ctrl(_micOn ? Icons.mic : Icons.mic_off, _micOn, _toggleMic),
              const SizedBox(width: 12),
              _ctrl(_camOn ? Icons.videocam : Icons.videocam_off, _camOn, _toggleCam),
              const SizedBox(width: 12),
              _ctrl(Icons.screen_share, _sharing, _toggleShare),
              const SizedBox(width: 12),
              _ctrl(Icons.edit, _boardOpen, () => setState(() => _boardOpen = !_boardOpen)),
              const SizedBox(width: 12),
            ],
            _ctrl(Icons.front_hand, _handRaised, _toggleHand),
            const SizedBox(width: 12),
            _ctrl(Icons.emoji_emotions_outlined, false, _showReactions),
            const SizedBox(width: 12),
            _badged(_ctrl(Icons.chat_bubble_outline, false, _openChat), _unread),
            const SizedBox(width: 12),
            _badged(_ctrl(Icons.help_outline, false, _openQna), _qnaUnread),
            if (_isHost) ...[
              const SizedBox(width: 12),
              _ctrl(Icons.bar_chart, false, _openPollComposer),
            ],
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _leave,
              child: const CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFFE53935),
                child: Icon(Icons.call_end, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctrl(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: 24,
        backgroundColor: active ? const Color(0xFF3F51B5) : Colors.white10,
        child: Icon(icon, color: active ? Colors.white : Colors.white60, size: 22),
      ),
    );
  }

  Widget _badged(Widget child, int count) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Color(0xFF3F51B5), shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
      ],
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
