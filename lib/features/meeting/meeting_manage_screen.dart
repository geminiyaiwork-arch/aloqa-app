/// ALOQA — Uchrashuvni boshqarish (Meeting Manage).
/// Host control panel for a single meeting: details/rename, entry mode,
/// lifecycle (start/end/delete + auto-end duration), live participants &
/// waiting room, history table and transcript generation/download.
library;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aloqa/core/config/app_config.dart';
import 'package:aloqa/core/format.dart';
import 'package:aloqa/core/i18n/i18n_service.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/app_shell.dart';
import 'package:aloqa/core/widgets/error_banner.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/core/widgets/reveal.dart';
import 'package:aloqa/features/meeting/meeting_models.dart';
import 'package:aloqa/features/meeting/meeting_providers.dart';

class MeetingManageScreen extends ConsumerStatefulWidget {
  const MeetingManageScreen({super.key, required this.meetingId});

  final String meetingId;

  @override
  ConsumerState<MeetingManageScreen> createState() =>
      _MeetingManageScreenState();
}

class _MeetingManageScreenState extends ConsumerState<MeetingManageScreen> {
  final _repo = MeetingRepository.instance;

  Meeting? _meeting;
  bool _loading = true;
  bool _notFound = false;

  // Inline title editing.
  bool _editingTitle = false;
  final _titleCtrl = TextEditingController();
  bool _savingTitle = false;

  // Transient "copied" flags.
  bool _copiedLink = false;
  bool _copiedId = false;
  bool _copiedLinkBox = false;

  // Busy flags for lifecycle actions.
  bool _busyEntry = false;
  bool _busyStart = false;
  bool _busyDuration = false;
  bool _busyEnd = false;
  bool _busyDelete = false;

  // Transcript.
  TranscriptInfo? _transcript;
  bool _busyTranscribe = false;
  Timer? _transcriptTimer;

  // Online / waiting tabs.
  bool _showWaitingTab = false;

  String get _id => widget.meetingId;

  String get _inviteLink => '${AppConfig.webOrigin}/m/$_id/lobby';

  static const _durations = <int>[15, 30, 45, 60, 120, 180, 360, 720, 1440, 0];

  @override
  void initState() {
    super.initState();
    _load();
    _loadTranscript();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _transcriptTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });
    try {
      final m = await _repo.get(_id);
      if (!mounted) return;
      setState(() {
        _meeting = m;
        _titleCtrl.text = m.title;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = true;
      });
    }
  }

  Future<void> _reload() async {
    try {
      final m = await _repo.get(_id);
      if (!mounted) return;
      setState(() {
        _meeting = m;
        if (!_editingTitle) _titleCtrl.text = m.title;
      });
    } catch (_) {/* keep old state */}
    ref.invalidate(meetingLiveProvider(_id));
  }

  // ---- Transcript polling -------------------------------------------------

  Future<void> _loadTranscript() async {
    try {
      final t = await _repo.transcript(_id);
      if (!mounted) return;
      setState(() => _transcript = t);
      _scheduleTranscriptPoll();
    } catch (_) {/* transcript not available — leave as null */}
  }

  void _scheduleTranscriptPoll() {
    _transcriptTimer?.cancel();
    final st = _transcript?.status.toLowerCase();
    if (st == 'pending' || st == 'processing') {
      _transcriptTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) _loadTranscript();
      });
    }
  }

  // ---- Helpers ------------------------------------------------------------

  void _snackError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ref.tt('common.error'))),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _copy(String text, void Function(bool) flag) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    flag(true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) flag(false);
    });
  }

  // ---- Actions ------------------------------------------------------------

  Future<void> _saveTitle() async {
    final v = _titleCtrl.text.trim();
    if (v.isEmpty) {
      setState(() => _editingTitle = false);
      return;
    }
    setState(() => _savingTitle = true);
    try {
      final m = await _repo.patch(_id, {'title': v});
      if (!mounted) return;
      setState(() {
        _meeting = m;
        _editingTitle = false;
        _savingTitle = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingTitle = false);
      _snackError();
    }
  }

  Future<void> _setWaitingRoom(bool on) async {
    if (_busyEntry) return;
    setState(() => _busyEntry = true);
    try {
      final m = await _repo.patch(_id, {
        'settings': {'waiting_room': on},
      });
      if (!mounted) return;
      setState(() => _meeting = m);
    } catch (_) {
      _snackError();
    } finally {
      if (mounted) setState(() => _busyEntry = false);
    }
  }

  Future<void> _startMeeting() async {
    setState(() => _busyStart = true);
    try {
      final m = await _repo.patch(_id, {'status': 'live'});
      if (!mounted) return;
      setState(() => _meeting = m);
      ref.invalidate(meetingLiveProvider(_id));
    } catch (_) {
      _snackError();
    } finally {
      if (mounted) setState(() => _busyStart = false);
    }
  }

  Future<void> _setDuration(int minutes) async {
    setState(() => _busyDuration = true);
    try {
      final iso = minutes == 0
          ? null
          : DateTime.now()
              .add(Duration(minutes: minutes))
              .toUtc()
              .toIso8601String();
      final m = await _repo.patch(_id, {'auto_end_at': iso});
      if (!mounted) return;
      setState(() => _meeting = m);
    } catch (_) {
      _snackError();
    } finally {
      if (mounted) setState(() => _busyDuration = false);
    }
  }

  Future<void> _patchAutoEnd(DateTime when) async {
    setState(() => _busyDuration = true);
    try {
      final m = await _repo
          .patch(_id, {'auto_end_at': when.toUtc().toIso8601String()});
      if (!mounted) return;
      setState(() => _meeting = m);
    } catch (_) {
      _snackError();
    } finally {
      if (mounted) setState(() => _busyDuration = false);
    }
  }

  Future<void> _pickAutoEndDate() async {
    final m = _meeting;
    if (m == null) return;
    final base = (m.autoEndAt ?? DateTime.now().add(const Duration(hours: 1)))
        .toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    final when =
        DateTime(date.year, date.month, date.day, base.hour, base.minute);
    await _patchAutoEnd(when);
  }

  Future<void> _pickAutoEndTime() async {
    final m = _meeting;
    if (m == null) return;
    final base = (m.autoEndAt ?? DateTime.now().add(const Duration(hours: 1)))
        .toLocal();
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (time == null) return;
    final when =
        DateTime(base.year, base.month, base.day, time.hour, time.minute);
    await _patchAutoEnd(when);
  }

  Future<void> _endMeeting() async {
    setState(() => _busyEnd = true);
    try {
      await _repo.endMeeting(_id);
      await _reload();
    } catch (_) {
      _snackError();
    } finally {
      if (mounted) setState(() => _busyEnd = false);
    }
  }

  Future<void> _deleteMeeting() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ref.tt('mobile.manage.deleteTitle')),
        content: Text(ref.tt('mobile.manage.deleteConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ref.tt('action.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(ref.tt('mobile.action.delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyDelete = true);
    try {
      await _repo.delete(_id);
      if (!mounted) return;
      context.go('/home');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyDelete = false);
      _snackError();
    }
  }

  Future<void> _admit(WaitingPerson p, String decision) async {
    // Optimistic: refresh live afterwards; swallow errors like web.
    try {
      await _repo.admit(_id, participantId: p.id, decision: decision);
    } catch (_) {/* swallow */}
    ref.invalidate(meetingLiveProvider(_id));
  }

  Future<void> _kick(ParticipantHistory p) async {
    try {
      await _repo.kick(_id, participantId: p.id);
    } catch (_) {/* swallow */}
    ref.invalidate(meetingLiveProvider(_id));
  }

  Future<void> _generateTranscript() async {
    setState(() => _busyTranscribe = true);
    try {
      await _repo.transcribe(_id);
      await _loadTranscript();
    } catch (_) {
      _snack(ref.tt('mobile.manage.transcriptNeedRecord'));
    } finally {
      if (mounted) setState(() => _busyTranscribe = false);
    }
  }

  Future<void> _showTranscriptText(String format) async {
    // No filesystem package — fetch bytes, decode as text, show in dialog with
    // a clipboard "copy" button (download is degraded to view+copy by design).
    try {
      List<int> bytes;
      try {
        bytes = await _repo.transcriptDownload(_id, format: format);
      } catch (_) {
        bytes = const [];
      }
      var text = bytes.isNotEmpty
          ? String.fromCharCodes(bytes)
          : (_transcript?.text ?? '');
      if (text.trim().isEmpty) text = ref.tt('mobile.manage.transcriptEmpty');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
              ref.tt('mobile.manage.transcriptDialogTitle', {'format': format})),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (ctx.mounted) Navigator.of(ctx).pop();
                _snack(ref.tt('action.copied'));
              },
              child: Text(ref.tt('action.copy')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(ref.tt('mobile.action.close')),
            ),
          ],
        ),
      );
    } catch (_) {
      _snackError();
    }
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AloqaAppShell(
        currentPath: '/meeting/:id',
        child: _CenteredState(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.brand600),
              const SizedBox(height: 16),
              Text(ref.t('common.loading'),
                  style: const TextStyle(color: AppColors.slate500)),
            ],
          ),
        ),
      );
    }

    if (_notFound || _meeting == null) {
      return AloqaAppShell(
        currentPath: '/meeting/:id',
        child: _CenteredState(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔍', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                ref.t('mobile.manage.notFound'),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate900),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: GradientButton(
                  label: ref.t('mobile.manage.homeButton'),
                  icon: Icons.home_rounded,
                  onPressed: () => context.go('/home'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final m = _meeting!;
    return AloqaAppShell(
      currentPath: '/meeting/:id',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return SingleChildScrollView(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _backLink(),
              const SizedBox(height: 16),
              RevealUp(child: _header(m)),
              const SizedBox(height: 20),
              RevealUp(delayMs: 60, child: _detailGrid(m, wide)),
              const SizedBox(height: 20),
              RevealUp(delayMs: 120, child: _participantsCard()),
              const SizedBox(height: 20),
              RevealUp(delayMs: 180, child: _historyCard()),
              const SizedBox(height: 20),
              RevealUp(delayMs: 240, child: _transcriptCard()),
              const SizedBox(height: 24),
            ],
            ),
          );
        },
      ),
    );
  }

  Widget _backLink() {
    return InkWell(
      onTap: () => context.go('/home'),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          ref.t('mobile.manage.back'),
          style: const TextStyle(
              color: AppColors.brand600, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ---- Header -------------------------------------------------------------

  Widget _header(Meeting m) {
    final st = meetingStatusStyle(m.status);
    final code = m.code ?? m.id;
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brand600,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.videocam_rounded,
                    color: Colors.white, size: 24),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  m.title,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.slate900),
                ),
              ),
              StatusChip(label: st.label, color: st.color),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ref.t('mobile.manage.conferenceIdLabel', {'code': code}),
            style: const TextStyle(color: AppColors.slate500, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _outlineAction(
                icon: _copiedLink ? Icons.check_rounded : Icons.link_rounded,
                label: _copiedLink
                    ? ref.t('mobile.manage.copiedCheck')
                    : ref.t('mobile.manage.copyLink'),
                onTap: () =>
                    _copy(_inviteLink, (v) => setState(() => _copiedLink = v)),
              ),
              SizedBox(
                width: 220,
                child: GradientButton(
                  label: ref.t('mobile.manage.joinMeeting'),
                  icon: Icons.login_rounded,
                  onPressed: () => context.go('/lobby/$_id'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _outlineAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.slate700,
        side: const BorderSide(color: AppColors.slate200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ---- 3-column detail grid ----------------------------------------------

  Widget _detailGrid(Meeting m, bool wide) {
    final cols = [
      _detailCol(m),
      _entryCol(m),
      _manageCol(m),
    ];
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cols.length; i++) ...[
            if (i > 0) const SizedBox(width: 20),
            Expanded(child: cols[i]),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < cols.length; i++) ...[
          if (i > 0) const SizedBox(height: 20),
          cols[i],
        ],
      ],
    );
  }

  // COL 1 — Konferensiya ma'lumotlari
  Widget _detailCol(Meeting m) {
    final code = m.code ?? m.id;
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(ref.t('mobile.manage.detailsHeading')),
          const SizedBox(height: 14),
          _fieldLabel(ref.t('mobile.manage.nameLabel')),
          const SizedBox(height: 6),
          if (_editingTitle)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleCtrl,
                    autofocus: true,
                    onSubmitted: (_) => _saveTitle(),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.slate200),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: _savingTitle ? null : _saveTitle,
                  icon: _savingTitle
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.brand600),
                        )
                      : const Icon(Icons.check_rounded,
                          color: AppColors.brand600),
                  tooltip: ref.t('mobile.manage.tooltipSave'),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    m.title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate900),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    _titleCtrl.text = m.title;
                    setState(() => _editingTitle = true);
                  },
                  icon: const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.slate500),
                  tooltip: ref.t('mobile.manage.tooltipEdit'),
                ),
              ],
            ),
          const SizedBox(height: 16),
          _fieldLabel(ref.t('mobile.manage.conferenceId')),
          const SizedBox(height: 6),
          _copyBox(
            value: code,
            copied: _copiedId,
            onCopy: () => _copy(code, (v) => setState(() => _copiedId = v)),
          ),
          const SizedBox(height: 16),
          _fieldLabel(ref.t('mobile.manage.inviteLink')),
          const SizedBox(height: 6),
          _copyBox(
            value: _inviteLink,
            copied: _copiedLinkBox,
            onCopy: () =>
                _copy(_inviteLink, (v) => setState(() => _copiedLinkBox = v)),
          ),
        ],
      ),
    );
  }

  Widget _copyBox({
    required String value,
    required bool copied,
    required VoidCallback onCopy,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.slate200),
      ),
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.slate700,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          IconButton(
            onPressed: onCopy,
            icon: Icon(
              copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 18,
              color: copied ? AppColors.brand600 : AppColors.slate500,
            ),
            tooltip: ref.t('mobile.manage.tooltipCopy'),
          ),
        ],
      ),
    );
  }

  // COL 2 — Kirish sozlamasi
  Widget _entryCol(Meeting m) {
    final waiting = m.settings?['waiting_room'] == true;
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(ref.t('mobile.manage.entryHeading')),
          const SizedBox(height: 14),
          _entryRadio(
            selected: !waiting,
            title: ref.t('mobile.manage.entryOpen'),
            subtitle: ref.t('mobile.manage.entryOpenSub'),
            icon: Icons.lock_open_rounded,
            onTap: _busyEntry ? null : () => _setWaitingRoom(false),
          ),
          const SizedBox(height: 12),
          _entryRadio(
            selected: waiting,
            title: ref.t('mobile.manage.entryWaiting'),
            subtitle: ref.t('mobile.manage.entryWaitingSub'),
            icon: Icons.meeting_room_rounded,
            onTap: _busyEntry ? null : () => _setWaitingRoom(true),
          ),
        ],
      ),
    );
  }

  Widget _entryRadio({
    required bool selected,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.brand500 : AppColors.slate200,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 22,
                color: selected ? AppColors.brand600 : AppColors.slate400),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: selected
                            ? AppColors.brand700
                            : AppColors.slate900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.slate500),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppColors.brand600 : AppColors.slate300,
            ),
          ],
        ),
      ),
    );
  }

  // COL 3 — Konferensiyani boshqarish
  Widget _manageCol(Meeting m) {
    final isLive = (m.status ?? '').toLowerCase() == 'live';
    final isEnded = (m.status ?? '').toLowerCase() == 'ended';
    int? currentDuration;
    // Best-effort reflect existing auto-end as a duration choice (left as
    // hint only; selection drives PATCH).
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(ref.t('mobile.manage.manageHeading')),
          const SizedBox(height: 14),
          if (!isLive && !isEnded) ...[
            GradientButton(
              label: ref.t('meeting.startMeeting'),
              icon: Icons.play_arrow_rounded,
              busy: _busyStart,
              onPressed: _busyStart ? null : _startMeeting,
            ),
            const SizedBox(height: 16),
          ],
          _fieldLabel(ref.t('mobile.manage.autoEnd')),
          const SizedBox(height: 6),
          Text(
            fmtDateTime(m.autoEndAt),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.slate900),
          ),
          const SizedBox(height: 12),
          _fieldLabel(ref.t('mobile.manage.durationLabel')),
          const SizedBox(height: 6),
          Opacity(
            opacity: _busyDuration ? 0.6 : 1,
            child: DropdownButtonFormField<int>(
              value: currentDuration,
              isExpanded: true,
              hint: Text(ref.t('mobile.manage.pickPlaceholder')),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.slate200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.slate200),
                ),
              ),
              items: [
                for (final d in _durations)
                  DropdownMenuItem<int>(
                    value: d,
                    child: Text(_durationLabel(d)),
                  ),
              ],
              onChanged: _busyDuration
                  ? null
                  : (v) {
                      if (v != null) _setDuration(v);
                    },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _pickerButton(
                  icon: Icons.calendar_today_rounded,
                  label: ref.t('mobile.manage.dateLabel'),
                  onTap: _busyDuration ? null : _pickAutoEndDate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _pickerButton(
                  icon: Icons.schedule_rounded,
                  label: ref.t('mobile.manage.timeLabel'),
                  onTap: _busyDuration ? null : _pickAutoEndTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AppColors.slate200),
          const SizedBox(height: 14),
          if (!isEnded)
            _dangerButton(
              icon: Icons.stop_circle_outlined,
              label: ref.t('mobile.manage.end'),
              busy: _busyEnd,
              onTap: _busyEnd ? null : _endMeeting,
            ),
          if (!isEnded) const SizedBox(height: 10),
          _dangerButton(
            icon: Icons.delete_outline_rounded,
            label: ref.t('mobile.action.delete'),
            busy: _busyDelete,
            filled: true,
            onTap: _busyDelete ? null : _deleteMeeting,
          ),
        ],
      ),
    );
  }

  String _durationLabel(int d) {
    if (d == 0) return ref.t('mobile.duration.unlimited');
    if (d == 60) return ref.t('mobile.duration.hour1');
    if (d == 120) return ref.t('mobile.duration.hour2');
    if (d == 180) return ref.t('mobile.duration.hour3');
    if (d == 360) return ref.t('mobile.duration.hour6');
    if (d == 720) return ref.t('mobile.duration.hour12');
    if (d == 1440) return ref.t('mobile.duration.hour24');
    return ref.t('mobile.duration.minutes', {'minutes': '$d'});
  }

  Widget _pickerButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.slate700,
        side: const BorderSide(color: AppColors.slate200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _dangerButton({
    required IconData icon,
    required String label,
    required bool busy,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    final child = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.danger),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          );
    if (filled) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: child,
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: const BorderSide(color: AppColors.danger),
          minimumSize: const Size(double.infinity, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: child,
      ),
    );
  }

  // ---- Participants card (Online / Waiting tabs) --------------------------

  Widget _participantsCard() {
    final liveAsync = ref.watch(meetingLiveProvider(_id));
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(ref.t('conf.participants')),
          const SizedBox(height: 12),
          Row(
            children: [
              _tab(ref.t('mobile.manage.tabOnline'), !_showWaitingTab,
                  () => setState(() => _showWaitingTab = false)),
              const SizedBox(width: 8),
              _tab(ref.t('mobile.manage.tabWaiting'), _showWaitingTab,
                  () => setState(() => _showWaitingTab = true)),
            ],
          ),
          const SizedBox(height: 14),
          liveAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.brand600),
              ),
            ),
            error: (_, __) =>
                InlineErrorBanner(message: ref.t('common.error')),
            data: (live) => _showWaitingTab
                ? _waitingList(live.waiting)
                : _onlineTable(
                    live.participants.where((p) => p.active).toList()),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.brand600 : AppColors.slate100,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: active ? Colors.white : AppColors.slate600,
          ),
        ),
      ),
    );
  }

  Widget _onlineTable(List<ParticipantHistory> rows) {
    if (rows.isEmpty) {
      return _emptyRow(ref.t('mobile.manage.noOnline'));
    }
    return Column(
      children: [
        for (final p in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Row(
              children: [
                _avatar(p.avatar, p.name, 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.slate900),
                      ),
                      Text(
                        p.role == 'host'
                            ? ref.t('mobile.manage.roleHost')
                            : ref.t('mobile.manage.roleParticipant'),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.slate400),
                      ),
                    ],
                  ),
                ),
                Icon(p.usedMic ? Icons.mic : Icons.mic_off,
                    size: 18,
                    color: p.usedMic ? AppColors.brand600 : AppColors.slate400),
                const SizedBox(width: 12),
                Icon(p.usedCam ? Icons.videocam : Icons.videocam_off,
                    size: 18,
                    color: p.usedCam ? AppColors.brand600 : AppColors.slate400),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: AppColors.slate400),
                  onSelected: (v) {
                    if (v == 'kick') _kick(p);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      value: 'kick',
                      child: Text(ref.t('mobile.manage.kick'),
                          style: const TextStyle(color: AppColors.danger)),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _waitingList(List<WaitingPerson> rows) {
    if (rows.isEmpty) {
      return _emptyRow(ref.t('mobile.manage.waitingEmpty'));
    }
    return Column(
      children: [
        for (final p in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Row(
              children: [
                _avatar(p.avatar, p.name, 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate900),
                  ),
                ),
                SizedBox(
                  height: 36,
                  child: FilledButton(
                    onPressed: () => _admit(p, 'admit'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand600,
                      minimumSize: const Size(0, 36),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(ref.t('mobile.action.admit'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: () => _admit(p, 'deny'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.slate200),
                      minimumSize: const Size(0, 36),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(ref.t('mobile.action.deny'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---- History card -------------------------------------------------------

  Widget _historyCard() {
    final liveAsync = ref.watch(meetingLiveProvider(_id));
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(ref.t('mobile.manage.historyHeading')),
          const SizedBox(height: 14),
          liveAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.brand600),
              ),
            ),
            error: (_, __) =>
                InlineErrorBanner(message: ref.t('common.error')),
            data: (live) {
              final rows = live.participants;
              if (rows.isEmpty) {
                return _emptyRow(ref.t('mobile.manage.historyEmpty'));
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.slate600),
                  dataTextStyle: const TextStyle(
                      fontSize: 13, color: AppColors.slate700),
                  columns: [
                    DataColumn(label: Text(ref.t('mobile.table.name'))),
                    DataColumn(label: Text(ref.t('mobile.table.joined'))),
                    DataColumn(label: Text(ref.t('mobile.table.left'))),
                    DataColumn(label: Text(ref.t('mobile.table.minutes'))),
                    DataColumn(label: Text(ref.t('mobile.table.camera'))),
                    DataColumn(label: Text(ref.t('mobile.table.mic'))),
                  ],
                  rows: [
                    for (final p in rows)
                      DataRow(cells: [
                        DataCell(Text(p.name)),
                        DataCell(Text(p.joinedAt == null
                            ? '—'
                            : fmtTime(p.joinedAt!))),
                        DataCell(Text(
                            p.leftAt == null ? '—' : fmtTime(p.leftAt!))),
                        DataCell(Text('${p.durationMin}')),
                        DataCell(Icon(
                          p.usedCam ? Icons.check_circle : Icons.remove_circle_outline,
                          size: 18,
                          color: p.usedCam
                              ? AppColors.brand600
                              : AppColors.slate300,
                        )),
                        DataCell(Icon(
                          p.usedMic ? Icons.check_circle : Icons.remove_circle_outline,
                          size: 18,
                          color: p.usedMic
                              ? AppColors.brand600
                              : AppColors.slate300,
                        )),
                      ]),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---- Transcript card ----------------------------------------------------

  Widget _transcriptCard() {
    final t = _transcript;
    return AloqaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(ref.t('mobile.manage.transcriptHeading')),
          const SizedBox(height: 14),
          if (t == null)
            _emptyRow(ref.t('mobile.manage.transcriptNone'))
          else if (!t.allowed)
            _transcriptGated()
          else
            _transcriptAllowed(t),
        ],
      ),
    );
  }

  Widget _transcriptGated() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brand50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brand200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_outlined,
                  size: 20, color: AppColors.brand600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ref.t('mobile.manage.transcriptGated'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 180,
            child: GradientButton(
              label: ref.t('mobile.manage.viewPlan'),
              icon: Icons.arrow_forward_rounded,
              onPressed: () => context.go('/billing'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _transcriptAllowed(TranscriptInfo t) {
    final status = t.status.toLowerCase();
    final isDone = status == 'done' && t.hasText;
    final isWorking = status == 'pending' || status == 'processing';

    if (isDone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(
                  label: ref.t('mobile.manage.transcriptReady'),
                  color: AppColors.brand600),
              if (t.language != null) ...[
                const SizedBox(width: 8),
                Text(
                    ref.t('mobile.manage.transcriptLang',
                        {'language': '${t.language}'}),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.slate500)),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _outlineAction(
                icon: Icons.download_rounded,
                label: '.txt',
                onTap: () => _showTranscriptText('txt'),
              ),
              _outlineAction(
                icon: Icons.download_rounded,
                label: '.srt',
                onTap: () => _showTranscriptText('srt'),
              ),
            ],
          ),
          if ((t.text ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.slate200),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  t.text!,
                  style: const TextStyle(
                      fontSize: 13, height: 1.5, color: AppColors.slate700),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isWorking)
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.brand600),
              ),
              const SizedBox(width: 10),
              Text(
                status == 'pending'
                    ? ref.t('mobile.manage.transcriptQueued')
                    : ref.t('mobile.manage.transcriptProcessing'),
                style: const TextStyle(color: AppColors.slate600),
              ),
            ],
          )
        else
          Text(
            ref.t('mobile.manage.transcriptIntro'),
            style: const TextStyle(color: AppColors.slate600),
          ),
        const SizedBox(height: 14),
        SizedBox(
          width: 220,
          child: GradientButton(
            label: ref.t('mobile.manage.generateTranscript'),
            icon: Icons.notes_rounded,
            busy: _busyTranscribe,
            onPressed:
                (_busyTranscribe || isWorking) ? null : _generateTranscript,
          ),
        ),
      ],
    );
  }

  // ---- Small shared pieces ------------------------------------------------

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.slate500),
      );

  Widget _emptyRow(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(text,
              style: const TextStyle(color: AppColors.slate400)),
        ),
      );

  Widget _avatar(String? url, String name, double size) {
    final initial =
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _avatarFallback(initial, size),
          errorWidget: (_, __, ___) => _avatarFallback(initial, size),
        ),
      );
    }
    return _avatarFallback(initial, size);
  }

  Widget _avatarFallback(String initial, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.brand600,
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: size * 0.42),
        ),
      );
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Center(child: child),
    );
  }
}
