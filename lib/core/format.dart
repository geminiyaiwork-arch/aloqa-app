/// ALOQA — formatting helpers (ported 1:1 from web: som / dates / tariff /
/// provider + status maps). No intl locale init needed — Uzbek month names and
/// digit grouping are done manually so DateFormat('uz') never throws at runtime.
library;

import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

const _uzMonths = [
  'yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun',
  'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr',
];

/// Group an integer with spaces every 3 digits (uz style): 100000 -> "100 000".
String _grouped(int v) {
  final neg = v < 0;
  final s = v.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return (neg ? '-' : '') + buf.toString();
}

/// "150 000 so'm"
String som(num value) => "${_grouped(value.round())} so'm";

String _pad2(int n) => n.toString().padLeft(2, '0');

/// "05 iyun 2026"
String fmtDate(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${_pad2(l.day)} ${_uzMonths[l.month - 1]} ${l.year}';
}

/// "05 iyun 2026, 14:30"
String fmtDateTime(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${fmtDate(l)}, ${_pad2(l.hour)}:${_pad2(l.minute)}';
}

/// "14:30"
String fmtTime(DateTime d) {
  final l = d.toLocal();
  return '${_pad2(l.hour)}:${_pad2(l.minute)}';
}

/// Payment provider display label.
String providerLabel(String p) {
  switch (p.toLowerCase()) {
    case 'click':
      return 'Click';
    case 'payme':
      return 'Payme';
    case 'uzum':
      return 'Uzum';
    case 'card':
      return 'Karta';
    default:
      return p.isEmpty ? '—' : p;
  }
}

/// Transaction status → (uzbek label, color). Mirrors web TX_STATUS.
({String label, Color color}) txStatusStyle(String status) {
  switch (status.toLowerCase()) {
    case 'received':
    case 'success':
    case 'done':
      return (label: 'Qabul qilindi', color: AppColors.brand600);
    case 'pending':
    case 'processing':
      return (label: 'Kutilmoqda', color: const Color(0xFFD97706)); // amber-600
    case 'failed':
    case 'error':
      return (label: 'Xatolik', color: AppColors.danger);
    default:
      return (label: status.isEmpty ? '—' : status, color: AppColors.slate500);
  }
}

/// Meeting status → (uzbek label, color). Mirrors web STATUS.
({String label, Color color}) meetingStatusStyle(String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'live':
      return (label: 'Jonli', color: AppColors.brand600);
    case 'scheduled':
    case 'waiting':
      return (label: 'Rejalashtirilgan', color: const Color(0xFF2563EB)); // blue-600
    case 'ended':
      return (label: 'Tugagan', color: AppColors.slate500);
    case 'cancelled':
      return (label: 'Bekor qilingan', color: AppColors.danger);
    default:
      return (label: status?.isNotEmpty == true ? status! : 'Tezkor',
          color: AppColors.slate500);
  }
}
