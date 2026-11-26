import 'dart:io';

import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/finance_models.dart';
import '../models/pos_models.dart';

class FinancePdfService {
  static Future<File> exportDetailedFinancePdf({
    required String storeName,
    required String rangeLabel,
    required FinanceSummary summary,
    required Map<String, double> accountBalances,
    required Map<String, double> incomeCategories,
    required Map<String, double> expenseCategories,
    required List<FinanceEntry> entries,
    bool openAfterSave = true,
    bool shareAfterSave = false,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(26),
        build: (ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    storeName,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Laporan Keuangan Detail & Buku Kas Terintegrasi POS',
                    style: const pw.TextStyle(fontSize: 10.5),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Periode: $rangeLabel',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Dicetak: ${PosFormat.dateTime(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Text(
            'RINGKASAN ARUS KAS',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Keterangan', 'Jumlah'],
            data: [
              ['Total Pemasukan (${summary.entryCount} catatan)', PosFormat.rupiah(summary.totalIncome)],
              ['  - Pemasukan dari POS', PosFormat.rupiah(summary.posIncome)],
              ['  - Pemasukan Non-POS / Manual', PosFormat.rupiah(summary.manualIncome)],
              ['Total Pengeluaran / Belanja', PosFormat.rupiah(summary.totalExpense)],
              ['Saldo / Arus Kas Bersih', PosFormat.rupiah(summary.netBalance)],
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'SALDO PER AKUN / DOMPET',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Akun / Dompet', 'Arus Kas Bersih'],
            data: accountBalances.entries
                .map((e) => [e.key, PosFormat.rupiah(e.value)])
                .toList(),
          ),
          if (incomeCategories.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              'REKAP PEMASUKAN PER KATEGORI',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Kategori', 'Total'],
              data: incomeCategories.entries
                  .map((e) => [e.key, PosFormat.rupiah(e.value)])
                  .toList(),
            ),
          ],
          if (expenseCategories.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              'REKAP PENGELUARAN / BELANJA PER KATEGORI',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Kategori', 'Total'],
              data: expenseCategories.entries
                  .map((e) => [e.key, PosFormat.rupiah(e.value)])
                  .toList(),
            ),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            'BUKU KAS DETAIL (${entries.length} TRANSAKSI)',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (entries.isEmpty)
            pw.Text('Tidak ada transaksi pada periode ini.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Tanggal', 'Jenis', 'Kategori', 'Keterangan', 'Akun', 'Jumlah'],
              data: entries
                  .take(100)
                  .map(
                    (e) => [
                      PosFormat.dateTime(e.date),
                      e.type.label,
                      e.category,
                      e.notes.isNotEmpty ? '${e.title}\n(${e.notes})' : e.title,
                      e.paymentAccount,
                      '${e.isIncome ? '+' : '-'}${PosFormat.rupiah(e.amount)}',
                    ],
                  )
                  .toList(),
            ),
        ],
      ),
    );

    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'MediaCenterFinance'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File(p.join(dir.path, 'Laporan_Keuangan_Detail_$ts.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);

    if (shareAfterSave) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Laporan Keuangan $storeName ($rangeLabel)',
          subject: 'Laporan Keuangan $storeName',
        ),
      );
    } else if (openAfterSave) {
      await OpenFile.open(file.path);
    }
    return file;
  }
}
