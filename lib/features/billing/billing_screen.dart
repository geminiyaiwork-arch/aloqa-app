/// ALOQA — Billing: balans, tarif, to'lovlar tarixi va rejalar (web /app/billing).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aloqa/core/format.dart';
import 'package:aloqa/core/i18n/i18n_service.dart';
import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';
import 'package:aloqa/core/widgets/app_shell.dart';
import 'package:aloqa/core/widgets/error_banner.dart';
import 'package:aloqa/core/widgets/ghost_button.dart';
import 'package:aloqa/core/widgets/gradient_button.dart';
import 'package:aloqa/core/widgets/reveal.dart';
import 'package:aloqa/features/auth/auth_provider.dart';
import 'package:aloqa/features/billing/billing_repository.dart';

/// "150 000 so'm" yoki bepul reja uchun "Bepul".
String _planPrice(Plan p, WidgetRef ref) =>
    p.price > 0 ? som(p.price) : ref.tt('billing.price.free');

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(billingProvider);
    return AloqaAppShell(
      currentPath: '/billing',
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 96),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.brand600),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InlineErrorBanner(
                message: ref.t('mobile.billing.loadError'),
              ),
              const SizedBox(height: 16),
              Center(
                child: SizedBox(
                  width: 220,
                  child: GradientButton(
                    label: ref.t('mobile.billing.reload'),
                    icon: Icons.refresh,
                    onPressed: () => ref.invalidate(billingProvider),
                  ),
                ),
              ),
            ],
          ),
        ),
        data: (d) => _BillingBody(wallet: d.wallet, plans: d.plans),
      ),
    );
  }
}

class _BillingBody extends ConsumerWidget {
  const _BillingBody({required this.wallet, required this.plans});

  final WalletInfo wallet;
  final List<Plan> plans;

  String _currentPlanId(WidgetRef ref) {
    final fromUser = ref.watch(authProvider).user?.planId;
    if (fromUser != null && fromUser.isNotEmpty) return fromUser;
    // Foydalanuvchida reja yo'q bo'lsa — bepul (narxsiz) reja joriy hisoblanadi.
    for (final p in plans) {
      if (p.price <= 0) return p.id;
    }
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = _currentPlanId(ref);
    final txs = wallet.transactions;

    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── (1) Balans + tarif ─────────────────────────────────────────
        RevealUp(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 720;
              final balance = _BalanceCard(
                wallet: wallet,
                onTopup: () => _openTopupModal(context, ref, wallet),
              );
              final sub = _SubscriptionCard(wallet: wallet);
              if (wide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: balance),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: sub),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [balance, const SizedBox(height: 16), sub],
              );
            },
          ),
        ),
        const SizedBox(height: 28),

        // ── (2) To'lovlar tarixi ───────────────────────────────────────
        RevealUp(
          delayMs: 80,
          child: AloqaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeading(ref.t('billing.tx.title')),
                const SizedBox(height: 16),
                if (txs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        ref.t('billing.tx.empty'),
                        style: const TextStyle(
                          color: AppColors.slate400,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      for (var i = 0; i < txs.length; i++) ...[
                        if (i > 0)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.slate100,
                          ),
                        _TxRow(tx: txs[i]),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),

        // ── (3) Rejalar ────────────────────────────────────────────────
        RevealUp(
          delayMs: 120,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SectionHeading(ref.t('billing.plans.title')),
          ),
        ),
        const SizedBox(height: 12),
        if (plans.isEmpty)
          RevealUp(
            delayMs: 160,
            child: AloqaCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    ref.t('mobile.billing.plansEmpty'),
                    style: const TextStyle(
                        color: AppColors.slate400, fontSize: 14),
                  ),
                ),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 1100
                  ? 4
                  : c.maxWidth >= 680
                      ? 2
                      : 1;
              const gap = 16.0;
              final cardW = cols == 1
                  ? c.maxWidth
                  : (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < plans.length; i++)
                    SizedBox(
                      width: cardW,
                      child: RevealUp(
                        delayMs: 160 + i * 60,
                        child: _PlanCard(
                          plan: plans[i],
                          isCurrent: plans[i].id == currentId,
                          onChoose: () => _openPlanModal(
                            context,
                            ref,
                            plans[i],
                            wallet,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 8),
      ],
      ),
    );
  }

  // ── TOPUP MODAL ────────────────────────────────────────────────────
  void _openTopupModal(
    BuildContext context,
    WidgetRef ref,
    WalletInfo wallet,
  ) {
    final providers = wallet.providers.isNotEmpty
        ? wallet.providers
        : const ['click', 'payme', 'uzum', 'card'];
    showDialog<void>(
      context: context,
      builder: (_) => _TopupDialog(
        providers: providers,
        onDone: () => ref.invalidate(billingProvider),
      ),
    );
  }

  // ── PLAN MODAL ─────────────────────────────────────────────────────
  void _openPlanModal(
    BuildContext context,
    WidgetRef ref,
    Plan plan,
    WalletInfo wallet,
  ) {
    final providers = wallet.providers.isNotEmpty
        ? wallet.providers
        : const ['click', 'payme', 'uzum', 'card'];
    showDialog<void>(
      context: context,
      builder: (_) => _PlanDialog(
        plan: plan,
        providers: providers,
        onDone: () => ref.invalidate(billingProvider),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// BALANCE CARD (gradient brand600 -> brand700)
// ════════════════════════════════════════════════════════════════════
class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.wallet, required this.onTopup});

  final WalletInfo wallet;
  final VoidCallback onTopup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand600, AppColors.brand700],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand600.withOpacity(0.30),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ref.t('billing.balance.title'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              som(wallet.balance),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Oq pill tugma "+ To'ldirish".
          Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onTopup,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded,
                          size: 18, color: AppColors.brand700),
                      const SizedBox(width: 6),
                      Text(
                        ref.t('billing.balance.topup'),
                        style: const TextStyle(
                          color: AppColors.brand700,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// SUBSCRIPTION CARD
// ════════════════════════════════════════════════════════════════════
class _SubscriptionCard extends ConsumerWidget {
  const _SubscriptionCard({required this.wallet});

  final WalletInfo wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = wallet.subscription;
    final planName = (sub?.plan != null && sub!.plan!.isNotEmpty)
        ? sub.plan!
        : ref.t('billing.subscription.freePlan');
    final hasExpiry = sub?.expiresAt != null;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: AppColors.brand600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ref.t('billing.subscription.current'),
                  style: const TextStyle(
                    color: AppColors.slate500,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            planName,
            style: const TextStyle(
              color: AppColors.slate900,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasExpiry
                ? ref.t('mobile.billing.subscription.expiresUntil',
                    {'date': fmtDate(sub!.expiresAt)})
                : ref.t('mobile.billing.subscription.permanent'),
            style: const TextStyle(
              color: AppColors.slate400,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// TRANSACTION ROW
// ════════════════════════════════════════════════════════════════════
class _TxRow extends ConsumerWidget {
  const _TxRow({required this.tx});

  final WalletTx tx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTop = tx.isTopup;
    final st = txStatusStyle(tx.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isTop ? AppColors.brand600 : AppColors.brand500)
                  .withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isTop ? Icons.arrow_upward_rounded : Icons.star_rounded,
              size: 20,
              color: isTop ? AppColors.brand600 : AppColors.brand500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTop
                      ? ref.t('billing.tx.topup')
                      : ref.t('billing.tx.planPurchase'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate900,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${fmtDate(tx.createdAt)} · ${providerLabel(tx.provider)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate400,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                som(tx.amount),
                style: const TextStyle(
                  color: AppColors.slate900,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              StatusChip(label: st.label, color: st.color),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// PLAN CARD
// ════════════════════════════════════════════════════════════════════
class _PlanCard extends ConsumerWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.onChoose,
  });

  final Plan plan;
  final bool isCurrent;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlighted = (plan.slug ?? '').toLowerCase() == 'pro';
    final isPaid = plan.price > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? AppColors.brand600 : AppColors.slate200,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: highlighted
                ? AppColors.brand600.withOpacity(0.16)
                : Colors.black.withOpacity(0.04),
            blurRadius: highlighted ? 18 : 4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate900,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (highlighted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brand600,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    ref.t('billing.plans.recommended'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _planPrice(plan, ref),
              style: const TextStyle(
                color: AppColors.brand700,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (plan.features.isEmpty)
            Text(
              ref.t('mobile.billing.basicFeatures'),
              style: const TextStyle(color: AppColors.slate400, fontSize: 13),
            )
          else
            ...plan.features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: AppColors.brand600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f,
                        style: const TextStyle(
                          color: AppColors.slate700,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          // Tugma: joriy reja bo'lsa o'chirilgan; aks holda Tanlash/Boshlash.
          if (isCurrent)
            _DisabledPill(label: ref.t('billing.plans.currentPlan'))
          else
            GradientButton(
              label: isPaid
                  ? ref.t('billing.plans.select')
                  : ref.t('mobile.billing.plan.start'),
              icon: isPaid
                  ? Icons.arrow_forward_rounded
                  : Icons.play_arrow_rounded,
              onPressed: onChoose,
            ),
        ],
      ),
    );
  }
}

class _DisabledPill extends StatelessWidget {
  const _DisabledPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_rounded,
              size: 18, color: AppColors.brand600),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate600,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// PROVIDER PICKER (shared by topup + plan dialogs)
// ════════════════════════════════════════════════════════════════════
class _ProviderGrid extends StatelessWidget {
  const _ProviderGrid({
    required this.providers,
    required this.selected,
    required this.onSelect,
  });

  final List<String> providers;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final p in providers)
          _ProviderTile(
            provider: p,
            selected: p == selected,
            onTap: () => onSelect(p),
          ),
      ],
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final String provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.brand600 : AppColors.slate200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              provider.toLowerCase() == 'card'
                  ? Icons.credit_card_rounded
                  : Icons.account_balance_rounded,
              size: 22,
              color: selected ? AppColors.brand600 : AppColors.slate500,
            ),
            const SizedBox(height: 6),
            Text(
              providerLabel(provider),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.brand700 : AppColors.slate600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// TOPUP DIALOG
// ════════════════════════════════════════════════════════════════════
class _TopupDialog extends ConsumerStatefulWidget {
  const _TopupDialog({required this.providers, required this.onDone});

  final List<String> providers;
  final VoidCallback onDone;

  @override
  ConsumerState<_TopupDialog> createState() => _TopupDialogState();
}

class _TopupDialogState extends ConsumerState<_TopupDialog> {
  static const _quick = [50000, 100000, 200000, 500000];
  final _amountCtrl = TextEditingController(text: '100000');
  late String _provider = widget.providers.first;
  bool _busy = false;
  bool _sent = false;
  String? _error;

  int get _amount => int.tryParse(_amountCtrl.text.trim()) ?? 0;
  bool get _valid => _amount >= 1000;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BillingRepository.instance
          .topup(amount: _amount, provider: _provider);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = ref.tt('common.error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ModalScaffold(
      title: ref.t('billing.topup.title'),
      child: _sent
          ? _SentBlock(
              message: '✅ ${ref.t('billing.sent.title')}',
              hint: ref.t('mobile.billing.topup.sentHint'),
              onClose: () {
                Navigator.of(context).pop();
                widget.onDone();
              },
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                InlineErrorBanner(message: _error),
                if (_error != null) const SizedBox(height: 12),
                Text(
                  ref.t('billing.topup.amount'),
                  style: const TextStyle(
                    color: AppColors.slate600,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    suffixText: ref.t('common.som'),
                    hintText: '100000',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.slate200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.slate200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.brand600, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q in _quick)
                      _AmountChip(
                        label: som(q),
                        selected: _amount == q,
                        onTap: _busy
                            ? null
                            : () {
                                _amountCtrl.text = q.toString();
                                setState(() {});
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  ref.t('billing.payment.method'),
                  style: const TextStyle(
                    color: AppColors.slate600,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _ProviderGrid(
                  providers: widget.providers,
                  selected: _provider,
                  onSelect: _busy
                      ? (_) {}
                      : (p) => setState(() => _provider = p),
                ),
                const SizedBox(height: 20),
                if (!_valid)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      ref.t('mobile.billing.topup.minHint'),
                      style: const TextStyle(
                          color: AppColors.slate400, fontSize: 12),
                    ),
                  ),
                GradientButton(
                  label: ref.t('billing.payment.pay'),
                  icon: Icons.lock_rounded,
                  busy: _busy,
                  onPressed: _valid ? _submit : null,
                ),
                const SizedBox(height: 8),
                Center(
                  child: GhostButton(
                    label: ref.t('action.cancel'),
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// PLAN DIALOG
// ════════════════════════════════════════════════════════════════════
class _PlanDialog extends ConsumerStatefulWidget {
  const _PlanDialog({
    required this.plan,
    required this.providers,
    required this.onDone,
  });

  final Plan plan;
  final List<String> providers;
  final VoidCallback onDone;

  @override
  ConsumerState<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends ConsumerState<_PlanDialog> {
  late String _provider = widget.providers.first;
  bool _busy = false;
  bool _done = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BillingRepository.instance
          .subscribe(planId: widget.plan.id, provider: _provider);
      if (!mounted) return;
      setState(() {
        _done = true;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = ref.tt('common.error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return _ModalScaffold(
      title: ref.t('mobile.billing.plan.formalizeTitle'),
      child: _done
          ? _SentBlock(
              message: '✅ ${ref.t('billing.sent.title')}',
              hint: ref.t('mobile.billing.plan.sentHint'),
              onClose: () {
                Navigator.of(context).pop();
                widget.onDone();
              },
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                InlineErrorBanner(message: _error),
                if (_error != null) const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.brand50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.brand200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.name,
                              style: const TextStyle(
                                color: AppColors.slate900,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ref.t('billing.plan.selected'),
                              style: const TextStyle(
                                color: AppColors.slate500,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _planPrice(plan, ref),
                        style: const TextStyle(
                          color: AppColors.brand700,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  ref.t('billing.payment.method'),
                  style: const TextStyle(
                    color: AppColors.slate600,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _ProviderGrid(
                  providers: widget.providers,
                  selected: _provider,
                  onSelect: _busy
                      ? (_) {}
                      : (p) => setState(() => _provider = p),
                ),
                const SizedBox(height: 20),
                GradientButton(
                  label: plan.price > 0
                      ? ref.t('mobile.billing.plan.payAndSwitch')
                      : ref.t('mobile.billing.plan.switchTo'),
                  icon: Icons.lock_rounded,
                  busy: _busy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 8),
                Center(
                  child: GhostButton(
                    label: ref.t('action.cancel'),
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// SHARED MODAL PIECES
// ════════════════════════════════════════════════════════════════════
class _ModalScaffold extends StatelessWidget {
  const _ModalScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.slate900,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.slate400),
                    splashRadius: 20,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SentBlock extends ConsumerWidget {
  const _SentBlock({
    required this.message,
    required this.hint,
    required this.onClose,
  });

  final String message;
  final String hint;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.brand50,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              color: AppColors.brand600, size: 34),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.slate900,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.slate500, fontSize: 13),
        ),
        const SizedBox(height: 20),
        GradientButton(label: ref.t('action.close'), onPressed: onClose),
      ],
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand600 : AppColors.slate50,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.brand600 : AppColors.slate200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.slate600,
          ),
        ),
      ),
    );
  }
}
