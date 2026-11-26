import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/pos_models.dart';

class PairedBluetoothPrinter {
  final String name;
  final String address;

  const PairedBluetoothPrinter({
    required this.name,
    required this.address,
  });
}

class PosBluetoothPrinterService {
  static const MethodChannel _channel =
      MethodChannel('com.musikm3u.player/media_store');

  static Future<bool> ensureBluetoothPermissions() async {
    if (!Platform.isAndroid) return false;
    try {
      final connect = await Permission.bluetoothConnect.request();
      final scan = await Permission.bluetoothScan.request();
      if (connect.isGranted || scan.isGranted) return true;
      final legacy = await Permission.bluetooth.status;
      return legacy.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<List<PairedBluetoothPrinter>> listPairedPrinters() async {
    if (!Platform.isAndroid) return const [];
    await ensureBluetoothPermissions();
    final raw =
        await _channel.invokeMethod<List<dynamic>>('listPairedBluetoothPrinters');
    if (raw == null) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (m) => PairedBluetoothPrinter(
            name: m['name']?.toString() ?? 'Bluetooth Printer',
            address: m['address']?.toString() ?? '',
          ),
        )
        .where((p) => p.address.isNotEmpty)
        .toList();
  }

  static String _lr(String left, String right, {int width = 32}) {
    final l = left.length > width - 2 ? left.substring(0, width - 2) : left;
    final spaces = (width - l.length - right.length).clamp(1, width);
    return '$l${' ' * spaces}$right';
  }

  /// Generates 58mm ESC/POS thermal receipt bytes.
  static Uint8List buildEscPosReceipt(
    PosOrder order,
    PosBusinessProfile profile, {
    int lineWidth = 32,
  }) {
    final List<int> bytes = [];
    void addText(String text) {
      bytes.addAll(latin1.encode('$text\n'));
    }

    // ESC @ (Init printer)
    bytes.addAll([0x1B, 0x40]);
    // Center align + Bold + Double Height for Store Name
    bytes.addAll([0x1B, 0x61, 0x01]);
    bytes.addAll([0x1B, 0x45, 0x01]);
    addText(profile.storeName);
    bytes.addAll([0x1B, 0x45, 0x00]);
    if (profile.address.trim().isNotEmpty) addText(profile.address);
    if (profile.phone.trim().isNotEmpty) addText('Tel: ${profile.phone}');
    addText('-' * lineWidth);

    // Left align metadata
    bytes.addAll([0x1B, 0x61, 0x00]);
    addText('No   : ${order.receiptNumber}');
    addText('Tgl  : ${PosFormat.dateTime(order.createdAt)}');
    if (order.customerName != null && order.customerName!.isNotEmpty) {
      addText('Plg  : ${order.customerName}');
    }
    addText('Bayar: ${order.paymentMethod}');
    addText('-' * lineWidth);

    for (final item in order.items) {
      addText(item.productName);
      addText(
        _lr(
          '${item.quantity}x ${PosFormat.rupiah(item.unitPrice)}',
          PosFormat.rupiah(item.lineTotal),
          width: lineWidth,
        ),
      );
    }
    addText('-' * lineWidth);

    addText(_lr('Subtotal', PosFormat.rupiah(order.subtotal), width: lineWidth));
    if (order.discountAmount > 0) {
      addText(
        _lr(
          'Diskon',
          '-${PosFormat.rupiah(order.discountAmount)}',
          width: lineWidth,
        ),
      );
    }
    if (order.taxAmount > 0) {
      addText(_lr('Pajak', PosFormat.rupiah(order.taxAmount), width: lineWidth));
    }

    bytes.addAll([0x1B, 0x45, 0x01]);
    addText(_lr('TOTAL', PosFormat.rupiah(order.total), width: lineWidth));
    bytes.addAll([0x1B, 0x45, 0x00]);

    addText(_lr('Bayar', PosFormat.rupiah(order.amountPaid), width: lineWidth));
    if (order.changeAmount > 0) {
      addText(
        _lr('Kembali', PosFormat.rupiah(order.changeAmount), width: lineWidth),
      );
    }

    addText('-' * lineWidth);
    bytes.addAll([0x1B, 0x61, 0x01]);
    addText(profile.receiptFooter);
    addText('');
    addText('');
    // Feed & Cut
    bytes.addAll([0x1D, 0x56, 0x41, 0x10]);

    return Uint8List.fromList(bytes);
  }

  static Future<bool> printReceipt({
    required String address,
    required PosOrder order,
    required PosBusinessProfile profile,
  }) async {
    if (!Platform.isAndroid) return false;
    await ensureBluetoothPermissions();
    final escPosBytes = buildEscPosReceipt(order, profile);
    final ok = await _channel.invokeMethod<bool>('printEscPosBytes', {
      'address': address,
      'bytes': escPosBytes,
    });
    return ok == true;
  }

  /// Prints ESC/POS thermal receipt directly to a LAN/Wi-Fi printer (port 9100), ideal for Windows Desktop POS.
  static Future<bool> printReceiptTcp({
    required String host,
    int port = 9100,
    required PosOrder order,
    required PosBusinessProfile profile,
  }) async {
    final socket = await Socket.connect(
      host.trim(),
      port,
      timeout: const Duration(seconds: 5),
    );
    try {
      final escPosBytes = buildEscPosReceipt(order, profile);
      socket.add(escPosBytes);
      await socket.flush();
      return true;
    } finally {
      await socket.close();
    }
  }
}
