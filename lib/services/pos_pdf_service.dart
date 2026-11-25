import 'dart:io';

import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/pos_models.dart';

class PosPdfService {
  static Future<Directory> _getExportDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'MediaCenterPOS'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Generates an 80mm thermal-style PDF receipt for [order].
  static Future<File> generateReceiptPdf(
    PosOrder order,
    PosBusinessProfile profile,
  ) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(14),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                profile.storeName,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            if (profile.address.trim().isNotEmpty)
              pw.Center(
                child: pw.Text(
                  profile.address,
                  style: const pw.TextStyle(fontSize: 8.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            if (profile.phone.trim().isNotEmpty)
              pw.Center(
                child: pw.Text(
                  'Tel: ${profile.phone}',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
              ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.8),
            pw.Text('No Nota : ${order.receiptNumber}',
                style: const pw.TextStyle(fontSize: 8.5)),
            pw.Text('Tanggal : ${PosFormat.dateTime(order.createdAt)}',
                style: const pw.TextStyle(fontSize: 8.5)),
            if (order.customerName != null && order.customerName!.isNotEmpty)
              pw.Text('Pelanggan: ${order.customerName}',
                  style: const pw.TextStyle(fontSize: 8.5)),
            pw.Text('Bayar   : ${order.paymentMethod}',
                style: const pw.TextStyle(fontSize: 8.5)),
            pw.Divider(thickness: 0.8),
            for (final item in order.items) ...[
              pw.Text(
                item.productName,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${item.quantity} ${item.unit} x ${PosFormat.rupiah(item.unitPrice)}',
                    style: const pw.TextStyle(fontSize: 8.5),
                  ),
                  pw.Text(
                    PosFormat.rupiah(item.lineTotal),
                    style: const pw.TextStyle(fontSize: 8.5),
                  ),
                ],
              ),
              pw.SizedBox(height: 3),
            ],
            pw.Divider(thickness: 0.8),
            _pdfRow('Subtotal', PosFormat.rupiah(order.subtotal)),
            if (order.discountAmount > 0)
              _pdfRow('Diskon', '-${PosFormat.rupiah(order.discountAmount)}'),
            if (order.taxAmount > 0)
              _pdfRow('Pajak', PosFormat.rupiah(order.taxAmount)),
            pw.SizedBox(height: 3),
            _pdfRow(
              'TOTAL',
              PosFormat.rupiah(order.total),
              bold: true,
              fontSize: 10.5,
            ),
            _pdfRow('Bayar', PosFormat.rupiah(order.amountPaid)),
            if (order.changeAmount > 0)
              _pdfRow('Kembali', PosFormat.rupiah(order.changeAmount)),
            pw.Divider(thickness: 0.8),
            pw.Center(
              child: pw.Text(
                profile.receiptFooter,
                style: const pw.TextStyle(fontSize: 8.5),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );

    final dir = await _getExportDir();
    final file = File(p.join(dir.path, '${order.receiptNumber}.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  static pw.Widget _pdfRow(
    String left,
    String right, {
    bool bold = false,
    double fontSize = 9,
  }) {
    final style = pw.TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(left, style: style),
        pw.Text(right, style: style),
      ],
    );
  }

  /// Shares the PDF receipt (can be sent directly to WhatsApp / any messaging app).
  static Future<void> shareReceiptPdf(
    PosOrder order,
    PosBusinessProfile profile,
  ) async {
    final file = await generateReceiptPdf(order, profile);
    final summaryText =
        'Nota ${profile.storeName}\nNo: ${order.receiptNumber}\nTotal: ${PosFormat.rupiah(order.total)}\n${profile.receiptFooter}';
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: summaryText,
        subject: 'Nota ${order.receiptNumber}',
      ),
    );
  }

  /// Generates an A4 Financial Report PDF and opens/shares it.
  static Future<File> exportFinancialReportPdf({
    required PosBusinessProfile profile,
    required String rangeLabel,
    required PosFinancialSummary summary,
    required List<({String name, int qty, double revenue})> topProducts,
    required List<PosOrder> orders,
    required List<PosExpense> expenses,
    bool openAfterSave = true,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    profile.storeName,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Laporan Keuangan & Analitik Penjualan (${profile.businessType.label})',
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
          pw.SizedBox(height: 14),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Text(
            'RINGKASAN LABA & RUGI',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['Keterangan', 'Nilai'],
            data: [
              ['Total Omzet Penjualan (${summary.transactionCount} trx)', PosFormat.rupiah(summary.totalRevenue)],
              ['Harga Pokok Penjualan (HPP / Modal)', PosFormat.rupiah(summary.totalCost)],
              ['Laba Kotor', PosFormat.rupiah(summary.grossProfit)],
              ['Total Pengeluaran Operasional', PosFormat.rupiah(summary.totalExpenses)],
              ['Laba Bersih', PosFormat.rupiah(summary.netProfit)],
              ['Pajak Terkumpul', PosFormat.rupiah(summary.taxCollected)],
              ['Total Diskon Diberikan', PosFormat.rupiah(summary.discountTotal)],
              ['Rata-rata Transaksi', PosFormat.rupiah(summary.averageOrder)],
            ],
          ),
          pw.SizedBox(height: 16),
          if (topProducts.isNotEmpty) ...[
            pw.Text(
              'PRODUK TERLARIS',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Produk', 'Qty Terjual', 'Total Penjualan'],
              data: topProducts
                  .map(
                    (p) => [
                      p.name,
                      '${p.qty}',
                      PosFormat.rupiah(p.revenue),
                    ],
                  )
                  .toList(),
            ),
            pw.SizedBox(height: 16),
          ],
          if (expenses.isNotEmpty) ...[
            pw.Text(
              'CATATAN PENGELUARAN',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Tanggal', 'Keterangan', 'Kategori', 'Jumlah'],
              data: expenses
                  .map(
                    (e) => [
                      PosFormat.dateOnly(e.createdAt),
                      e.title,
                      e.category,
                      PosFormat.rupiah(e.amount),
                    ],
                  )
                  .toList(),
            ),
            pw.SizedBox(height: 16),
          ],
          if (orders.isNotEmpty) ...[
            pw.Text(
              'RIWAYAT TRANSAKSI (${orders.length})',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['No Nota', 'Tanggal', 'Pelanggan', 'Metode', 'Total'],
              data: orders
                  .take(50)
                  .map(
                    (o) => [
                      o.receiptNumber,
                      PosFormat.dateTime(o.createdAt),
                      o.customerName ?? 'Umum',
                      o.paymentMethod,
                      PosFormat.rupiah(o.total),
                    ],
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );

    final dir = await _getExportDir();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File(p.join(dir.path, 'Laporan_Keuangan_$ts.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    if (openAfterSave) {
      await OpenFile.open(file.path);
    }
    return file;
  }
}
