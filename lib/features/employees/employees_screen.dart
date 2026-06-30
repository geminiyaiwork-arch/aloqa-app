/// ALOQA — Employees (Hodimlar reestri).
///
/// Web parity of /app/employees. Lists attendance-roster employees, gates on
/// the attendance entitlement, supports add + EDIT (name / position / phone /
/// photo) and optimistic delete. Phone binds the employee to a login account
/// so conference attendance matching is stable (#10); a "linked" badge shows it.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:aloqa/core/i18n/i18n_service.dart';
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
  int _tab = 0; // 0 = Hodimlar, 1 = Davomat hisobotlari

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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tabBar(),
              const SizedBox(height: 14),
              Expanded(
                child: _tab == 0
                    ? _Main(
                        res: res,
                        removing: _removing,
                        onAdd: () => _openEmployeeModal(),
                        onEdit: (emp) => _openEmployeeModal(editing: emp),
                        onDelete: (emp) => _confirmDelete(emp),
                      )
                    : const _ReportsView(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tabBar() {
    Widget seg(int i, String label) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _tab == i ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: _tab == i
                    ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                    : null,
              ),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _tab == i ? AppColors.brand700 : AppColors.slate500)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [seg(0, 'Hodimlar'), seg(1, 'Davomat hisobotlari')]),
    );
  }

  /// Kontaktdan tanlash — uchrashuv kontaktlarini ko'rsatadi, tanlanganini qaytaradi.
  Future<MeetingContact?> _showContactPicker() {
    return showModalBottomSheet<MeetingContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(builder: (ctx, setSheet) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.92,
            minChildSize: 0.4,
            builder: (ctx, scrollCtrl) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
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
                    const Text('Kontaktni tanlang',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.slate900)),
                    const SizedBox(height: 10),
                    TextField(
                      onChanged: (v) => setSheet(() => query = v),
                      decoration: InputDecoration(
                        hintText: 'Qidirish…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.slate50,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: FutureBuilder<List<MeetingContact>>(
                        future: EmployeesRepository.instance.meetingContacts(),
                        builder: (ctx, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.brand600));
                          }
                          final all = snap.data ?? const <MeetingContact>[];
                          final q = query.trim().toLowerCase();
                          final items = q.isEmpty
                              ? all
                              : all
                                  .where((c) =>
                                      c.name.toLowerCase().contains(q) ||
                                      (c.phone ?? '').contains(q) ||
                                      (c.email ?? '').toLowerCase().contains(q))
                                  .toList();
                          if (items.isEmpty) {
                            return const Center(
                                child: Text('Kontaktlar topilmadi',
                                    style: TextStyle(color: AppColors.slate400)));
                          }
                          return ListView.builder(
                            controller: scrollCtrl,
                            itemCount: items.length,
                            itemBuilder: (ctx, i) {
                              final c = items[i];
                              return ListTile(
                                onTap: () => Navigator.of(ctx).pop(c),
                                leading: (c.avatar != null && c.avatar!.isNotEmpty)
                                    ? CircleAvatar(
                                        backgroundImage:
                                            CachedNetworkImageProvider(c.avatar!))
                                    : CircleAvatar(
                                        backgroundColor: AppColors.brand600,
                                        child: Text(
                                            (c.name.isEmpty ? '?' : c.name[0])
                                                .toUpperCase(),
                                            style: const TextStyle(
                                                color: Colors.white))),
                                title: Text(c.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(c.phone ?? c.email ?? '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        });
      },
    );
  }

  // ---- Add / edit employee modal ------------------------------------------

  Future<void> _openEmployeeModal({Employee? editing}) async {
    final isEdit = editing != null;
    final nameCtrl = TextEditingController(text: editing?.name ?? '');
    final positionCtrl = TextEditingController(text: editing?.position ?? '');
    final phoneCtrl = TextEditingController(text: editing?.phone ?? '');
    Uint8List? pickedBytes; // new photo chosen this session (overrides existing)
    var busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModal) {
            Future<void> pickPhoto() async {
              try {
                final picked = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1024,
                  imageQuality: 88,
                );
                if (picked == null) return;
                final bytes = await File(picked.path).readAsBytes();
                setModal(() => pickedBytes = bytes);
              } catch (_) {
                if (!dialogCtx.mounted) return;
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  SnackBar(
                      content: Text(ref.tt('mobile.profile.imageUploadFailed'))),
                );
              }
            }

            Future<void> save() async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              setModal(() => busy = true);
              try {
                final repo = EmployeesRepository.instance;
                if (isEdit) {
                  await repo.update(
                    editing.id,
                    name: name,
                    position: positionCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    photoBytes: pickedBytes,
                  );
                } else {
                  await repo.create(
                    name: name,
                    position: positionCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    photoBytes: pickedBytes,
                  );
                }
                if (!dialogCtx.mounted) return;
                Navigator.of(dialogCtx).pop();
                ref.invalidate(employeesProvider);
              } catch (_) {
                if (!dialogCtx.mounted) return;
                setModal(() => busy = false);
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  SnackBar(content: Text(ref.tt('common.error'))),
                );
              }
            }

            final canSave = !busy && nameCtrl.text.trim().isNotEmpty;

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
                            child: Icon(
                                isEdit
                                    ? Icons.edit_outlined
                                    : Icons.person_add_alt_1,
                                color: AppColors.brand600,
                                size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isEdit
                                  ? ref.tt('mobile.employees.editModalTitle')
                                  : ref.tt('mobile.employees.addModalTitle'),
                              style: const TextStyle(
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
                      if (!isEdit) ...[
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  final c = await _showContactPicker();
                                  if (c != null) {
                                    nameCtrl.text = c.name;
                                    if (c.phone != null &&
                                        c.phone!.trim().isNotEmpty) {
                                      phoneCtrl.text = c.phone!.trim();
                                    }
                                    setModal(() {});
                                  }
                                },
                          icon: const Icon(Icons.contacts_outlined, size: 18),
                          label: const Text('Kontaktdan tanlash'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.brand700,
                            side: const BorderSide(color: AppColors.brand200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _PhotoPicker(
                        name: nameCtrl.text.trim().isEmpty
                            ? (editing?.name ?? '')
                            : nameCtrl.text.trim(),
                        pickedBytes: pickedBytes,
                        existingPhoto: editing?.photo,
                        onPick: busy ? null : pickPhoto,
                      ),
                      const SizedBox(height: 20),
                      AloqaInput(
                        controller: nameCtrl,
                        label: ref.tt('mobile.employees.nameLabel'),
                        hint: ref.tt('mobile.employees.nameHint'),
                        prefixIcon: Icons.badge_outlined,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setModal(() {}),
                      ),
                      const SizedBox(height: 14),
                      AloqaInput(
                        controller: positionCtrl,
                        label: ref.tt('mobile.employees.positionLabel'),
                        hint: ref.tt('mobile.employees.positionHint'),
                        prefixIcon: Icons.work_outline,
                      ),
                      const SizedBox(height: 14),
                      AloqaInput(
                        controller: phoneCtrl,
                        label: ref.tt('mobile.employees.phoneLabel'),
                        hint: ref.tt('mobile.employees.phoneHint'),
                        prefixIcon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline,
                              size: 15, color: AppColors.slate400),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              ref.tt('mobile.employees.phoneHelp'),
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.slate400),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      GradientButton(
                        label: ref.tt('action.save'),
                        busy: busy,
                        icon: Icons.check,
                        onPressed: canSave ? save : null,
                      ),
                      const SizedBox(height: 10),
                      GhostButton(
                        label: ref.tt('action.cancel'),
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
          title: Text(
            ref.tt('mobile.employees.deleteTitle'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.slate900,
            ),
          ),
          content: Text(
            ref.tt('mobile.employees.deleteConfirm', {'name': emp.name}),
            style: const TextStyle(fontSize: 14, color: AppColors.slate600),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(
                ref.tt('action.cancel'),
                style: const TextStyle(color: AppColors.slate500),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                minimumSize: const Size(96, 44),
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(ref.tt('mobile.action.delete')),
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
        SnackBar(content: Text(ref.tt('common.error'))),
      );
    }
  }
}

// ===========================================================================
// MAIN content (attendance enabled)
// ===========================================================================

class _Main extends ConsumerWidget {
  const _Main({
    required this.res,
    required this.removing,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final EmployeesResult res;
  final Set<int> removing;
  final VoidCallback onAdd;
  final void Function(Employee) onEdit;
  final void Function(Employee) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible =
        res.employees.where((e) => !removing.contains(e.id)).toList();
    final count = visible.length;
    final max = res.maxEmployees;
    final atLimit = max > 0 && res.employees.length >= max;

    final headerCounter = max > 0
        ? ref.t('mobile.employees.headerCounterMax',
            {'count': '${res.employees.length}', 'max': '$max'})
        : ref.t('mobile.employees.headerCounter',
            {'count': '${res.employees.length}'});

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
                    Text(
                      ref.t('mobile.employees.rosterTitle'),
                      style: const TextStyle(
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
                disabledReason: atLimit ? ref.t('mobile.employees.limitReached') : null,
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
                      ref.t('mobile.employees.limitWarning', {'max': '$max'}),
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
            onEdit: onEdit,
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
    required this.onEdit,
    required this.onDelete,
  });

  final List<Employee> employees;
  final int count;
  final void Function(Employee) onEdit;
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
                    onEdit: () => onEdit(employees[i]),
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

class _EmployeeCard extends ConsumerWidget {
  const _EmployeeCard({
    required this.employee,
    required this.onEdit,
    required this.onDelete,
  });

  final Employee employee;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AloqaCard(
      padding: const EdgeInsets.all(16),
      onTap: onEdit, // bosish → tahrir (ism/lavozim/telefon/rasm)
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
                if (employee.linked) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.brand50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      ref.t('mobile.employees.linkedBadge'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand700,
                      ),
                    ),
                  ),
                ],
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

class _DeleteIconButton extends ConsumerStatefulWidget {
  const _DeleteIconButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  ConsumerState<_DeleteIconButton> createState() => _DeleteIconButtonState();
}

class _DeleteIconButtonState extends ConsumerState<_DeleteIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: IconButton(
        tooltip: ref.t('mobile.action.delete'),
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

class _AddButton extends ConsumerWidget {
  const _AddButton({required this.onPressed, this.disabledReason});

  final VoidCallback? onPressed;
  final String? disabledReason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disabled = onPressed == null;
    final button = FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: 18),
      label: Text(ref.t('mobile.employees.addButton')),
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
// Photo picker for the add/edit modal (image_picker → gallery → bytes)
// ===========================================================================

class _PhotoPicker extends ConsumerWidget {
  const _PhotoPicker({
    required this.name,
    required this.pickedBytes,
    required this.existingPhoto,
    required this.onPick,
  });

  final String name;
  final Uint8List? pickedBytes;
  final String? existingPhoto;
  final VoidCallback? onPick;

  String get _initial {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return t.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const size = 84.0;
    final hasExisting =
        existingPhoto != null && existingPhoto!.trim().isNotEmpty;

    Widget avatar;
    if (pickedBytes != null) {
      avatar = ClipOval(
        child: Image.memory(pickedBytes!,
            width: size, height: size, fit: BoxFit.cover),
      );
    } else if (hasExisting) {
      avatar = ClipOval(
        child: CachedNetworkImage(
          imageUrl: existingPhoto!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _initialCircle(size),
        ),
      );
    } else {
      avatar = _initialCircle(size);
    }

    final hasAny = pickedBytes != null || hasExisting;

    return Column(
      children: [
        avatar,
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.image_outlined, size: 18),
          label: Text(hasAny
              ? ref.t('mobile.employees.photoChange')
              : ref.t('mobile.profile.pickImage')),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brand700,
            side: const BorderSide(color: AppColors.brand200),
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _initialCircle(double size) => Container(
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
}

// ===========================================================================
// States: loading / error / gated / empty roster
// ===========================================================================

class _LoadingState extends ConsumerWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.brand600),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ref.t('common.loading'),
            style: const TextStyle(
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

class _ErrorState extends ConsumerWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              Text(
                ref.t('common.error'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                ref.t('mobile.employees.loadFailed'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.slate500),
              ),
              const SizedBox(height: 20),
              GhostButton(
                label: ref.t('action.retry'),
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

class _GatedState extends ConsumerWidget {
  const _GatedState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: RevealUp(
        child: AloqaCard(
          padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          child: Column(
            children: [
              const Text('📋', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 18),
              Text(
                ref.t('mobile.employees.gatedTitle'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.slate900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ref.t('mobile.employees.gatedSub'),
                textAlign: TextAlign.center,
                style: const TextStyle(
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

class _EmptyRoster extends ConsumerWidget {
  const _EmptyRoster();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          Text(
            ref.t('mobile.employees.emptyTitle'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.slate700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            ref.t('mobile.employees.emptySub'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.slate400),
          ),
        ],
      ),
    );
  }
}

String _fmtDt(DateTime? d) {
  if (d == null) return '—';
  const m = ['yan', 'fev', 'mar', 'apr', 'may', 'iyn', 'iyl', 'avg', 'sen', 'okt', 'noy', 'dek'];
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day}-${m[(d.month - 1).clamp(0, 11)]}, $hh:$mm';
}

/// Davomat hisobotlari ro'yxati (Davomat menyusi "Hisobotlar" tab) + Batafsil.
class _ReportsView extends ConsumerWidget {
  const _ReportsView();

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(attendanceHistoryProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brand600)),
      error: (_, __) => Center(
          child: Text(ref.tt('common.error'), style: const TextStyle(color: AppColors.slate400))),
      data: (reports) {
        if (reports.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Hali davomat hisoboti yo‘q.\nKonferensiyada davomatni hisoblang.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.slate400)),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(attendanceHistoryProvider),
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final r = reports[i];
              return AloqaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(r.meetingTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppColors.slate900)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.slate100,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text('#${r.meetingId}',
                              style: const TextStyle(fontSize: 11, color: AppColors.slate400)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Boshlandi: ${_fmtDt(r.startedAt)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _pill('Jami: ${r.total}', AppColors.slate100, AppColors.slate600),
                        _pill('Qatnashdi: ${r.present}', const Color(0xFFD1FAE5), const Color(0xFF047857)),
                        _pill('Qatnashmadi: ${r.absent}', const Color(0xFFFEE2E2), AppColors.danger),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: GradientButton(
                        label: 'Batafsil',
                        icon: Icons.list_alt_outlined,
                        onPressed: () => _showDetail(context, ref, r),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref, AttendanceHistoryReport r) {
    Widget cell(String v, String label, Color bg, Color fg) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(v, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: fg)),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: AppColors.slate500)),
            ]),
          ),
        );
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.meetingTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.slate900)),
                          Text('#${r.meetingId}${r.meetingCode != null ? ' · ${r.meetingCode}' : ''}',
                              style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
                        ],
                      ),
                    ),
                    IconButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        icon: const Icon(Icons.close, color: AppColors.slate400)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(children: [
                  cell('${r.total}', 'Jami', AppColors.slate50, AppColors.slate900),
                  cell('${r.present}', 'Qatnashdi', const Color(0xFFECFDF5), const Color(0xFF047857)),
                  cell('${r.absent}', 'Qatnashmadi', const Color(0xFFFEF2F2), AppColors.danger),
                  cell('${r.percent.round()}%', 'Foiz', AppColors.brand50, AppColors.brand700),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Boshlandi: ${_fmtDt(r.startedAt)}', style: const TextStyle(fontSize: 13, color: AppColors.slate700)),
                      const SizedBox(height: 2),
                      Text('Tugadi: ${_fmtDt(r.endedAt)}', style: const TextStyle(fontSize: 13, color: AppColors.slate700)),
                      if (r.generatedByName != null && r.generatedByName!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Sanagan: ${r.generatedByName}', style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Hodimlar', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.slate700)),
                const SizedBox(height: 8),
                if (r.items.isEmpty)
                  const Text('Hodim yo‘q', style: TextStyle(color: AppColors.slate400))
                else
                  for (final it in r.items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: it.present ? const Color(0xFFECFDF5) : AppColors.slate100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          if (it.photo != null && it.photo!.isNotEmpty)
                            CircleAvatar(radius: 18, backgroundImage: CachedNetworkImageProvider(it.photo!))
                          else
                            CircleAvatar(
                                radius: 18,
                                backgroundColor: AppColors.brand600,
                                child: Text((it.name.isEmpty ? '?' : it.name[0]).toUpperCase(),
                                    style: const TextStyle(color: Colors.white))),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.slate900)),
                                Text((it.position == null || it.position!.trim().isEmpty) ? '—' : it.position!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: it.present ? const Color(0xFFD1FAE5) : AppColors.danger.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(
                                it.present
                                    ? (it.minutes > 0 ? '✓ ${it.minutes} daq' : '✓ Bor')
                                    : 'Yo‘q',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: it.present ? const Color(0xFF047857) : AppColors.danger)),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 8),
                GradientButton(label: ref.tt('conf.att.close'), onPressed: () => Navigator.of(dialogCtx).pop()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
