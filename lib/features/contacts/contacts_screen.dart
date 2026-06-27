/// ALOQA — Kontaktlar. Permission gate → contact list with editable saved name.
/// The saved name is what shows in conferences for that person.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aloqa/core/i18n/i18n_service.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/app_shell.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/features/contacts/contacts_service.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  bool? _granted; // null = checking
  bool _loading = false;
  bool _slow = false; // load taking too long → show retry
  List<AppContact> _all = [];
  String _query = '';
  Timer? _slowTimer;

  // (E13) Ishtirokchilar tabi — uchrashuvlardan yig'ilган
  List<AppContact> _participants = [];
  bool _pLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
    _loadParticipants();
  }

  Future<void> _loadParticipants() async {
    final list = await ContactsStore.instance
        .meetingContacts(guestFallback: ref.tt('mobile.contacts.guest'));
    if (!mounted) return;
    setState(() {
      _participants = list;
      _pLoading = false;
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  // On entry we DON'T request the system permission (that can hang on MIUI when
  // the dialog never appears). We only read the saved flag: if contacts were
  // enabled before, load directly; otherwise show the gate and let the user tap.
  Future<void> _init() async {
    final enabledBefore = await ContactsStore.instance.wasEnabled();
    if (!mounted) return;
    if (enabledBefore) {
      setState(() => _granted = true);
      await _reload();
    } else {
      setState(() {
        _granted = false;
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    _slowTimer?.cancel();
    setState(() {
      _loading = true;
      _slow = false;
    });
    _slowTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _loading) setState(() => _slow = true);
    });
    final list = await ContactsStore.instance.load();
    _slowTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
      _slow = false;
    });
  }

  Future<void> _ask() async {
    setState(() => _loading = true);
    final ok = await ContactsStore.instance.hasPermission();
    if (!mounted) return;
    setState(() => _granted = ok);
    if (ok) {
      await _reload();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _edit(AppContact c) async {
    final ctrl = TextEditingController(text: c.override ?? '');
    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(ref.tt('mobile.contacts.savedName')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.rawPhone,
                style: const TextStyle(color: AppColors.slate500, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: ref.tt('mobile.contacts.nameHint'),
                helperText: ref.tt('mobile.contacts.nameHelper'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, '__clear__'),
            child: Text(ref.tt('mobile.action.clear'),
                style: const TextStyle(color: AppColors.slate500)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brand600),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(ref.tt('action.save')),
          ),
        ],
      ),
    );
    if (res == null) return;
    await ContactsStore.instance
        .setOverride(c.phone, res == '__clear__' ? null : res);
    if (_granted == true) await _reload();
    await _loadParticipants();
  }

  @override
  Widget build(BuildContext context) {
    // (E11) Tepada 2 ta tugma: Kontaktlar / Ishtirokchilar
    return AloqaAppShell(
      currentPath: '/contacts',
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: TabBar(
                labelColor: AppColors.brand600,
                unselectedLabelColor: AppColors.slate500,
                indicatorColor: AppColors.brand600,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                tabs: [
                  Tab(text: ref.t('mobile.contacts.tabContacts')),
                  Tab(text: ref.t('mobile.contacts.tabParticipants')),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [
                  _content(),
                  _participantsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // (E13) Ishtirokchilar tabi
  Widget _participantsTab() {
    if (_pLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.brand600));
    }
    if (_participants.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            ref.t('mobile.contacts.participantsEmpty'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.slate400),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
              ref.t('mobile.contacts.participantsCount',
                  {'count': '${_participants.length}'}),
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate400)),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: _participants.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _row(_participants[i]),
          ),
        ),
      ],
    );
  }

  Widget _content() {
    if (_granted == false) {
      return SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 8),
            AloqaCard(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                        color: AppColors.brand50,
                        borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.contacts_outlined,
                        size: 32, color: AppColors.brand600),
                  ),
                  const SizedBox(height: 16),
                  Text(ref.t('mobile.contacts.permissionTitle'),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.slate900)),
                  const SizedBox(height: 6),
                  Text(
                    ref.t('mobile.contacts.permissionSub'),
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 14, color: AppColors.slate500),
                  ),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: GradientButton(
                        label: ref.t('mobile.contacts.allowButton'),
                        icon: Icons.lock_open,
                        onPressed: _ask),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.brand600),
            const SizedBox(height: 16),
            Text(ref.t('mobile.contacts.loading'),
                style: const TextStyle(color: AppColors.slate500)),
            if (_slow) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  ref.t('mobile.contacts.slowHint'),
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppColors.slate400, fontSize: 13),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _reload,
                child: Text(ref.t('action.retry')),
              ),
            ],
          ],
        ),
      );
    }

    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? _all
        : _all
            .where((c) =>
                c.displayName.toLowerCase().contains(q) ||
                c.phone.contains(q) ||
                c.rawPhone.contains(q))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: ref.t('mobile.contacts.searchHint'),
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
              ref.t('mobile.contacts.contactsCount',
                  {'count': '${list.length}'}),
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate400)),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          _all.isEmpty
                              ? ref.t('mobile.contacts.notFound')
                              : ref.t('mobile.contacts.searchNotFound'),
                          style: const TextStyle(color: AppColors.slate400)),
                      if (_all.isEmpty) ...[
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _ask,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(ref.t('action.retry')),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _row(list[i]),
                ),
        ),
      ],
    );
  }

  Widget _row(AppContact c) {
    final hasOverride = c.override != null && c.override!.trim().isNotEmpty;
    final initial =
        c.displayName.trim().isNotEmpty ? c.displayName.trim()[0].toUpperCase() : '?';
    return AloqaCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: () => _edit(c),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.brand600,
            child: Text(initial,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(c.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.slate900)),
                    ),
                    if (hasOverride) ...[
                      const SizedBox(width: 6),
                      StatusChip(
                          label: ref.t('mobile.contacts.savedChip'),
                          color: AppColors.brand600),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(c.rawPhone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.slate500)),
              ],
            ),
          ),
          const Icon(Icons.edit_outlined, size: 18, color: AppColors.slate400),
        ],
      ),
    );
  }
}
