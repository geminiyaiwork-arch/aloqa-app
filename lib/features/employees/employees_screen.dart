/// ALOQA — Employees (Hodimlar reestri).
///
/// Web parity of /app/employees. Lists attendance-roster employees, gates on
/// the attendance entitlement, supports add (name + position; photo upload is
/// deferred — image_picker is absent) and optimistic delete.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/aloqa_input.dart';
import 'package:aloqa/core/widgets/app_shell.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/core/widgets/ghost_button.dart';
import 'package:aloqa/core/widgets/reveal.dart';
import 'package:aloqa/features/employees/employees_repository.dart';

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  /// Ids being optimistically removed (hidden from the grid while delete flies).
  final Set<int> _removing = <int>{};

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(employeesProvider);

    return AloqaAppShell(
      currentPath: '/employees',
      child: async.when(
        loading: () => const _LoadingState(),
        error: (_, __) => _ErrorState(
          onRetry: () => ref.invalidate(employeesProvider),
        ),
        data: (res) {
          if (!res.attendanceEnabled) {
            return const _GatedState();
          }
          return _Main(
            res: res,
            removing: _removing,
            onAdd: () => _openAddModal(res),
            onDelete: (emp) => _confirmDelete(emp),
          );
        },
      ),
    );
  }

  // ---- Add employee modal -------------------------------------------------

  Future<void> _openAddModal(EmployeesResult res) async {
    final nameCtrl = TextEditingController();
    final positionCtrl = TextEditingController();
    var busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModal) {
            Future<void> save() async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              setModal(() => busy = true);
              try {
                await EmployeesRepository.instance
                    .create(name: name, position: positionCtrl.text.trim());
                if (!dialogCtx.mounted) return;
                Navigator.of(dialogCtx).pop();
                ref.invalidate(employeesProvider);
              } catch (_) {
                if (!dialogCtx.mounted) return;
                setModal(() => busy = false);
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  const SnackBar(content: Text('Xatolik yuz berdi')),
                );
              }
            }

            final canSave =
                !busy && nameCtrl.text.trim().isNotEmpty;

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.brand50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.person_add_alt_1,
                                color: AppColors.brand600, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Yangi hodim',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.slate900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: busy
                                ? null
                                : () => Navigator.of(dialogCtx).pop(),
                            icon: const Icon(Icons.close,
                                color: AppColors.slate400),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Photo placeholder + disabled picker (image_picker absent).
                      const _PhotoPlaceholder(),
                      const SizedBox(height: 20),
                      AloqaInput(
                        controller: nameCtrl,
                        label: 'Ism *',
                        hint: 'Hodimning to\'liq ismi',
                        prefixIcon: Icons.badge_outlined,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setModal(() {}),
                      ),
                      const SizedBox(height: 14),
                      AloqaInput(
                        controller: positionCtrl,
                        label: 'Lavozim',
                        hint: 'Masalan: Menejer',
                        prefixIcon: Icons.work_outline,
                      ),
                      const SizedBox(height: 24),
                      GradientButton(
                        label: 'Saqlash',
                        busy: busy,
                        icon: Icons.check,
                        onPressed: canSave ? save : null,
                      ),
                      const SizedBox(height: 10),
                      GhostButton(
                        label: 'Bekor qilish',
                        onPressed:
                            busy ? null : () => Navigator.of(dialogCtx).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---- Delete confirm + optimistic removal --------------------------------

  Future<void> _confirmDelete(Employee emp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Hodimni o\'chirasizmi?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.slate900,
            ),
          ),
          content: Text(
            '«${emp.name}» reestrdan o\'chiriladi. Bu amalni ortga qaytarib bo\'lmaydi.',
            style: const TextStyle(fontSize: 14, color: AppColors.slate600),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text(
                'Bekor qilish',
                style: TextStyle(color: AppColors.slate500),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                minimumSize: const Size(96, 44),
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('O\'chirish'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    // Optimistic hide.
    setState(() => _removing.add(emp.id));
    try {
      await EmployeesRepository.instance.delete(emp.id);
      if (!mounted) return;
      ref.invalidate(employeesProvider);
      setState(() => _removing.remove(emp.id));
    } catch (_) {
      if (!mounted) return;
      // Rollback hide on failure.
      setState(() => _removing.remove(emp.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xatolik yuz berdi')),
      );
    }
  }
}

// ===========================================================================
// MAIN content (attendance enabled)
// ===========================================================================

class _Main extends StatelessWidget {
  const _Main({
    required this.res,
    required this.removing,
    required this.onAdd,
    required this.onDelete,
  });

  final EmployeesResult res;
  final Set<int> removing;
  final VoidCallback onAdd;
  final void Function(Employee) onDelete;

  @override
  Widget build(BuildContext context) {
    final visible =
        res.employees.where((e) => !removing.contains(e.id)).toList();
    final count = visible.length;
    final max = res.maxEmployees;
    final atLimit = max > 0 && res.employees.length >= max;

    final headerCounter =
        'Hodimlar: ${res.employees.length}${max > 0 ? ' / $max' : ''}';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        RevealUp(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hodimlar reestri',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.slate900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headerCounter,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _AddButton(
                onPressed: atLimit ? null : onAdd,
                disabledReason: atLimit ? 'Limit to\'ldi' : null,
              ),
            ],
          ),
        ),
        if (atLimit) ...[
          const SizedBox(height: 12),
          RevealUp(
            delayMs: 40,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.brand50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.brand200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.brand700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tarifingiz bo\'yicha hodimlar soni chegarasiga ($max) yetdingiz.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.brand700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (visible.isEmpty)
          const RevealUp(delayMs: 60, child: _EmptyRoster())
        else
          _Grid(
            employees: visible,
            count: count,
            onDelete: onDelete,
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.employees,
    required this.count,
    required this.onDelete,
  });

  final List<Employee> employees;
  final int count;
  final void Function(Employee) onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 1100
            ? 4
            : w >= 820
                ? 3
                : w >= 520
                    ? 2
                    : 1;
        const gap = 16.0;
        final tileW = (w - gap * (cols - 1)) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < employees.length; i++)
              SizedBox(
                width: tileW,
                child: RevealUp(
                  delayMs: 40 + (i % cols) * 30 + (i ~/ cols) * 20,
                  child: _EmployeeCard(
                    employee: employees[i],
                    onDelete: () => onDelete(employees[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee, required this.onDelete});

  final Employee employee;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AloqaCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _Avatar(name: employee.name, photo: employee.photo, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  employee.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  (employee.position == null || employee.position!.trim().isEmpty)
                      ? '—'
                      : employee.position!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.slate400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _DeleteIconButton(onPressed: onDelete),
        ],
      ),
    );
  }
}

class _DeleteIconButton extends StatefulWidget {
  const _DeleteIconButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_DeleteIconButton> createState() => _DeleteIconButtonState();
}

class _DeleteIconButtonState extends State<_DeleteIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: IconButton(
        tooltip: 'O\'chirish',
        splashRadius: 22,
        onPressed: widget.onPressed,
        icon: Icon(
          Icons.close,
          size: 20,
          color: _hover ? AppColors.danger : AppColors.slate300,
        ),
      ),
    );
  }
}

// ===========================================================================
// Avatar
// ===========================================================================

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photo, this.size = 56});

  final String name;
  final String? photo;
  final double size;

  String get _initial {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return t.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photo != null && photo!.trim().isNotEmpty;

    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.brand600,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );

    if (!hasPhoto) return fallback;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photo!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: size,
          height: size,
          color: AppColors.slate100,
        ),
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

// ===========================================================================
// Add button (finite minimum size — never a bare full-width FilledButton)
// ===========================================================================

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed, this.disabledReason});

  final VoidCallback? onPressed;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final button = FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Hodim qo\'shish'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand600,
        disabledBackgroundColor: AppColors.slate200,
        disabledForegroundColor: AppColors.slate400,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    if (disabled && disabledReason != null) {
      return Tooltip(message: disabledReason!, child: button);
    }
    return button;
  }
}

// ===========================================================================
// Photo placeholder for the add modal (upload deferred — image_picker absent)
// ===========================================================================

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.slate100,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.slate200),
          ),
          child: const Icon(Icons.photo_camera_outlined,
              size: 30, color: AppColors.slate400),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.image_outlined, size: 18),
          label: const Text('Rasm tanlash'),
          style: OutlinedButton.styleFrom(
            disabledForegroundColor: AppColors.slate400,
            side: const BorderSide(color: AppColors.slate200),
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '(tez kunda)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.slate400,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// States: loading / error / gated / empty roster
// ===========================================================================

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.brand600),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Yuklanmoqda…',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.slate400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: RevealUp(
        child: AloqaCard(
          padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline,
                    color: AppColors.danger, size: 30),
              ),
              const SizedBox(height: 16),
              const Text(
                'Xatolik yuz berdi',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Hodimlar ro\'yxatini yuklab bo\'lmadi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.slate500),
              ),
              const SizedBox(height: 20),
              GhostButton(
                label: 'Qayta urinish',
                leading: const Icon(Icons.refresh,
                    size: 18, color: AppColors.slate700),
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GatedState extends StatelessWidget {
  const _GatedState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 24),
      child: RevealUp(
        child: AloqaCard(
          padding: EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          child: Column(
            children: [
              Text('📋', style: TextStyle(fontSize: 48)),
              SizedBox(height: 18),
              Text(
                'Davomat yoqilmagan',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.slate900,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Davomat moduli tarifingizda mavjud emas. '
                'Hodimlar reestridan foydalanish uchun tarifingizni yangilang.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.slate500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRoster extends StatelessWidget {
  const _EmptyRoster();

  @override
  Widget build(BuildContext context) {
    return AloqaCard(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.brand50,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_outlined,
                size: 32, color: AppColors.brand600),
          ),
          const SizedBox(height: 16),
          const Text(
            'Hali hodim qo\'shilmagan.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.slate700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Davomatni kuzatish uchun birinchi hodimingizni qo\'shing.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.slate400),
          ),
        ],
      ),
    );
  }
}
