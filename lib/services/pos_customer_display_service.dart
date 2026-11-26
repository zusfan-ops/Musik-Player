import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/pos_models.dart';
import '../providers/pos_provider.dart';

class CustomerDisplayInfo {
  final int monitorCount;
  final bool hasSecondMonitor;
  final bool isOpen;
  final bool onSecondMonitor;

  const CustomerDisplayInfo({
    this.monitorCount = 1,
    this.hasSecondMonitor = false,
    this.isOpen = false,
    this.onSecondMonitor = false,
  });

  factory CustomerDisplayInfo.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const CustomerDisplayInfo();
    return CustomerDisplayInfo(
      monitorCount: (map['monitorCount'] as num?)?.toInt() ?? 1,
      hasSecondMonitor: map['hasSecondMonitor'] == true,
      isOpen: map['isOpen'] == true,
      onSecondMonitor: map['onSecondMonitor'] == true,
    );
  }
}

class PosCustomerDisplayService {
  PosCustomerDisplayService._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onCustomerDisplayClosed') {
        infoNotifier.value = CustomerDisplayInfo(
          monitorCount: infoNotifier.value.monitorCount,
          hasSecondMonitor: infoNotifier.value.hasSecondMonitor,
          isOpen: false,
          onSecondMonitor: false,
        );
      }
    });
  }

  static final PosCustomerDisplayService instance =
      PosCustomerDisplayService._();

  static const MethodChannel _channel =
      MethodChannel('com.musikm3u.player/customer_display');

  final ValueNotifier<CustomerDisplayInfo> infoNotifier =
      ValueNotifier<CustomerDisplayInfo>(const CustomerDisplayInfo());

  PosOrder? _lastPaidOrder;

  bool get isSupported => !kIsWeb && Platform.isWindows;

  Future<CustomerDisplayInfo> refreshDisplayInfo() async {
    if (!isSupported) return const CustomerDisplayInfo();
    try {
      final raw =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getDisplayInfo');
      final info = CustomerDisplayInfo.fromMap(raw);
      infoNotifier.value = info;
      return info;
    } catch (_) {
      return infoNotifier.value;
    }
  }

  Future<CustomerDisplayInfo> open() async {
    if (!isSupported) return const CustomerDisplayInfo();
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('openCustomerDisplay');
      final info = CustomerDisplayInfo.fromMap(raw);
      infoNotifier.value = info;
      return info;
    } catch (_) {
      return infoNotifier.value;
    }
  }

  Future<CustomerDisplayInfo> close() async {
    if (!isSupported) return const CustomerDisplayInfo();
    _lastPaidOrder = null;
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('closeCustomerDisplay');
      final info = CustomerDisplayInfo.fromMap(raw);
      infoNotifier.value = info;
      return info;
    } catch (_) {
      return infoNotifier.value;
    }
  }

  void setPaidOrder(PosOrder order) {
    _lastPaidOrder = order;
  }

  void clearPaidOrder() {
    _lastPaidOrder = null;
  }

  Future<void> syncFromProviders({
    required PosProvider pos,
    String? nowPlaying,
  }) async {
    if (!isSupported || !infoNotifier.value.isOpen) return;

    if (pos.cart.isNotEmpty) {
      _lastPaidOrder = null;
    }

    final paidOrder = _lastPaidOrder;
    final String status;
    final List<Map<String, dynamic>> items;
    final String subtotal;
    final String discount;
    final String tax;
    final String total;
    final String paidAmount;
    final String changeAmount;
    final String paymentMethod;
    final String customerName;

    if (paidOrder != null && pos.cart.isEmpty) {
      status = 'paid';
      items = paidOrder.items
          .map(
            (e) => <String, dynamic>{
              'name': e.productName,
              'quantity': e.quantity,
              'unitPrice': PosFormat.rupiah(e.unitPrice),
              'lineTotal': PosFormat.rupiah(e.lineTotal),
            },
          )
          .toList();
      subtotal = PosFormat.rupiah(paidOrder.subtotal);
      discount = PosFormat.rupiah(paidOrder.discountAmount);
      tax = PosFormat.rupiah(paidOrder.taxAmount);
      total = PosFormat.rupiah(paidOrder.total);
      paidAmount = PosFormat.rupiah(paidOrder.amountPaid);
      changeAmount = PosFormat.rupiah(paidOrder.changeAmount);
      paymentMethod = paidOrder.paymentMethod;
      customerName = paidOrder.customerName ?? 'Pelanggan Umum';
    } else {
      status = pos.cart.isEmpty ? 'idle' : 'active';
      items = pos.cart
          .map(
            (e) => <String, dynamic>{
              'name': e.product.name,
              'quantity': e.quantity,
              'unitPrice': PosFormat.rupiah(e.product.price),
              'lineTotal': PosFormat.rupiah(e.lineTotal),
            },
          )
          .toList();
      subtotal = PosFormat.rupiah(pos.cartSubtotal);
      discount = PosFormat.rupiah(pos.cartDiscount);
      tax = PosFormat.rupiah(pos.cartTax);
      total = PosFormat.rupiah(pos.cartTotal);
      paidAmount = 'Rp 0';
      changeAmount = 'Rp 0';
      paymentMethod = 'Tunai';
      customerName = pos.selectedCustomer?.name ?? 'Pelanggan Umum';
    }

    try {
      await _channel.invokeMethod('updateCustomerDisplay', <String, dynamic>{
        'storeName': pos.profile.storeName,
        'subtitle':
            '${pos.profile.businessType.label} • ${pos.profile.address}',
        'status': status,
        'customerName': customerName,
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'total': total,
        'paidAmount': paidAmount,
        'changeAmount': changeAmount,
        'paymentMethod': paymentMethod,
        'nowPlaying': nowPlaying ?? '',
        'items': items,
      });
    } catch (_) {}
  }
}
