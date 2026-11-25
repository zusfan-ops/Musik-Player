import 'dart:convert';
import 'dart:io';

enum PosBusinessType {
  coffeeshop,
  roastery,
  general,
}

extension PosBusinessTypeExt on PosBusinessType {
  String get label => switch (this) {
        PosBusinessType.coffeeshop => 'Coffeeshop',
        PosBusinessType.roastery => 'Roastery',
        PosBusinessType.general => 'Produk Umum',
      };
}

class PosFormat {
  static String rupiah(num value) {
    final rounded = value.round();
    final negative = rounded < 0;
    final digits = rounded.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final posFromEnd = digits.length - i;
      if (i > 0 && posFromEnd % 3 == 0) {
        buf.write('.');
      }
      buf.write(digits[i]);
    }
    return '${negative ? '-' : ''}Rp ${buf.toString()}';
  }

  static String dateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  static String dateOnly(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }
}

class PosBusinessProfile {
  final String storeName;
  final PosBusinessType businessType;
  final String address;
  final String phone;
  final double taxPercent;
  final String receiptFooter;

  const PosBusinessProfile({
    this.storeName = 'MediaCenter Cafe & Store',
    this.businessType = PosBusinessType.coffeeshop,
    this.address = 'Jl. Utama No. 1, Indonesia',
    this.phone = '0812-0000-0000',
    this.taxPercent = 0.0,
    this.receiptFooter = 'Terima kasih sudah berbelanja!',
  });

  PosBusinessProfile copyWith({
    String? storeName,
    PosBusinessType? businessType,
    String? address,
    String? phone,
    double? taxPercent,
    String? receiptFooter,
  }) {
    return PosBusinessProfile(
      storeName: storeName ?? this.storeName,
      businessType: businessType ?? this.businessType,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      taxPercent: taxPercent ?? this.taxPercent,
      receiptFooter: receiptFooter ?? this.receiptFooter,
    );
  }

  Map<String, dynamic> toJson() => {
        'storeName': storeName,
        'businessType': businessType.name,
        'address': address,
        'phone': phone,
        'taxPercent': taxPercent,
        'receiptFooter': receiptFooter,
      };

  factory PosBusinessProfile.fromJson(Map<String, dynamic> json) {
    final typeName = json['businessType']?.toString() ?? 'coffeeshop';
    final bType = PosBusinessType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => PosBusinessType.coffeeshop,
    );
    return PosBusinessProfile(
      storeName: json['storeName']?.toString() ?? 'MediaCenter Cafe & Store',
      businessType: bType,
      address: json['address']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      taxPercent: (json['taxPercent'] as num?)?.toDouble() ?? 0.0,
      receiptFooter:
          json['receiptFooter']?.toString() ?? 'Terima kasih sudah berbelanja!',
    );
  }
}

class PosProduct {
  final String id;
  final String name;
  final String sku;
  final String category;
  final double price;
  final double costPrice;
  final int stock;
  final String unit;
  final String? imagePath;
  final bool isActive;

  const PosProduct({
    required this.id,
    required this.name,
    this.sku = '',
    required this.category,
    required this.price,
    this.costPrice = 0,
    this.stock = 50,
    this.unit = 'pcs',
    this.imagePath,
    this.isActive = true,
  });

  bool get hasLocalImage =>
      imagePath != null &&
      imagePath!.isNotEmpty &&
      File(imagePath!).existsSync();

  PosProduct copyWith({
    String? id,
    String? name,
    String? sku,
    String? category,
    double? price,
    double? costPrice,
    int? stock,
    String? unit,
    String? imagePath,
    bool clearImagePath = false,
    bool? isActive,
  }) {
    return PosProduct(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      category: category ?? this.category,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      stock: stock ?? this.stock,
      unit: unit ?? this.unit,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sku': sku,
        'category': category,
        'price': price,
        'costPrice': costPrice,
        'stock': stock,
        'unit': unit,
        'imagePath': ?imagePath,
        'isActive': isActive,
      };

  factory PosProduct.fromJson(Map<String, dynamic> json) {
    return PosProduct(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sku: json['sku']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Umum',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      costPrice: (json['costPrice'] as num?)?.toDouble() ?? 0.0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      unit: json['unit']?.toString() ?? 'pcs',
      imagePath: json['imagePath'] as String?,
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

class PosCustomer {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String notes;
  final double totalSpent;
  final int visitCount;
  final DateTime createdAt;

  const PosCustomer({
    required this.id,
    required this.name,
    this.phone = '',
    this.email = '',
    this.notes = '',
    this.totalSpent = 0,
    this.visitCount = 0,
    required this.createdAt,
  });

  PosCustomer copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? notes,
    double? totalSpent,
    int? visitCount,
    DateTime? createdAt,
  }) {
    return PosCustomer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notes: notes ?? this.notes,
      totalSpent: totalSpent ?? this.totalSpent,
      visitCount: visitCount ?? this.visitCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'notes': notes,
        'totalSpent': totalSpent,
        'visitCount': visitCount,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PosCustomer.fromJson(Map<String, dynamic> json) {
    return PosCustomer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      totalSpent: (json['totalSpent'] as num?)?.toDouble() ?? 0.0,
      visitCount: (json['visitCount'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class PosCartItem {
  final PosProduct product;
  final int quantity;
  final String note;

  const PosCartItem({
    required this.product,
    required this.quantity,
    this.note = '',
  });

  double get lineTotal => product.price * quantity;
  double get lineCost => product.costPrice * quantity;

  PosCartItem copyWith({PosProduct? product, int? quantity, String? note}) {
    return PosCartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      note: note ?? this.note,
    );
  }
}

class PosOrderItem {
  final String productId;
  final String productName;
  final double unitPrice;
  final double costPrice;
  final int quantity;
  final String unit;

  const PosOrderItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.costPrice,
    required this.quantity,
    required this.unit,
  });

  double get lineTotal => unitPrice * quantity;
  double get lineCost => costPrice * quantity;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'unitPrice': unitPrice,
        'costPrice': costPrice,
        'quantity': quantity,
        'unit': unit,
      };

  factory PosOrderItem.fromJson(Map<String, dynamic> json) {
    return PosOrderItem(
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
      costPrice: (json['costPrice'] as num?)?.toDouble() ?? 0.0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unit: json['unit']?.toString() ?? 'pcs',
    );
  }
}

class PosOrder {
  final String id;
  final String receiptNumber;
  final DateTime createdAt;
  final List<PosOrderItem> items;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double total;
  final double totalCost;
  final String paymentMethod;
  final double amountPaid;
  final double changeAmount;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String note;

  const PosOrder({
    required this.id,
    required this.receiptNumber,
    required this.createdAt,
    required this.items,
    required this.subtotal,
    this.discountAmount = 0,
    this.taxAmount = 0,
    required this.total,
    required this.totalCost,
    required this.paymentMethod,
    required this.amountPaid,
    required this.changeAmount,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.note = '',
  });

  double get grossProfit => total - totalCost;

  Map<String, dynamic> toJson() => {
        'id': id,
        'receiptNumber': receiptNumber,
        'createdAt': createdAt.toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
        'subtotal': subtotal,
        'discountAmount': discountAmount,
        'taxAmount': taxAmount,
        'total': total,
        'totalCost': totalCost,
        'paymentMethod': paymentMethod,
        'amountPaid': amountPaid,
        'changeAmount': changeAmount,
        'customerId': customerId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'note': note,
      };

  factory PosOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? const [];
    return PosOrder(
      id: json['id']?.toString() ?? '',
      receiptNumber: json['receiptNumber']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      items: rawItems
          .map((e) => PosOrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (json['taxAmount'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['paymentMethod']?.toString() ?? 'Tunai',
      amountPaid: (json['amountPaid'] as num?)?.toDouble() ?? 0.0,
      changeAmount: (json['changeAmount'] as num?)?.toDouble() ?? 0.0,
      customerId: json['customerId'] as String?,
      customerName: json['customerName'] as String?,
      customerPhone: json['customerPhone'] as String?,
      note: json['note']?.toString() ?? '',
    );
  }

  String toJsonString() => jsonEncode(toJson());
}

class PosExpense {
  final String id;
  final String title;
  final String category;
  final double amount;
  final DateTime createdAt;

  const PosExpense({
    required this.id,
    required this.title,
    this.category = 'Operasional',
    required this.amount,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'amount': amount,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PosExpense.fromJson(Map<String, dynamic> json) {
    return PosExpense(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Operasional',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class PosFinancialSummary {
  final double totalRevenue;
  final double totalCost;
  final double grossProfit;
  final double totalExpenses;
  final double netProfit;
  final double taxCollected;
  final double discountTotal;
  final int transactionCount;
  final double averageOrder;

  const PosFinancialSummary({
    required this.totalRevenue,
    required this.totalCost,
    required this.grossProfit,
    required this.totalExpenses,
    required this.netProfit,
    required this.taxCollected,
    required this.discountTotal,
    required this.transactionCount,
    required this.averageOrder,
  });
}
