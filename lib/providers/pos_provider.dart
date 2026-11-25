import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pos_models.dart';

class PosProvider extends ChangeNotifier {
  static const String _kProfileKey = 'pos_business_profile_v1';
  static const String _kProductsKey = 'pos_products_v1';
  static const String _kCustomersKey = 'pos_customers_v1';
  static const String _kOrdersKey = 'pos_orders_v1';
  static const String _kExpensesKey = 'pos_expenses_v1';
  static const String _kSeededKey = 'pos_seeded_v1';

  SharedPreferences? _prefs;
  bool _initialized = false;

  PosBusinessProfile _profile = const PosBusinessProfile();
  List<PosProduct> _products = [];
  List<PosCustomer> _customers = [];
  List<PosOrder> _orders = [];
  List<PosExpense> _expenses = [];

  final List<PosCartItem> _cart = [];
  PosCustomer? _selectedCustomer;
  double _discountAmount = 0.0;

  bool get initialized => _initialized;
  PosBusinessProfile get profile => _profile;
  List<PosProduct> get products => List.unmodifiable(_products);
  List<PosCustomer> get customers => List.unmodifiable(_customers);
  List<PosOrder> get orders => List.unmodifiable(_orders);
  List<PosExpense> get expenses => List.unmodifiable(_expenses);
  List<PosCartItem> get cart => List.unmodifiable(_cart);
  PosCustomer? get selectedCustomer => _selectedCustomer;
  double get discountAmount => _discountAmount;

  int get cartItemCount =>
      _cart.fold<int>(0, (sum, item) => sum + item.quantity);

  double get cartSubtotal =>
      _cart.fold<double>(0.0, (sum, item) => sum + item.lineTotal);

  double get cartDiscount => min(_discountAmount, cartSubtotal);

  double get cartTax {
    final taxable = max(0.0, cartSubtotal - cartDiscount);
    return taxable * (_profile.taxPercent / 100.0);
  }

  double get cartTotal => max(0.0, cartSubtotal - cartDiscount + cartTax);

  List<String> get productCategories {
    final set = <String>{'Semua'};
    for (final p in _products) {
      if (p.category.trim().isNotEmpty) {
        set.add(p.category.trim());
      }
    }
    return set.toList();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _loadData();
    if (!(_prefs?.getBool(_kSeededKey) ?? false) && _products.isEmpty) {
      _seedStarterCatalog(PosBusinessType.coffeeshop);
      await _prefs?.setBool(_kSeededKey, true);
      await _persistAll();
    }
    _initialized = true;
    notifyListeners();
  }

  void _loadData() {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      final rawProf = prefs.getString(_kProfileKey);
      if (rawProf != null && rawProf.isNotEmpty) {
        _profile = PosBusinessProfile.fromJson(
          jsonDecode(rawProf) as Map<String, dynamic>,
        );
      }
    } catch (_) {}

    try {
      final raw = prefs.getStringList(_kProductsKey) ?? const [];
      _products = raw
          .map((s) => PosProduct.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    try {
      final raw = prefs.getStringList(_kCustomersKey) ?? const [];
      _customers = raw
          .map((s) => PosCustomer.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    try {
      final raw = prefs.getStringList(_kOrdersKey) ?? const [];
      _orders = raw
          .map((s) => PosOrder.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {}

    try {
      final raw = prefs.getStringList(_kExpensesKey) ?? const [];
      _expenses = raw
          .map((s) => PosExpense.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {}
  }

  Future<void> _persistAll() async {
    await Future.wait([
      _persistProfile(),
      _persistProducts(),
      _persistCustomers(),
      _persistOrders(),
      _persistExpenses(),
    ]);
  }

  Future<void> _persistProfile() async {
    await _prefs?.setString(_kProfileKey, jsonEncode(_profile.toJson()));
  }

  Future<void> _persistProducts() async {
    await _prefs?.setStringList(
      _kProductsKey,
      _products.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> _persistCustomers() async {
    await _prefs?.setStringList(
      _kCustomersKey,
      _customers.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> _persistOrders() async {
    await _prefs?.setStringList(
      _kOrdersKey,
      _orders.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> _persistExpenses() async {
    await _prefs?.setStringList(
      _kExpensesKey,
      _expenses.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  void _seedStarterCatalog(PosBusinessType type) {
    _products = switch (type) {
      PosBusinessType.coffeeshop => [
          const PosProduct(
            id: 'prod_esp',
            name: 'Espresso',
            sku: 'COF-01',
            category: 'Kopi',
            price: 18000,
            costPrice: 6000,
            stock: 100,
            unit: 'cup',
          ),
          const PosProduct(
            id: 'prod_latte',
            name: 'Caffe Latte',
            sku: 'COF-02',
            category: 'Kopi',
            price: 28000,
            costPrice: 10500,
            stock: 100,
            unit: 'cup',
          ),
          const PosProduct(
            id: 'prod_amer',
            name: 'Iced Americano',
            sku: 'COF-03',
            category: 'Kopi',
            price: 22000,
            costPrice: 7000,
            stock: 100,
            unit: 'cup',
          ),
          const PosProduct(
            id: 'prod_matcha',
            name: 'Matcha Latte',
            sku: 'NON-01',
            category: 'Non-Kopi',
            price: 30000,
            costPrice: 12000,
            stock: 80,
            unit: 'cup',
          ),
          const PosProduct(
            id: 'prod_crois',
            name: 'Butter Croissant',
            sku: 'FD-01',
            category: 'Pastry',
            price: 25000,
            costPrice: 12000,
            stock: 40,
            unit: 'pcs',
          ),
          const PosProduct(
            id: 'prod_beans',
            name: 'House Blend Beans 250g',
            sku: 'RST-01',
            category: 'Roastery',
            price: 85000,
            costPrice: 48000,
            stock: 30,
            unit: 'pack',
          ),
        ],
      PosBusinessType.roastery => [
          const PosProduct(
            id: 'rst_gayo',
            name: 'Arabica Aceh Gayo 250g',
            sku: 'RST-101',
            category: 'Single Origin',
            price: 95000,
            costPrice: 55000,
            stock: 50,
            unit: 'pack',
          ),
          const PosProduct(
            id: 'rst_toraja',
            name: 'Arabica Toraja Sapan 250g',
            sku: 'RST-102',
            category: 'Single Origin',
            price: 98000,
            costPrice: 58000,
            stock: 40,
            unit: 'pack',
          ),
          const PosProduct(
            id: 'rst_esp1kg',
            name: 'Commercial Espresso Blend 1kg',
            sku: 'RST-103',
            category: 'Espresso Blend',
            price: 240000,
            costPrice: 155000,
            stock: 25,
            unit: 'kg',
          ),
          const PosProduct(
            id: 'rst_drip',
            name: 'Drip Bag Box (5 pcs)',
            sku: 'RST-104',
            category: 'Drip & Brew',
            price: 55000,
            costPrice: 28000,
            stock: 60,
            unit: 'box',
          ),
        ],
      PosBusinessType.general => [
          const PosProduct(
            id: 'gen_1',
            name: 'Produk Reguler A',
            sku: 'SKU-001',
            category: 'Umum',
            price: 25000,
            costPrice: 15000,
            stock: 50,
            unit: 'pcs',
          ),
          const PosProduct(
            id: 'gen_2',
            name: 'Produk Reguler B',
            sku: 'SKU-002',
            category: 'Umum',
            price: 50000,
            costPrice: 32000,
            stock: 40,
            unit: 'pcs',
          ),
          const PosProduct(
            id: 'gen_3',
            name: 'Paket Bundling',
            sku: 'SKU-003',
            category: 'Paket',
            price: 90000,
            costPrice: 60000,
            stock: 20,
            unit: 'paket',
          ),
        ],
    };

    if (_customers.isEmpty) {
      _customers = [
        PosCustomer(
          id: 'cust_walkin',
          name: 'Pelanggan Umum',
          phone: '',
          notes: 'Pembeli langsung di kasir',
          createdAt: DateTime.now(),
        ),
      ];
    }
  }

  Future<void> updateBusinessProfile(PosBusinessProfile updated) async {
    _profile = updated;
    await _persistProfile();
    notifyListeners();
  }

  Future<void> applyBusinessPresetCatalog(PosBusinessType type) async {
    _profile = _profile.copyWith(businessType: type);
    _seedStarterCatalog(type);
    await _persistProfile();
    await _persistProducts();
    notifyListeners();
  }

  // ==================== CART OPERATIONS ====================

  void addToCart(PosProduct product) {
    final idx = _cart.indexWhere((c) => c.product.id == product.id);
    if (idx >= 0) {
      _cart[idx] = _cart[idx].copyWith(quantity: _cart[idx].quantity + 1);
    } else {
      _cart.add(PosCartItem(product: product, quantity: 1));
    }
    notifyListeners();
  }

  void updateCartQty(String productId, int newQty) {
    final idx = _cart.indexWhere((c) => c.product.id == productId);
    if (idx < 0) return;
    if (newQty <= 0) {
      _cart.removeAt(idx);
    } else {
      _cart[idx] = _cart[idx].copyWith(quantity: newQty);
    }
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _selectedCustomer = null;
    _discountAmount = 0.0;
    notifyListeners();
  }

  void setSelectedCustomer(PosCustomer? customer) {
    _selectedCustomer = customer;
    notifyListeners();
  }

  void setDiscountAmount(double discount) {
    _discountAmount = max(0.0, discount);
    notifyListeners();
  }

  // ==================== CHECKOUT ====================

  Future<PosOrder> checkout({
    required String paymentMethod,
    required double amountPaid,
    String note = '',
  }) async {
    if (_cart.isEmpty) {
      throw StateError('Keranjang masih kosong');
    }

    final now = DateTime.now();
    final subtotal = cartSubtotal;
    final discount = cartDiscount;
    final tax = cartTax;
    final total = cartTotal;
    final totalCost = _cart.fold<double>(0.0, (s, c) => s + c.lineCost);
    final paid = paymentMethod == 'Tunai' ? max(amountPaid, total) : total;
    final change = max(0.0, paid - total);

    final receiptNo =
        'INV-${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(_orders.length + 1).toString().padLeft(4, '0')}';

    final order = PosOrder(
      id: 'ord_${now.microsecondsSinceEpoch}',
      receiptNumber: receiptNo,
      createdAt: now,
      items: _cart
          .map(
            (c) => PosOrderItem(
              productId: c.product.id,
              productName: c.product.name,
              unitPrice: c.product.price,
              costPrice: c.product.costPrice,
              quantity: c.quantity,
              unit: c.product.unit,
            ),
          )
          .toList(),
      subtotal: subtotal,
      discountAmount: discount,
      taxAmount: tax,
      total: total,
      totalCost: totalCost,
      paymentMethod: paymentMethod,
      amountPaid: paid,
      changeAmount: change,
      customerId: _selectedCustomer?.id,
      customerName: _selectedCustomer?.name,
      customerPhone: _selectedCustomer?.phone,
      note: note,
    );

    // Deduct stock
    for (final cartItem in _cart) {
      final pIdx = _products.indexWhere((p) => p.id == cartItem.product.id);
      if (pIdx >= 0) {
        final cur = _products[pIdx];
        _products[pIdx] = cur.copyWith(
          stock: max(0, cur.stock - cartItem.quantity),
        );
      }
    }

    // Update customer stats
    if (_selectedCustomer != null) {
      final cIdx =
          _customers.indexWhere((c) => c.id == _selectedCustomer!.id);
      if (cIdx >= 0) {
        final cur = _customers[cIdx];
        _customers[cIdx] = cur.copyWith(
          totalSpent: cur.totalSpent + total,
          visitCount: cur.visitCount + 1,
        );
      }
    }

    _orders.insert(0, order);
    _cart.clear();
    _selectedCustomer = null;
    _discountAmount = 0.0;

    await Future.wait([
      _persistOrders(),
      _persistProducts(),
      _persistCustomers(),
    ]);
    notifyListeners();
    return order;
  }

  // ==================== PRODUCT & CUSTOMER CRUD ====================

  Future<void> saveProduct(PosProduct product) async {
    final idx = _products.indexWhere((p) => p.id == product.id);
    if (idx >= 0) {
      _products[idx] = product;
    } else {
      _products.insert(0, product);
    }
    await _persistProducts();
    notifyListeners();
  }

  Future<void> deleteProduct(String productId) async {
    _products.removeWhere((p) => p.id == productId);
    _cart.removeWhere((c) => c.product.id == productId);
    await _persistProducts();
    notifyListeners();
  }

  Future<void> saveCustomer(PosCustomer customer) async {
    final idx = _customers.indexWhere((c) => c.id == customer.id);
    if (idx >= 0) {
      _customers[idx] = customer;
    } else {
      _customers.insert(0, customer);
    }
    await _persistCustomers();
    notifyListeners();
  }

  Future<void> deleteCustomer(String customerId) async {
    _customers.removeWhere((c) => c.id == customerId);
    if (_selectedCustomer?.id == customerId) {
      _selectedCustomer = null;
    }
    await _persistCustomers();
    notifyListeners();
  }

  // ==================== EXPENSES & FINANCIAL ANALYTICS ====================

  Future<void> addExpense(PosExpense expense) async {
    _expenses.insert(0, expense);
    await _persistExpenses();
    notifyListeners();
  }

  Future<void> deleteExpense(String expenseId) async {
    _expenses.removeWhere((e) => e.id == expenseId);
    await _persistExpenses();
    notifyListeners();
  }

  bool _isInRange(DateTime dt, String rangeKey) {
    final now = DateTime.now();
    return switch (rangeKey) {
      'Hari Ini' =>
        dt.year == now.year && dt.month == now.month && dt.day == now.day,
      '7 Hari' =>
        dt.isAfter(now.subtract(const Duration(days: 7))),
      '30 Hari' =>
        dt.isAfter(now.subtract(const Duration(days: 30))),
      _ => true,
    };
  }

  List<PosOrder> ordersInRange(String rangeKey) =>
      _orders.where((o) => _isInRange(o.createdAt, rangeKey)).toList();

  List<PosExpense> expensesInRange(String rangeKey) =>
      _expenses.where((e) => _isInRange(e.createdAt, rangeKey)).toList();

  PosFinancialSummary financialSummary(String rangeKey) {
    final filteredOrders = ordersInRange(rangeKey);
    final filteredExpenses = expensesInRange(rangeKey);

    double revenue = 0;
    double cost = 0;
    double tax = 0;
    double discount = 0;
    for (final o in filteredOrders) {
      revenue += o.total;
      cost += o.totalCost;
      tax += o.taxAmount;
      discount += o.discountAmount;
    }

    final expenseTotal =
        filteredExpenses.fold<double>(0.0, (s, e) => s + e.amount);
    final gross = revenue - cost;
    final net = gross - expenseTotal;
    final count = filteredOrders.length;

    return PosFinancialSummary(
      totalRevenue: revenue,
      totalCost: cost,
      grossProfit: gross,
      totalExpenses: expenseTotal,
      netProfit: net,
      taxCollected: tax,
      discountTotal: discount,
      transactionCount: count,
      averageOrder: count > 0 ? revenue / count : 0,
    );
  }

  /// Returns top selling products sorted by revenue descending.
  List<({String name, int qty, double revenue})> topSellingProducts(
    String rangeKey, {
    int limit = 5,
  }) {
    final Map<String, ({int qty, double revenue})> map = {};
    for (final o in ordersInRange(rangeKey)) {
      for (final item in o.items) {
        final cur = map[item.productName] ?? (qty: 0, revenue: 0.0);
        map[item.productName] = (
          qty: cur.qty + item.quantity,
          revenue: cur.revenue + item.lineTotal,
        );
      }
    }
    final list = map.entries
        .map((e) => (name: e.key, qty: e.value.qty, revenue: e.value.revenue))
        .toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    return list.take(limit).toList();
  }

  Map<String, double> paymentMethodBreakdown(String rangeKey) {
    final Map<String, double> map = {};
    for (final o in ordersInRange(rangeKey)) {
      map[o.paymentMethod] = (map[o.paymentMethod] ?? 0) + o.total;
    }
    return map;
  }

  /// Returns daily revenue totals for the last [days] days (oldest -> newest).
  List<({String label, double revenue})> dailySalesSeries({int days = 7}) {
    final now = DateTime.now();
    final List<({String label, double revenue})> out = [];
    for (int offset = days - 1; offset >= 0; offset--) {
      final d = now.subtract(Duration(days: offset));
      double sum = 0;
      for (final o in _orders) {
        if (o.createdAt.year == d.year &&
            o.createdAt.month == d.month &&
            o.createdAt.day == d.day) {
          sum += o.total;
        }
      }
      out.add((label: '${d.day}/${d.month}', revenue: sum));
    }
    return out;
  }
}
