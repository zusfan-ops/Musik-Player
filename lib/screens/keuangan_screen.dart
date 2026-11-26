import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/finance_models.dart';
import '../models/pos_models.dart';
import '../providers/finance_provider.dart';
import '../providers/pos_provider.dart';
import '../services/finance_pdf_service.dart';
import '../theme/app_theme.dart';

class KeuanganScreen extends StatefulWidget {
  const KeuanganScreen({super.key});

  static void show(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const KeuanganScreen()),
    );
  }

  @override
  State<KeuanganScreen> createState() => _KeuanganScreenState();
}

class _KeuanganScreenState extends State<KeuanganScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  String _range = 'Bulan Ini';
  FinanceEntryType? _typeFilter;
  String _accountFilter = 'Semua';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pos = context.read<PosProvider>();
      final fin = context.read<FinanceProvider>();
      unawaited(fin.syncFromPos(orders: pos.orders, expenses: pos.expenses));
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fin = context.watch<FinanceProvider>();
    final pos = context.watch<PosProvider>();

    final summary = fin.summaryForRange(_range, accountFilter: _accountFilter);
    final entries = fin.filterEntries(
      rangeKey: _range,
      typeFilter: _typeFilter,
      accountFilter: _accountFilter,
      query: _searchQuery,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Keuangan & Buku Kas',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            Text(
              'Pencatatan Belanja, Pemasukan & Terintegrasi POS',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sinkronkan Transaksi POS',
            icon: const Icon(Icons.sync_rounded),
            onPressed: () async {
              await fin.syncFromPos(orders: pos.orders, expenses: pos.expenses);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Transaksi POS disinkronkan ke Buku Kas!'),
                  ),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Export Laporan Keuangan PDF',
            icon: const Icon(Icons.picture_as_pdf_rounded),
            onPressed: () => _exportPdf(context, fin, pos, summary, entries),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.spotifyGreen,
          labelColor: AppColors.spotifyGreen,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: 'Buku Kas'),
            Tab(icon: Icon(Icons.pie_chart_rounded, size: 18), text: 'Rekap'),
            Tab(icon: Icon(Icons.picture_as_pdf_rounded, size: 18), text: 'Laporan'),
          ],
        ),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'fin_add_expense',
            backgroundColor: AppColors.netflixRed,
            foregroundColor: Colors.white,
            onPressed: () => _showEntryDialog(
              context,
              fin,
              initialType: FinanceEntryType.expense,
            ),
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 19),
            label: const Text('Pengeluaran'),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.extended(
            heroTag: 'fin_add_income',
            backgroundColor: AppColors.spotifyGreen,
            foregroundColor: Colors.white,
            onPressed: () => _showEntryDialog(
              context,
              fin,
              initialType: FinanceEntryType.income,
            ),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
            label: const Text('Pemasukan'),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildLedgerTab(context, fin, summary, entries),
          _buildBreakdownTab(fin),
          _buildPdfReportTab(context, fin, pos, summary, entries),
        ],
      ),
    );
  }

  Widget _buildLedgerTab(
    BuildContext context,
    FinanceProvider fin,
    FinanceSummary summary,
    List<FinanceEntry> entries,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
      children: [
        // Summary Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkNav,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SALDO ARUS KAS ($_range)',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                    ),
                  ),
                  Text(
                    '${summary.entryCount} catatan',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                PosFormat.rupiah(summary.netBalance),
                style: TextStyle(
                  color: summary.netBalance >= 0
                      ? Colors.white
                      : const Color(0xFFFF8A75),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pemasukan',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            PosFormat.rupiah(summary.totalIncome),
                            style: const TextStyle(
                              color: Color(0xFF7CE0A3),
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                            ),
                          ),
                          Text(
                            'POS: ${PosFormat.rupiah(summary.posIncome)}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pengeluaran / Belanja',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            PosFormat.rupiah(summary.totalExpense),
                            style: const TextStyle(
                              color: Color(0xFFFF9B88),
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                            ),
                          ),
                          Text(
                            'Manual: ${PosFormat.rupiah(summary.manualIncome)}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Search
        TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: 'Cari catatan keuangan, kategori, atau keterangan...',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: AppColors.surfaceElevated,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Period Filter
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final r in const [
                'Hari Ini',
                '7 Hari',
                '30 Hari',
                'Bulan Ini',
                'Semua',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(r, style: const TextStyle(fontSize: 11.5)),
                    selected: _range == r,
                    onSelected: (_) => setState(() => _range = r),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Type & Account filters
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in const [
                (null, 'Semua Jenis'),
                (FinanceEntryType.income, 'Pemasukan'),
                (FinanceEntryType.expense, 'Pengeluaran'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t.$2, style: const TextStyle(fontSize: 11)),
                    selected: _typeFilter == t.$1,
                    onSelected: (_) => setState(() => _typeFilter = t.$1),
                  ),
                ),
              for (final acc in [
                'Semua',
                ...FinanceProvider.paymentAccounts,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      acc == 'Semua' ? 'Semua Akun' : acc,
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: _accountFilter == acc,
                    onSelected: (_) => setState(() => _accountFilter = acc),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        if (entries.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'Belum ada catatan keuangan pada filter ini.\nKetuk tombol + Pemasukan atau - Pengeluaran di bawah.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else
          for (final entry in entries)
            Card(
              color: AppColors.surfaceElevated,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: entry.isIncome
                      ? const Color(0xFF1D8F52).withValues(alpha: 0.14)
                      : AppColors.netflixRed.withValues(alpha: 0.14),
                  child: Icon(
                    entry.isIncome
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: entry.isIncome
                        ? const Color(0xFF1D8F52)
                        : AppColors.netflixRed,
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    if (entry.isFromPos)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.spotifyGreen.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'POS',
                          style: TextStyle(
                            color: AppColors.spotifyGreen,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: Text(
                  '${entry.category} • ${entry.paymentAccount} • ${PosFormat.dateTime(entry.date)}${entry.notes.isNotEmpty ? '\n${entry.notes}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${entry.isIncome ? '+' : '-'}${PosFormat.rupiah(entry.amount)}',
                      style: TextStyle(
                        color: entry.isIncome
                            ? const Color(0xFF1D8F52)
                            : AppColors.netflixRed,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: () => fin.deleteEntry(entry.id),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                onTap: () => _showEntryDialog(
                  context,
                  fin,
                  initialType: entry.type,
                  existing: entry,
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildBreakdownTab(FinanceProvider fin) {
    final balances = fin.accountBalances(_range);
    final incCats = fin.categoryBreakdown(_range, type: FinanceEntryType.income);
    final expCats = fin.categoryBreakdown(_range, type: FinanceEntryType.expense);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
      children: [
        const Text(
          'Arus Kas per Akun / Dompet',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 8),
        for (final acc in balances.entries)
          Card(
            color: AppColors.surfaceElevated,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(
                Icons.account_balance_wallet_rounded,
                color: AppColors.neonCyan,
              ),
              title: Text(
                acc.key,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              trailing: Text(
                PosFormat.rupiah(acc.value),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: acc.value >= 0
                      ? const Color(0xFF1D8F52)
                      : AppColors.netflixRed,
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),
        const Text(
          'Pemasukan per Kategori',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 8),
        if (incCats.isEmpty)
          const Text(
            'Belum ada pemasukan pada periode ini.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          )
        else
          for (final e in incCats.entries)
            Card(
              color: AppColors.surfaceElevated,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(
                  e.key,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: Text(
                  PosFormat.rupiah(e.value),
                  style: const TextStyle(
                    color: Color(0xFF1D8F52),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        const SizedBox(height: 14),
        const Text(
          'Pengeluaran / Belanja per Kategori',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 8),
        if (expCats.isEmpty)
          const Text(
            'Belum ada pengeluaran pada periode ini.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          )
        else
          for (final e in expCats.entries)
            Card(
              color: AppColors.surfaceElevated,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(
                  e.key,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: Text(
                  PosFormat.rupiah(e.value),
                  style: const TextStyle(
                    color: AppColors.netflixRed,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildPdfReportTab(
    BuildContext context,
    FinanceProvider fin,
    PosProvider pos,
    FinanceSummary summary,
    List<FinanceEntry> entries,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Export Laporan Keuangan Detail (PDF)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Periode aktif: $_range • ${entries.length} transaksi\nMencakup ringkasan arus kas, pemasukan POS & manual, rekap kategori, saldo dompet, serta tabel buku kas lengkap.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.darkNav,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () =>
                          _exportPdf(context, fin, pos, summary, entries),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text(
                        'Buka Laporan PDF',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.spotifyGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () => _exportPdf(
                        context,
                        fin,
                        pos,
                        summary,
                        entries,
                        share: true,
                      ),
                      icon: const Icon(Icons.share_rounded),
                      label: const Text(
                        'Kirim WA / Share',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _exportPdf(
    BuildContext context,
    FinanceProvider fin,
    PosProvider pos,
    FinanceSummary summary,
    List<FinanceEntry> entries, {
    bool share = false,
  }) async {
    final file = await FinancePdfService.exportDetailedFinancePdf(
      storeName: pos.profile.storeName,
      rangeLabel: _range,
      summary: summary,
      accountBalances: fin.accountBalances(_range),
      incomeCategories:
          fin.categoryBreakdown(_range, type: FinanceEntryType.income),
      expenseCategories:
          fin.categoryBreakdown(_range, type: FinanceEntryType.expense),
      entries: entries,
      openAfterSave: !share,
      shareAfterSave: share,
    );
    if (context.mounted && !share) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF tersimpan: ${file.path}')),
      );
    }
  }

  Future<void> _showEntryDialog(
    BuildContext context,
    FinanceProvider fin, {
    required FinanceEntryType initialType,
    FinanceEntry? existing,
  }) async {
    FinanceEntryType type = existing?.type ?? initialType;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final amountCtrl = TextEditingController(
      text: existing != null ? existing.amount.round().toString() : '',
    );
    final customCatCtrl =
        TextEditingController(text: existing?.category ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String selectedAccount =
        existing?.paymentAccount ?? FinanceProvider.paymentAccounts.first;
    DateTime selectedDate = existing?.date ?? DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setDState) {
          final presetCats = type == FinanceEntryType.income
              ? FinanceProvider.defaultIncomeCategories
              : FinanceProvider.defaultExpenseCategories;
          if (customCatCtrl.text.trim().isEmpty) {
            customCatCtrl.text = presetCats.first;
          }
          return AlertDialog(
            title: Text(
              existing == null ? 'Catat Keuangan' : 'Edit Catatan Keuangan',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<FinanceEntryType>(
                    segments: const [
                      ButtonSegment(
                        value: FinanceEntryType.expense,
                        label: Text('Pengeluaran'),
                        icon: Icon(Icons.arrow_upward_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: FinanceEntryType.income,
                        label: Text('Pemasukan'),
                        icon: Icon(Icons.arrow_downward_rounded, size: 16),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) {
                      setDState(() {
                        type = s.first;
                        customCatCtrl.text = (type == FinanceEntryType.income
                                ? FinanceProvider.defaultIncomeCategories
                                : FinanceProvider.defaultExpenseCategories)
                            .first;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Judul / Keterangan Belanja atau Pemasukan',
                    ),
                  ),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pilih Kategori (atau ketik kustom)',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final cat in presetCats)
                        ChoiceChip(
                          label: Text(cat, style: const TextStyle(fontSize: 11)),
                          selected: customCatCtrl.text.trim() == cat,
                          onSelected: (_) =>
                              setDState(() => customCatCtrl.text = cat),
                        ),
                    ],
                  ),
                  TextField(
                    controller: customCatCtrl,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: FinanceProvider.paymentAccounts
                            .contains(selectedAccount)
                        ? selectedAccount
                        : FinanceProvider.paymentAccounts.first,
                    decoration: const InputDecoration(labelText: 'Akun / Dompet'),
                    items: [
                      for (final acc in FinanceProvider.paymentAccounts)
                        DropdownMenuItem(value: acc, child: Text(acc)),
                    ],
                    onChanged: (v) {
                      if (v != null) setDState(() => selectedAccount = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null && ctx.mounted) {
                        setDState(() {
                          selectedDate = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            selectedDate.hour,
                            selectedDate.minute,
                          );
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Tanggal'),
                      child: Text(PosFormat.dateOnly(selectedDate)),
                    ),
                  ),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Catatan Detail (Opsional)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('Batal'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.spotifyGreen,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                  if (title.isEmpty || amount <= 0) return;
                  final entry = FinanceEntry(
                    id: existing?.id ??
                        'fin_${DateTime.now().microsecondsSinceEpoch}',
                    type: type,
                    title: title,
                    category: customCatCtrl.text.trim().isEmpty
                        ? 'Umum'
                        : customCatCtrl.text.trim(),
                    amount: amount,
                    paymentAccount: selectedAccount,
                    date: selectedDate,
                    notes: notesCtrl.text.trim(),
                    source: existing?.source ?? FinanceEntrySource.manual,
                    referenceId: existing?.referenceId,
                  );
                  await fin.saveEntry(entry);
                  if (dCtx.mounted) Navigator.pop(dCtx);
                },
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
    titleCtrl.dispose();
    amountCtrl.dispose();
    customCatCtrl.dispose();
    notesCtrl.dispose();
  }
}
