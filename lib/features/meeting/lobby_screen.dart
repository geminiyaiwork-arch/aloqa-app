/// ALOQA — lobby / preview (M10). Camera+mic preview + name + join.
///
/// Uses flutter_webrtc for the local preview directly (works on all platforms
/// at 0.11.7). On join it calls POST /meetings/{id}/join and pushes the
/// conference screen with the LiveKit token. Password-protected meetings prompt
/// for the password; with a waiting room the same call is polled every ~3 s
/// until the host admits (or denies) the user.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_service.dart';
import '../auth/auth_provider.dart';
import 'conference_screen.dart';
import 'meeting_models.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, required this.meetingId});

  final String meetingId;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final _renderer = RTCVideoRenderer();
  final _name = TextEditingController();
  MediaStream? _stream;
  bool _camOn = true;
  bool _micOn = true;
  bool _joining = false;
  String? _previewError;

  // Parol bilan himoyalangan uchrashuv.
  bool _hasPassword = false;
  String? _password;

  // Kutish xonasi: host qabul qilguncha /join so'rovi takrorlanadi.
  bool _waiting = false;
  Timer? _pollTimer;

  /// Konferensiya ekraniga o'tildi — kech kelgan preview oqimi darhol yopiladi.
  bool _entered = false;


  @override
  void initState() {
    super.initState();
    // Ismni ro'yxatdagi nom bilan to'ldiramiz (tarifsizlar o'zgartira olmaydi).
    final user = ref.read(authProvider).user;
    if (user != null && _name.text.isEmpty) {
      _name.text = user.name;
    }
    _initPreview();
    _loadMeetingInfo();
  }

  /// Uchrashuv parolli ekanini oldindan bilib olamiz (a'zo bo'lmaganlarga
  /// server `has_password` qaytaradi). Xato bo'lsa — join o'zi aniq javob beradi.
  Future<void> _loadMeetingInfo() async {
    try {
      final m = await MeetingRepository.instance.get(widget.meetingId);
      if (!mounted) return;
      if (m.hasPassword) setState(() => _hasPassword = true);
    } catch (_) {/* ignore */}
  }

  Future<void> _initPreview() async {
    try {
      await _renderer.initialize();
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user'},
      });
      if (!mounted || _entered) {
        // Ekran allaqachon yopilgan (yoki konferensiyaga kirilgan) — kamera va
        // mikrofonni DARHOL bo'shatamiz, aks holda ular band bo'lib qoladi.
        await _releaseStream(stream);
        return;
      }
      // Preview kelguncha foydalanuvchi tugmalarni bosgan bo'lishi mumkin.
      for (final t in stream.getVideoTracks()) {
        t.enabled = _camOn;
      }
      for (final t in stream.getAudioTracks()) {
        t.enabled = _micOn;
      }
      _stream = stream;
      _renderer.srcObject = stream;
      setState(() {});
    } catch (e) {
      // Permission denied / no device — allow audio-only / name-only join.
      if (mounted) setState(() => _previewError = e.toString());
    }
  }

  Future<void> _releaseStream(MediaStream stream) async {
    try {
      await stream.dispose();
    } catch (_) {/* ignore */}
  }

  // Tugmalar preview oqimi bo'lmasa ham ishlaydi (kamerasiz kompyuter, ruxsat
  // berilmagan holat): tanlov konferensiyaga startCam/startMic sifatida uzatiladi.
  void _toggleCam() {
    setState(() => _camOn = !_camOn);
    final tracks = _stream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    for (final t in tracks) {
      t.enabled = _camOn;
    }
  }

  void _toggleMic() {
    setState(() => _micOn = !_micOn);
    final tracks = _stream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    for (final t in tracks) {
      t.enabled = _micOn;
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String? get _guestName {
    final n = _name.text.trim();
    return n.isEmpty ? null : n;
  }

  Future<JoinInfo> _callJoin() => MeetingRepository.instance.join(
        widget.meetingId,
        guestName: _guestName,
        password: _password,
        cam: _camOn,
        mic: _micOn,
      );

  /// Token olindi-yu, ekranga kirilmadi (bekor qilindi / ekran yopildi) —
  /// serverdagi "qo'shildi" belgisini qaytarib qo'yamiz. Best-effort.
  void _releaseJoin() {
    unawaited(MeetingRepository.instance
        .leave(widget.meetingId)
        .catchError((Object _) {}));
  }

  Future<void> _join() async {
    if (_joining || _waiting) return;
    if (_hasPassword && (_password ?? '').isEmpty) {
      final pw = await _askPassword();
      if (pw == null || !mounted) return;
      _password = pw;
    }
    setState(() => _joining = true);
    await _attemptJoin();
  }

  Future<void> _attemptJoin() async {
    try {
      final info = await _callJoin();
      if (!mounted) {
        if (!info.waiting) _releaseJoin();
        return;
      }
      if (info.waiting) {
        setState(() {
          _joining = false;
          _waiting = true;
        });
        _schedulePoll(const Duration(seconds: 3));
        return;
      }
      await _enter(info);
    } on DioException catch (e) {
      if (!mounted) return;
      await _handleJoinError(e);
    } catch (_) {
      if (!mounted) return;
      _stopWaiting();
      _snack(ref.tt('common.error'));
    } finally {
      if (mounted && _joining) setState(() => _joining = false);
    }
  }

  /// Aniq sabab ko'rsatamiz ("Uchrashuv tugagan" / "qulflangan" / "to'la") —
  /// umumiy "Xatolik" emas. Parol xatosida qayta so'raymiz.
  Future<void> _handleJoinError(DioException e) async {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final serverMsg = (data is Map && data['message'] is String)
        ? (data['message'] as String).trim()
        : '';
    final lower = serverMsg.toLowerCase();
    if (_joining) setState(() => _joining = false);

    // 403 + "parol": parol yo'q yoki noto'g'ri → qayta so'raymiz.
    if (status == 403 && lower.contains('parol')) {
      _stopWaiting();
      final hadPassword = (_password ?? '').isNotEmpty;
      _password = null;
      _hasPassword = true;
      final pw = await _askPassword(wrong: hadPassword);
      if (pw == null || !mounted) return;
      _password = pw;
      setState(() => _joining = true);
      await _attemptJoin();
      return;
    }

    _stopWaiting();
    // 429: juda ko'p xato parol — keyingi urinishda parol qayta so'raladi.
    if (status == 429) _password = null;
    var msg = serverMsg.isNotEmpty ? serverMsg : ref.tt('common.error');
    if (status == 403 && lower.contains('rad et')) {
      msg = ref.tt('mobile.lobby.denied');
    }
    _snack(msg);
  }

  // ---- Kutish xonasi ------------------------------------------------------

  void _schedulePoll(Duration delay) {
    _pollTimer?.cancel();
    _pollTimer = Timer(delay, _pollJoin);
  }

  void _stopWaiting() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_waiting) return;
    if (mounted) {
      setState(() => _waiting = false);
    } else {
      _waiting = false;
    }
  }

  Future<void> _pollJoin() async {
    if (!mounted || !_waiting) return;
    try {
      final info = await _callJoin();
      if (!mounted || !_waiting) {
        // Kutish bekor qilingan / ekran yopilgan paytda qabul qilingan bo'lsa.
        if (!info.waiting) _releaseJoin();
        return;
      }
      if (info.waiting) {
        _schedulePoll(const Duration(seconds: 3));
        return;
      }
      _pollTimer = null;
      setState(() => _waiting = false);
      await _enter(info);
    } on DioException catch (e) {
      if (!mounted || !_waiting) return;
      final status = e.response?.statusCode;
      if (status == null || status >= 500) {
        // Tarmoq uzildi / server vaqtincha javob bermadi — kutishda davom etamiz.
        _schedulePoll(const Duration(seconds: 3));
        return;
      }
      if (status == 429) {
        // So'rovlar chegarasi — sekinroq takrorlaymiz.
        _schedulePoll(const Duration(seconds: 10));
        return;
      }
      await _handleJoinError(e);
    } catch (_) {
      if (mounted && _waiting) _schedulePoll(const Duration(seconds: 3));
    }
  }

  // ---- Kirish -------------------------------------------------------------

  Future<void> _enter(JoinInfo info) async {
    _entered = true;
    // Release preview before entering the room (frees the camera).
    await _disposePreview();
    if (!mounted) {
      _releaseJoin();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConferenceScreen(
        meetingId: widget.meetingId,
        joinInfo: info,
        startCam: _camOn,
        startMic: _micOn,
      ),
    ));
  }

  Future<String?> _askPassword({bool wrong = false}) async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ref.tt('mobile.lobby.passwordTitle')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            hintText: ref.tt('mobile.lobby.passwordHint'),
            errorText: wrong ? ref.tt('mobile.lobby.passwordWrong') : null,
            prefixIcon: const Icon(Icons.lock_outline),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ref.tt('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(ref.tt('action.join')),
          ),
        ],
      ),
    );
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> _disposePreview() async {
    final stream = _stream;
    _stream = null;
    try {
      _renderer.srcObject = null;
    } catch (_) {/* ignore */}
    if (stream != null) await _releaseStream(stream);
  }

  @override
  void dispose() {
    // Ekran tark etildi — kutish so'rovlari to'xtaydi.
    _pollTimer?.cancel();
    _pollTimer = null;
    _waiting = false;
    _disposePreview();
    _renderer.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Android orqaga: lobby go_router bilan ochilgan (stack almashtirilgan) → orqaga bosilsa
    // ilovadan chiqib ketardi. Endi DASHBOARDga (asosiy) qaytaradi.
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) context.go('/home');
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(ref.t('lobby.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: Colors.black,
                    child: _previewError != null || !_camOn || _stream == null
                        ? const Center(
                            child: Icon(Icons.videocam_off,
                                color: Colors.white54, size: 56),
                          )
                        : RTCVideoView(_renderer, mirror: true),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundToggle(
                    on: _micOn,
                    onIcon: Icons.mic,
                    offIcon: Icons.mic_off,
                    onTap: _toggleMic,
                  ),
                  const SizedBox(width: 20),
                  _RoundToggle(
                    on: _camOn,
                    onIcon: Icons.videocam,
                    offIcon: Icons.videocam_off,
                    onTap: _toggleCam,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Builder(builder: (_) {
                final u = ref.watch(authProvider).user;
                final hasPlan =
                    (u?.planId != null && u!.planId!.trim().isNotEmpty);
                return TextField(
                  controller: _name,
                  readOnly: !hasPlan,
                  decoration: InputDecoration(
                    labelText: ref.t('lobby.yourName'),
                    prefixIcon: const Icon(Icons.person_outline),
                    suffixIcon: hasPlan
                        ? null
                        : const Icon(Icons.lock_outline,
                            size: 18, color: Color(0xFF94A3B8)),
                    helperText: hasPlan
                        ? null
                        : ref.t('mobile.lobby.namePlanLocked'),
                  ),
                );
              }),
              const SizedBox(height: 16),
              if (_waiting)
                _waitingCard()
              else
                FilledButton.icon(
                  onPressed: _joining ? null : _join,
                  icon: _joining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white))
                      : const Icon(Icons.video_call),
                  label: Text(ref.t('lobby.joinNow')),
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  /// "Host qabul qilishini kuting" holati (kutish xonasi).
  Widget _waitingCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ref.t('conf.waiting.title'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ref.t('conf.waiting.desc'),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _stopWaiting,
              child: Text(ref.t('action.cancel')),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundToggle extends StatelessWidget {
  const _RoundToggle({
    required this.on,
    required this.onIcon,
    required this.offIcon,
    required this.onTap,
  });

  final bool on;
  final IconData onIcon;
  final IconData offIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      child: CircleAvatar(
        radius: 28,
        backgroundColor: on
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.errorContainer,
        child: Icon(on ? onIcon : offIcon,
            color: on
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
