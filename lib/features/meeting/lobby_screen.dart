/// ALOQA — lobby / preview (M10). Camera+mic preview + name + join.
///
/// Uses flutter_webrtc for the local preview directly (works on all platforms
/// at 0.11.7). On join it calls POST /meetings/{id}/join and pushes the
/// conference screen with the LiveKit token.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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

  @override
  void initState() {
    super.initState();
    // Ismni ro'yxatdagi nom bilan to'ldiramiz (tarifsizlar o'zgartira olmaydi).
    final user = ref.read(authProvider).user;
    if (user != null && _name.text.isEmpty) {
      _name.text = user.name;
    }
    _initPreview();
  }

  Future<void> _initPreview() async {
    try {
      await _renderer.initialize();
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user'},
      });
      _stream = stream;
      _renderer.srcObject = stream;
      if (mounted) setState(() {});
    } catch (e) {
      // Permission denied / no device — allow audio-only / name-only join.
      if (mounted) setState(() => _previewError = e.toString());
    }
  }

  void _toggleCam() {
    final track = _stream?.getVideoTracks().firstOrNull;
    if (track != null) {
      _camOn = !_camOn;
      track.enabled = _camOn;
      setState(() {});
    }
  }

  void _toggleMic() {
    final track = _stream?.getAudioTracks().firstOrNull;
    if (track != null) {
      _micOn = !_micOn;
      track.enabled = _micOn;
      setState(() {});
    }
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      final info = await MeetingRepository.instance.join(
        widget.meetingId,
        guestName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      );
      // Release preview before entering the room (frees the camera).
      await _disposePreview();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConferenceScreen(
          meetingId: widget.meetingId,
          joinInfo: info,
          startCam: _camOn,
          startMic: _micOn,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      // Aniq sabab ko'rsatamiz ("Uchrashuv tugagan"/"parol noto'g'ri"/"to'la") — umumiy "Xatolik" emas.
      var msg = ref.t('common.error');
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data['message'] is String && (data['message'] as String).trim().isNotEmpty) {
          msg = data['message'] as String;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _disposePreview() async {
    _renderer.srcObject = null;
    await _stream?.dispose();
    _stream = null;
  }

  @override
  void dispose() {
    _disposePreview();
    _renderer.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(ref.t('lobby.title'))),
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
                    child: _previewError != null || !_camOn
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

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
