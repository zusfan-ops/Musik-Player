import 'pos_models.dart';

enum FinanceEntryType {
  income,
  expense,
}

extension FinanceEntryTypeExt on FinanceEntryType {
  String get label =>
      this == FinanceEntryType.income ? 'Pemasukan' : 'Pengeluaran';
}

enum FinanceEntrySource {
  manual,
  posOrder,
}

class FinanceEntry {
  final String id;
  final FinanceEntryType type;
  final String title;
  final String category;
  final double amount;
  final String paymentAccount; // Kas Tunai | Rekening Bank | QRIS / E-Wallet
  final DateTime date;
  final String notes;
  final FinanceEntrySource source;
  final String? referenceId;

  const FinanceEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.category,
    required this.amount,
    this.paymentAccount = 'Kas Tunai',
    required this.date,
    this.notes = '',
    this.source = FinanceEntrySource.manual,
    this.referenceId,
  });

  bool get isIncome => type == FinanceEntryType.income;
  bool get isFromPos => source == FinanceEntrySource.posOrder;

  FinanceEntry copyWith({
    String? id,
    FinanceEntryType? type,
    String? title,
    String? category,
    double? amount,
    String? paymentAccount,
    DateTime? date,
    String? notes,
    FinanceEntrySource? source,
    String? referenceId,
  }) {
    return FinanceEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      paymentAccount: paymentAccount ?? this.paymentAccount,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      source: source ?? this.source,
      referenceId: referenceId ?? this.referenceId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'category': category,
        'amount': amount,
        'paymentAccount': paymentAccount,
        'date': date.toIso8601String(),
        'notes': notes,
        'source': source.name,
        'referenceId': ?referenceId,
      };

  factory FinanceEntry.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? 'expense';
    final srcName = json['source']?.toString() ?? 'manual';
    return FinanceEntry(
      id: json['id']?.toString() ?? '',
      type: typeName == 'income'
          ? FinanceEntryType.income
          : FinanceEntryType.expense,
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Umum',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      paymentAccount: json['paymentAccount']?.toString() ?? 'Kas Tunai',
      date:
          DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      notes: json['notes']?.toString() ?? '',
      source: srcName == 'posOrder'
          ? FinanceEntrySource.posOrder
          : FinanceEntrySource.manual,
      referenceId: json['referenceId'] as String?,
    );
  }

  static String accountFromPosPayment(String paymentMethod) {
    return switch (paymentMethod) {
      'Tunai' => 'Kas Tunai',
      'QRIS' => 'QRIS / E-Wallet',
      'Transfer' || 'Kartu' => 'Rekening Bank',
      _ => 'Kas Tunai',
    };
  }

  factory FinanceEntry.fromPosOrder(PosOrder order) {
    final itemSummary = order.items
        .map((i) => '${i.quantity}x ${i.productName}')
        .join(', ');
    final custPart =
        order.customerName != null && order.customerName!.isNotEmpty
            ? ' • Plg: ${order.customerName}'
            : '';
    return FinanceEntry(
      id: 'fin_pos_${order.id}',
      type: FinanceEntryType.income,
      title: 'Penjualan POS ${order.receiptNumber}',
      category: 'Penjualan POS',
      amount: order.total,
      paymentAccount: accountFromPosPayment(order.paymentMethod),
      date: order.createdAt,
      notes: '$itemSummary$custPart',
      source: FinanceEntrySource.posOrder,
      referenceId: order.id,
    );
  }
}

class FinanceSummary {
  final double totalIncome;
  final double totalExpense;
  final double netBalance;
  final double posIncome;
  final double manualIncome;
  final int entryCount;

  const FinanceSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.netBalance,
    required this.posIncome,
    required this.manualIncome,
    required this.entryCount,
  });
}
