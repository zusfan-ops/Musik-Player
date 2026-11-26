import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/finance_models.dart';
import '../models/pos_models.dart';

class FinanceProvider extends ChangeNotifier {
  static const String _kEntriesKey = 'finance_entries_v1';

  static const List<String> defaultIncomeCategories = [
    'Penjualan POS',
    'Penjualan Non-POS',
    'Modal Usaha',
    'Jasa / Layanan',
    'Piutang Masuk',
    'Lain-lain',
  ];

  static const List<String> defaultExpenseCategories = [
    'Belanja Bahan Baku',
    'Belanja Stok / Barang',
    'Operasional Toko',
    'Listrik, Air & Internet',
    'Gaji Karyawan',
    'Sewa & Perawatan',
    'Transportasi',
    'Pengeluaran Pribadi',
    'Lain-lain',
  ];

  static const List<String> paymentAccounts = [
    'Kas Tunai',
    'Rekening Bank',
    'QRIS / E-Wallet',
  ];

  SharedPreferences? _prefs;
  bool _initialized = false;
  List<FinanceEntry> _entries = [];

  bool get initialized => _initialized;
  List<FinanceEntry> get entries => List.unmodifiable(_entries);

  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _loadEntries();
    _initialized = true;
    notifyListeners();
  }

  void _loadEntries() {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final raw = prefs.getStringList(_kEntriesKey) ?? const [];
      _entries = raw
          .map(
            (s) => FinanceEntry.fromJson(jsonDecode(s) as Map<String, dynamic>),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    } catch (_) {
      _entries = [];
    }
  }

  Future<void> _persistEntries() async {
    await _prefs?.setStringList(
      _kEntriesKey,
      _entries.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> saveEntry(FinanceEntry entry) async {
    final idx = _entries.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      _entries[idx] = entry;
    } else {
      _entries.insert(0, entry);
    }
    _entries.sort((a, b) => b.date.compareTo(a.date));
    await _persistEntries();
    notifyListeners();
  }

  Future<void> deleteEntry(String entryId) async {
    _entries.removeWhere((e) => e.id == entryId);
    await _persistEntries();
    notifyListeners();
  }

  Future<void> recordPosOrder(PosOrder order) async {
    final entry = FinanceEntry.fromPosOrder(order);
    await saveEntry(entry);
  }

  /// Backfills any historical POS orders & expenses into the unified Finance ledger.
  Future<void> syncFromPos({
    required List<PosOrder> orders,
    required List<PosExpense> expenses,
  }) async {
    bool changed = false;
    final existingRefIds = _entries
        .map((e) => e.referenceId)
        .whereType<String>()
        .toSet();
    final existingIds = _entries.map((e) => e.id).toSet();

    for (final order in orders) {
      if (!existingRefIds.contains(order.id) &&
          !existingIds.contains('fin_pos_${order.id}')) {
        _entries.add(FinanceEntry.fromPosOrder(order));
        changed = true;
      }
    }

    for (final exp in expenses) {
      final finId = 'fin_posexp_${exp.id}';
      if (!existingRefIds.contains(exp.id) && !existingIds.contains(finId)) {
        _entries.add(
          FinanceEntry(
            id: finId,
            type: FinanceEntryType.expense,
            title: exp.title,
            category: exp.category,
            amount: exp.amount,
            paymentAccount: 'Kas Tunai',
            date: exp.createdAt,
            notes: 'Dari POS Pengeluaran',
            source: FinanceEntrySource.posOrder,
            referenceId: exp.id,
          ),
        );
        changed = true;
      }
    }

    if (changed) {
      _entries.sort((a, b) => b.date.compareTo(a.date));
      await _persistEntries();
      notifyListeners();
    }
  }

  bool _isInRange(DateTime dt, String rangeKey) {
    final now = DateTime.now();
    return switch (rangeKey) {
      'Hari Ini' =>
        dt.year == now.year && dt.month == now.month && dt.day == now.day,
      '7 Hari' => dt.isAfter(now.subtract(const Duration(days: 7))),
      '30 Hari' => dt.isAfter(now.subtract(const Duration(days: 30))),
      'Bulan Ini' => dt.year == now.year && dt.month == now.month,
      _ => true,
    };
  }

  List<FinanceEntry> filterEntries({
    required String rangeKey,
    FinanceEntryType? typeFilter,
    String accountFilter = 'Semua',
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    return _entries.where((e) {
      if (!_isInRange(e.date, rangeKey)) return false;
      if (typeFilter != null && e.type != typeFilter) return false;
      if (accountFilter != 'Semua' && e.paymentAccount != accountFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        final match = e.title.toLowerCase().contains(q) ||
            e.category.toLowerCase().contains(q) ||
            e.notes.toLowerCase().contains(q);
        if (!match) return false;
      }
      return true;
    }).toList();
  }

  FinanceSummary summaryForRange(
    String rangeKey, {
    String accountFilter = 'Semua',
  }) {
    final list = filterEntries(
      rangeKey: rangeKey,
      accountFilter: accountFilter,
    );
    double income = 0;
    double expense = 0;
    double posIncome = 0;
    double manualIncome = 0;

    for (final e in list) {
      if (e.isIncome) {
        income += e.amount;
        if (e.isFromPos) {
          posIncome += e.amount;
        } else {
          manualIncome += e.amount;
        }
      } else {
        expense += e.amount;
      }
    }

    return FinanceSummary(
      totalIncome: income,
      totalExpense: expense,
      netBalance: income - expense,
      posIncome: posIncome,
      manualIncome: manualIncome,
      entryCount: list.length,
    );
  }

  Map<String, double> categoryBreakdown(
    String rangeKey, {
    required FinanceEntryType type,
  }) {
    final Map<String, double> map = {};
    for (final e in filterEntries(rangeKey: rangeKey, typeFilter: type)) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return map;
  }

  Map<String, double> accountBalances(String rangeKey) {
    final Map<String, double> map = {
      for (final a in paymentAccounts) a: 0.0,
    };
    for (final e in filterEntries(rangeKey: rangeKey)) {
      final delta = e.isIncome ? e.amount : -e.amount;
      map[e.paymentAccount] = (map[e.paymentAccount] ?? 0) + delta;
    }
    return map;
  }
}
