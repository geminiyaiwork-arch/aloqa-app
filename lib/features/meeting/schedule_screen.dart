/// ALOQA — Schedule a meeting (Rejalashtirilgan uchrashuv yaratish).
///
/// Lets the host pick a title, a required date+time, a duration (>= 15 min) and
/// an optional recurrence, then creates a scheduled meeting via the foundation
/// repository and returns to the dashboard.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:aloqa/core/format.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/aloqa_input.dart';
import 'package:aloqa/core/widgets/app_shell.dart';
import 'package:aloqa/core/widgets/error_banner.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/core/widgets/reveal.dart';
import 'package:aloqa/features/meeting/meeting_models.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _duration =
      TextEditingController(text: '60');

  DateTime? _when;
  String _recurrence = '';
  bool _busy = false;
  String? _error;

  static const _recurrenceOptions = <({String value, String label})>[
    (value: '', label: 'Bir martalik'),
    (value: 'daily', label: 'Har kuni'),
    (value: 'weekly', label: 'Har hafta'),
    (value: 'monthly', label: 'Har oy'),
  ];

  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final base = _when ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: base.isBefore(now) ? now : base,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      helpText: 'Sanani tanlang',
      cancelText: 'Bekor qilish',
      confirmText: 'Tanlash',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      helpText: 'Vaqtni tanlang',
      cancelText: 'Bekor qilish',
      confirmText: 'Tanlash',
    );
    if (time == null || !mounted) return;

    setState(() {
      _when = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _error = null;
    });
  }

  int get _durationMinutes {
    final n = int.tryParse(_duration.text.trim());
    if (n == null) return 0;
    return n;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_when == null) {
      setState(() => _error = 'Sana va vaqtni tanlang');
      return;
    }
    if (_durationMinutes < 15) {
      setState(() => _error = "Davomiylik kamida 15 daqiqa bo'lishi kerak");
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await MeetingRepository.instance.createScheduled(
        title: _title.text.trim(),
        when: _when,
        durationMinutes: _durationMinutes,
        recurrence: _recurrence.isEmpty ? null : _recurrence,
      );
      if (!mounted) return;
      context.go('/home');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Xatolik yuz berdi');
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Xatolik yuz berdi')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AloqaAppShell(
      currentPath: '/schedule',
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RevealUp(
                  child: _Intro(),
                ),
                const SizedBox(height: 20),
                RevealUp(
                  delayMs: 80,
                  child: AloqaCard(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AloqaInput(
                          controller: _title,
                          label: 'Uchrashuv nomi',
                          hint: 'Masalan: Haftalik yig\'ilish',
                          prefixIcon: Icons.title_rounded,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 18),
                        _WhenField(
                          when: _when,
                          onTap: _pickWhen,
                        ),
                        const SizedBox(height: 18),
                        AloqaInput(
                          controller: _duration,
                          label: 'Davomiyligi (daqiqa)',
                          hint: '60',
                          prefixIcon: Icons.timer_outlined,
                          keyboardType: TextInputType.number,
                          onChanged: (_) {
                            if (_error != null) {
                              setState(() => _error = null);
                            }
                          },
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Eng kami 15 daqiqa.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.slate400),
                        ),
                        const SizedBox(height: 18),
                        _RecurrenceField(
                          value: _recurrence,
                          options: _recurrenceOptions,
                          onChanged: (v) =>
                              setState(() => _recurrence = v ?? ''),
                        ),
                        const SizedBox(height: 18),
                        InlineErrorBanner(message: _error),
                        if (_error != null) const SizedBox(height: 14),
                        GradientButton(
                          label: 'Saqlash',
                          icon: Icons.calendar_month_rounded,
                          busy: _busy,
                          onPressed: _busy ? null : _submit,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                RevealUp(
                  delayMs: 160,
                  child: _SummaryCard(
                    when: _when,
                    durationMinutes: _durationMinutes,
                    recurrenceLabel: _recurrenceLabel,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _recurrenceLabel {
    for (final o in _recurrenceOptions) {
      if (o.value == _recurrence) return o.label;
    }
    return 'Bir martalik';
  }
}

class _Intro extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.brand600.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.event_available_rounded,
              color: AppColors.brand600, size: 24),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Uchrashuvni rejalashtirish',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate900),
              ),
              SizedBox(height: 2),
              Text(
                "Sana, vaqt va davomiylikni belgilang.",
                style: TextStyle(fontSize: 14, color: AppColors.slate500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tappable, read-only style field that opens date+time pickers.
class _WhenField extends StatelessWidget {
  const _WhenField({required this.when, required this.onTap});

  final DateTime? when;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = when != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sana va vaqt',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.slate600),
        ),
        const SizedBox(height: 6),
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: hasValue
                        ? AppColors.brand500.withOpacity(0.55)
                        : AppColors.slate200),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 20,
                      color:
                          hasValue ? AppColors.brand600 : AppColors.slate400),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasValue
                          ? fmtDateTime(when)
                          : 'Sana va vaqtni tanlang',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                        color: hasValue
                            ? AppColors.slate900
                            : AppColors.slate400,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.slate400),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Recurrence dropdown styled to match the rest of the form.
class _RecurrenceField extends StatelessWidget {
  const _RecurrenceField({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<({String value, String label})> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Takrorlanish',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.slate600),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.slate400),
          style: const TextStyle(fontSize: 15, color: AppColors.slate900),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.repeat_rounded,
                size: 20, color: AppColors.slate400),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.slate200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.brand500, width: 2),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.slate200),
            ),
          ),
          items: [
            for (final o in options)
              DropdownMenuItem<String>(
                value: o.value,
                child: Text(o.label),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Read-only recap of the chosen schedule so the host sees what will be saved.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.when,
    required this.durationMinutes,
    required this.recurrenceLabel,
  });

  final DateTime? when;
  final int durationMinutes;
  final String recurrenceLabel;

  @override
  Widget build(BuildContext context) {
    final endsAt = (when != null && durationMinutes > 0)
        ? when!.add(Duration(minutes: durationMinutes))
        : null;
    return AloqaCard(
      padding: const EdgeInsets.all(18),
      borderColor: AppColors.brand500.withOpacity(0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ko\'rib chiqish',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.slate900),
          ),
          const SizedBox(height: 12),
          _SummaryRow(
            icon: Icons.event_rounded,
            label: 'Boshlanish',
            value: when != null ? fmtDateTime(when) : 'Tanlanmagan',
            muted: when == null,
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            icon: Icons.timelapse_rounded,
            label: 'Davomiyligi',
            value: durationMinutes >= 15 ? '$durationMinutes daqiqa' : '—',
            muted: durationMinutes < 15,
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            icon: Icons.flag_outlined,
            label: 'Tugash',
            value: endsAt != null ? fmtDateTime(endsAt) : '—',
            muted: endsAt == null,
          ),
          const SizedBox(height: 10),
          _SummaryRow(
            icon: Icons.repeat_rounded,
            label: 'Takrorlanish',
            value: recurrenceLabel,
            muted: false,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.muted,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.slate400),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.slate500),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: muted ? AppColors.slate400 : AppColors.slate900,
            ),
          ),
        ),
      ],
    );
  }
}
