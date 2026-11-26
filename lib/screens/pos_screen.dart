import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/finance_models.dart';
import '../models/pos_models.dart';
import '../providers/finance_provider.dart';
import '../providers/music_provider.dart';
import '../providers/pos_provider.dart';
import '../services/pos_pdf_service.dart';
import '../services/pos_printer_service.dart';
import '../theme/app_theme.dart';
import '../widgets/audio_waveform_visualizer.dart';
import 'keuangan_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  static void show(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const PosScreen()),
    );
  }

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pos.profile.storeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            Text(
              'POS Universal • ${pos.profile.businessType.label}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Buka Keuangan & Buku Kas',
            icon: const Icon(Icons.account_balance_wallet_rounded),
            onPressed: () => KeuanganScreen.show(context),
          ),
          IconButton(
            tooltip: 'Pengaturan Toko & Preset Usaha',
            icon: const Icon(Icons.storefront_rounded),
            onPressed: () => _showStoreSettingsDialog(context, pos),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.spotifyGreen,
          labelColor: AppColors.spotifyGreen,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.point_of_sale_rounded, size: 18), text: 'Kasir'),
            Tab(icon: Icon(Icons.inventory_2_rounded, size: 18), text: 'Produk'),
            Tab(icon: Icon(Icons.people_rounded, size: 18), text: 'Pelanggan'),
            Tab(icon: Icon(Icons.analytics_rounded, size: 18), text: 'Laporan'),
          ],
        ),
      ),
      body: Column(
        children: [
          const _PosMusicMiniController(),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _PosCashierTab(
                  onOpenCustomersTab: () => _tabCtrl.animateTo(2),
                ),
                const _PosProductsTab(),
                const _PosCustomersTab(),
                const _PosReportsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showStoreSettingsDialog(
    BuildContext context,
    PosProvider pos,
  ) async {
    final nameCtrl = TextEditingController(text: pos.profile.storeName);
    final addrCtrl = TextEditingController(text: pos.profile.address);
    final phoneCtrl = TextEditingController(text: pos.profile.phone);
    final taxCtrl =
        TextEditingController(text: pos.profile.taxPercent.toStringAsFixed(0));
    final footerCtrl = TextEditingController(text: pos.profile.receiptFooter);
    PosBusinessType selectedType = pos.profile.businessType;

    await showDialog<void>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text(
            'Pengaturan Toko POS',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Jenis Usaha',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final t in PosBusinessType.values)
                      ChoiceChip(
                        label: Text(t.label, style: const TextStyle(fontSize: 12)),
                        selected: selectedType == t,
                        onSelected: (_) => setDState(() => selectedType = t),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Toko / Usaha'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: addrCtrl,
                  decoration: const InputDecoration(labelText: 'Alamat'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Telepon / WA'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: taxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Pajak / PB1 (%)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: footerCtrl,
                  decoration: const InputDecoration(labelText: 'Catatan Kaki Nota'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await pos.applyBusinessPresetCatalog(selectedType);
                    if (dCtx.mounted) Navigator.pop(dCtx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Katalog contoh ${selectedType.label} diterapkan!',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: Text(
                    'Muat Katalog Contoh ${selectedType.label}',
                    style: const TextStyle(fontSize: 12),
                  ),
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
                final updated = pos.profile.copyWith(
                  storeName: nameCtrl.text.trim().isEmpty
                      ? 'MediaCenter POS'
                      : nameCtrl.text.trim(),
                  businessType: selectedType,
                  address: addrCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  taxPercent: double.tryParse(taxCtrl.text.trim()) ?? 0.0,
                  receiptFooter: footerCtrl.text.trim(),
                );
                await pos.updateBusinessProfile(updated);
                if (dCtx.mounted) Navigator.pop(dCtx);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    addrCtrl.dispose();
    phoneCtrl.dispose();
    taxCtrl.dispose();
    footerCtrl.dispose();
  }
}

class _PosMusicMiniController extends StatelessWidget {
  const _PosMusicMiniController();

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicProvider>();
    final track = music.currentTrack;
    final offline = music.allOfflineMusicTracks;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.darkNav,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.music_note_rounded,
            color: AppColors.spotifyGreen,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track?.title ?? 'Musik Toko (Standby)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                AudioWaveformVisualizer(
                  isPlaying: music.isPlaying,
                  color: AppColors.spotifyGreen,
                  barCount: 18,
                  height: 12,
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white70),
            onPressed: track != null ? music.playPrevious : null,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              music.isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded,
              color: AppColors.spotifyGreen,
              size: 28,
            ),
            onPressed: () {
              if (track != null) {
                music.togglePlayPause();
              } else if (offline.isNotEmpty) {
                music.playTrackList(offline);
              }
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.skip_next_rounded, color: Colors.white70),
            onPressed: track != null ? music.playNext : null,
          ),
        ],
      ),
    );
  }
}

// ==================== 1. TAB KASIR (POS) ====================

class _PosCashierTab extends StatefulWidget {
  final VoidCallback onOpenCustomersTab;

  const _PosCashierTab({required this.onOpenCustomersTab});

  @override
  State<_PosCashierTab> createState() => _PosCashierTabState();
}

class _PosCashierTabState extends State<_PosCashierTab> {
  String _search = '';
  String _category = 'Semua';

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final categories = pos.productCategories;
    final filtered = pos.products.where((p) {
      if (!p.isActive) return false;
      if (_category != 'Semua' && p.category != _category) return false;
      if (_search.trim().isNotEmpty) {
        final q = _search.toLowerCase();
        return p.name.toLowerCase().contains(q) ||
            p.sku.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 820;
    final gridCols = width >= 1250 ? 4 : (isWide ? 3 : 2);

    final Widget productPane = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Cari menu, produk, atau SKU...',
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
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final cat = categories[i];
              return ChoiceChip(
                label: Text(cat, style: const TextStyle(fontSize: 11.5)),
                selected: _category == cat,
                onSelected: (_) => setState(() => _category = cat),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'Produk tidak ditemukan.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: gridCols,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: isWide ? 0.96 : 0.92,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, idx) {
                    final prod = filtered[idx];
                    final inCartQty = pos.cart
                        .where((c) => c.product.id == prod.id)
                        .fold<int>(0, (s, c) => s + c.quantity);
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => pos.addToCart(prod),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: inCartQty > 0
                                ? AppColors.spotifyGreen
                                : Colors.black.withValues(alpha: 0.08),
                            width: inCartQty > 0 ? 1.6 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: prod.hasLocalImage
                                        ? Image.file(
                                            File(prod.imagePath!),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                _productPlaceholder(prod),
                                          )
                                        : _productPlaceholder(prod),
                                  ),
                                  Positioned(
                                    left: 6,
                                    top: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.58),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        prod.category,
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (inCartQty > 0)
                                    Positioned(
                                      right: 6,
                                      top: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.spotifyGreen,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '${inCartQty}x',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              prod.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  PosFormat.rupiah(prod.price),
                                  style: const TextStyle(
                                    color: AppColors.spotifyGreen,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Stok ${prod.stock}',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );

    if (isWide) {
      return Row(
        children: [
          Expanded(flex: 3, child: productPane),
          Container(
            width: width >= 1250 ? 390 : 340,
            margin: const EdgeInsets.fromLTRB(0, 8, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: _CurrentOrderPanel(
              onOpenCustomersTab: widget.onOpenCustomersTab,
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        productPane,
        if (pos.cart.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: InkWell(
              onTap: () => _openCartBottomSheet(context),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.darkNav,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.spotifyGreen,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${pos.cartItemCount} Item',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        PosFormat.rupiah(pos.cartTotal),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const Text(
                      'Checkout',
                      style: TextStyle(
                        color: AppColors.spotifyGreen,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.spotifyGreen,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openCartBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: _CurrentOrderPanel(
          closeOnCheckout: true,
          onOpenCustomersTab: widget.onOpenCustomersTab,
        ),
      ),
    );
  }

  Widget _productPlaceholder(PosProduct prod) {
    return Container(
      color: AppColors.surface,
      child: Center(
        child: Icon(
          prod.category.toLowerCase().contains('kopi')
              ? Icons.coffee_rounded
              : Icons.inventory_2_outlined,
          color: AppColors.textMuted,
          size: 32,
        ),
      ),
    );
  }
}

class _CurrentOrderPanel extends StatelessWidget {
  final bool closeOnCheckout;
  final VoidCallback onOpenCustomersTab;

  const _CurrentOrderPanel({
    this.closeOnCheckout = false,
    required this.onOpenCustomersTab,
  });

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Pesanan Saat Ini',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (pos.cart.isNotEmpty)
                TextButton(
                  onPressed: pos.clearCart,
                  child: const Text(
                    'Kosongkan',
                    style: TextStyle(color: AppColors.netflixRed),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickCustomer(context, pos),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person_outline_rounded,
                          size: 18,
                          color: AppColors.neonCyan,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pos.selectedCustomer?.name ??
                                'Pilih Pelanggan (Opsional)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Tambah Pelanggan Baru',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                onPressed: () => _showPosCustomerDialog(
                  context,
                  pos,
                  autoSelectOnAdd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: pos.cart.isEmpty
                ? const Center(
                    child: Text(
                      'Ketuk produk untuk menambahkan ke pesanan',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    itemCount: pos.cart.length,
                    separatorBuilder: (_, _) => const Divider(height: 10),
                    itemBuilder: (_, i) {
                      final c = pos.cart[i];
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  '${PosFormat.rupiah(c.product.price)} / ${c.product.unit}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                            onPressed: () => pos.updateCartQty(
                              c.product.id,
                              c.quantity - 1,
                            ),
                          ),
                          Text(
                            '${c.quantity}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.add_circle_outline_rounded,
                              color: AppColors.spotifyGreen,
                            ),
                            onPressed: () => pos.updateCartQty(
                              c.product.id,
                              c.quantity + 1,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const Divider(),
          _summaryRow('Subtotal', PosFormat.rupiah(pos.cartSubtotal)),
          if (pos.cartDiscount > 0)
            _summaryRow('Diskon', '-${PosFormat.rupiah(pos.cartDiscount)}'),
          if (pos.cartTax > 0)
            _summaryRow(
              'Pajak (${pos.profile.taxPercent.toStringAsFixed(0)}%)',
              PosFormat.rupiah(pos.cartTax),
            ),
          const SizedBox(height: 4),
          _summaryRow(
            'TOTAL',
            PosFormat.rupiah(pos.cartTotal),
            bold: true,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.spotifyGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: pos.cart.isEmpty
                  ? null
                  : () => _openCheckoutDialog(context, pos),
              icon: const Icon(Icons.payments_rounded),
              label: const Text(
                'Checkout & Bayar',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String l, String r, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              fontSize: bold ? 15 : 12.5,
            ),
          ),
          Text(
            r,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              fontSize: bold ? 16 : 13,
              color: bold ? AppColors.spotifyGreen : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomer(BuildContext context, PosProvider pos) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      builder: (sCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sCtx).size.height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Pilih Pelanggan',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sCtx);
                        if (closeOnCheckout && context.mounted) {
                          Navigator.pop(context);
                        }
                        onOpenCustomersTab();
                      },
                      icon: const Icon(Icons.people_outline_rounded, size: 17),
                      label: const Text('Database'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.spotifyGreen,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () async {
                        Navigator.pop(sCtx);
                        if (context.mounted) {
                          await _showPosCustomerDialog(
                            context,
                            pos,
                            autoSelectOnAdd: true,
                          );
                        }
                      },
                      icon: const Icon(Icons.person_add_rounded, size: 16),
                      label: const Text('Tambah'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('Tanpa Pelanggan / Umum'),
                      onTap: () {
                        pos.setSelectedCustomer(null);
                        Navigator.pop(sCtx);
                      },
                    ),
                    for (final c in pos.customers)
                      ListTile(
                        leading: const Icon(Icons.person_rounded),
                        title: Text(c.name),
                        subtitle: Text(
                          '${c.phone.isNotEmpty ? c.phone : 'Tanpa no HP'} • ${c.visitCount}x belanja',
                        ),
                        onTap: () {
                          pos.setSelectedCustomer(c);
                          Navigator.pop(sCtx);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCheckoutDialog(
    BuildContext context,
    PosProvider pos,
  ) async {
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    String paymentMethod = 'Tunai';
    final paidCtrl =
        TextEditingController(text: pos.cartTotal.round().toString());
    final discountCtrl =
        TextEditingController(text: pos.discountAmount.round().toString());

    await showDialog<void>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setDState) {
          final paidVal = double.tryParse(paidCtrl.text) ?? pos.cartTotal;
          final change = paymentMethod == 'Tunai'
              ? (paidVal - pos.cartTotal).clamp(0.0, double.infinity)
              : 0.0;
          return AlertDialog(
            title: const Text(
              'Pembayaran',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Tagihan: ${PosFormat.rupiah(pos.cartTotal)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.spotifyGreen,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Metode Pembayaran',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final m in const ['Tunai', 'QRIS', 'Transfer', 'Kartu'])
                        ChoiceChip(
                          label: Text(m, style: const TextStyle(fontSize: 12)),
                          selected: paymentMethod == m,
                          onSelected: (_) => setDState(() => paymentMethod = m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: discountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Diskon (Rp)'),
                    onChanged: (v) {
                      pos.setDiscountAmount(double.tryParse(v) ?? 0);
                      setDState(() {});
                    },
                  ),
                  if (paymentMethod == 'Tunai') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: paidCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Uang Diterima (Rp)'),
                      onChanged: (_) => setDState(() {}),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kembalian: ${PosFormat.rupiah(change)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
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
                  final fin = context.read<FinanceProvider>();
                  final order = await pos.checkout(
                    paymentMethod: paymentMethod,
                    amountPaid: paidVal,
                  );
                  await fin.recordPosOrder(order);
                  if (!dCtx.mounted) return;
                  Navigator.pop(dCtx);
                  if (closeOnCheckout && context.mounted) {
                    Navigator.pop(context);
                  }
                  if (rootCtx.mounted) {
                    await _PosReceiptActionsSheet.show(
                      rootCtx,
                      order,
                      pos.profile,
                    );
                  }
                },
                child: const Text('Selesaikan & Cetak'),
              ),
            ],
          );
        },
      ),
    );
    paidCtrl.dispose();
    discountCtrl.dispose();
  }
}

// ==================== RECEIPT / NOTA ACTIONS SHEET ====================

class _PosReceiptActionsSheet extends StatelessWidget {
  final PosOrder order;
  final PosBusinessProfile profile;

  const _PosReceiptActionsSheet({
    required this.order,
    required this.profile,
  });

  static Future<void> show(
    BuildContext context,
    PosOrder order,
    PosBusinessProfile profile,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PosReceiptActionsSheet(order: order, profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.spotifyGreen,
                  size: 26,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Transaksi Berhasil!',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${order.receiptNumber} • ${PosFormat.rupiah(order.total)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${item.quantity}x ${item.productName}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          Text(
                            PosFormat.rupiah(item.lineTotal),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        PosFormat.rupiah(order.total),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.spotifyGreen,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.darkNav,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _pickBluetoothAndPrint(context),
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text(
                      'Print Bluetooth',
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () =>
                        PosPdfService.shareReceiptPdf(order, profile),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text(
                      'Kirim WA PDF',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final f =
                      await PosPdfService.generateReceiptPdf(order, profile);
                  await OpenFile.open(f.path);
                },
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text('Lihat Nota PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBluetoothAndPrint(BuildContext context) async {
    try {
      final printers = await PosBluetoothPrinterService.listPairedPrinters();
      if (!context.mounted) return;
      if (!Platform.isAndroid || printers.isEmpty) {
        final ipCtrl = TextEditingController(text: '192.168.1.100');
        await showDialog<void>(
          context: context,
          builder: (dCtx) => AlertDialog(
            title: const Text('Cetak Printer Thermal (LAN / Wi-Fi)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Platform.isAndroid
                      ? 'Tidak ada printer Bluetooth ter-pair. Anda bisa cetak ke printer thermal jaringan (port 9100):'
                      : 'Masukkan IP Address printer thermal ESC/POS jaringan (port 9100):',
                  style: const TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ipCtrl,
                  decoration: const InputDecoration(
                    labelText: 'IP Printer (contoh: 192.168.1.100)',
                  ),
                ),
              ],
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
                  final host = ipCtrl.text.trim();
                  if (host.isEmpty) return;
                  Navigator.pop(dCtx);
                  try {
                    await PosBluetoothPrinterService.printReceiptTcp(
                      host: host,
                      order: order,
                      profile: profile,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Nota dicetak ke $host!')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Gagal cetak LAN: $e')),
                      );
                    }
                  }
                },
                child: const Text('Cetak'),
              ),
            ],
          ),
        );
        ipCtrl.dispose();
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: const Text('Pilih Printer Bluetooth'),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: printers.length,
              itemBuilder: (_, i) {
                final pr = printers[i];
                return ListTile(
                  leading: const Icon(Icons.print_rounded),
                  title: Text(pr.name),
                  subtitle: Text(pr.address),
                  onTap: () async {
                    Navigator.pop(dCtx);
                    try {
                      await PosBluetoothPrinterService.printReceipt(
                        address: pr.address,
                        order: order,
                        profile: profile,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Nota dicetak ke ${pr.name}!'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    }
                  },
                );
              },
            ),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bluetooth error: $e')),
        );
      }
    }
  }
}

// ==================== 2. TAB DATABASE PRODUK ====================

class _PosProductsTab extends StatefulWidget {
  const _PosProductsTab();

  @override
  State<_PosProductsTab> createState() => _PosProductsTabState();
}

class _PosProductsTabState extends State<_PosProductsTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final list = pos.products.where((p) {
      if (_search.trim().isEmpty) return true;
      final q = _search.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.spotifyGreen,
        foregroundColor: Colors.white,
        onPressed: () => _showProductDialog(context, pos),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah Produk'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Cari produk (${pos.products.length})...',
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
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final prod = list[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: AppColors.surfaceElevated,
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: prod.hasLocalImage
                          ? Image.file(
                              File(prod.imagePath!),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _listThumbPlaceholder(),
                            )
                          : _listThumbPlaceholder(),
                    ),
                    title: Text(
                      prod.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${prod.category} • Jual ${PosFormat.rupiah(prod.price)} • Modal ${PosFormat.rupiah(prod.costPrice)} • Stok ${prod.stock} ${prod.unit}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () =>
                              _showProductDialog(context, pos, existing: prod),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.netflixRed,
                            size: 20,
                          ),
                          onPressed: () => pos.deleteProduct(prod.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showProductDialog(
    BuildContext context,
    PosProvider pos, {
    PosProduct? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final skuCtrl = TextEditingController(text: existing?.sku ?? '');
    final catCtrl = TextEditingController(text: existing?.category ?? 'Umum');
    final priceCtrl = TextEditingController(
      text: existing != null ? existing.price.round().toString() : '',
    );
    final costCtrl = TextEditingController(
      text: existing != null ? existing.costPrice.round().toString() : '',
    );
    final stockCtrl = TextEditingController(
      text: existing != null ? existing.stock.toString() : '50',
    );
    final unitCtrl = TextEditingController(text: existing?.unit ?? 'pcs');
    String? pickedImagePath = existing?.imagePath;

    await showDialog<void>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: Text(existing == null ? 'Tambah Produk' : 'Edit Produk'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: pickedImagePath != null &&
                              pickedImagePath!.isNotEmpty &&
                              File(pickedImagePath!).existsSync()
                          ? Image.file(
                              File(pickedImagePath!),
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 64,
                              height: 64,
                              color: AppColors.surface,
                              child: const Icon(
                                Icons.add_photo_alternate_outlined,
                                color: AppColors.textMuted,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await FilePicker.pickFiles(
                                type: FileType.image,
                              );
                              if (picked.isEmpty) return;
                              final file = picked.first;
                              final docDir =
                                  await getApplicationDocumentsDirectory();
                              final imgDir = Directory(
                                p.join(docDir.path, 'MediaCenterPosImages'),
                              );
                              if (!await imgDir.exists()) {
                                await imgDir.create(recursive: true);
                              }
                              final ext = p.extension(file.name).isNotEmpty
                                  ? p.extension(file.name)
                                  : '.jpg';
                              final dest = File(
                                p.join(
                                  imgDir.path,
                                  'prod_${DateTime.now().microsecondsSinceEpoch}$ext',
                                ),
                              );
                              bool saved = false;
                              final bytes = await file.readAsBytes();
                              if (bytes.isNotEmpty) {
                                await dest.writeAsBytes(bytes, flush: true);
                                saved = true;
                              } else if (file.path != null) {
                                await File(file.path!).copy(dest.path);
                                saved = true;
                              }
                              if (saved && ctx.mounted) {
                                setDState(() => pickedImagePath = dest.path);
                              }
                            },
                            icon: const Icon(Icons.photo_library_rounded,
                                size: 16),
                            label: const Text(
                              'Pilih Foto',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          if (pickedImagePath != null)
                            TextButton(
                              onPressed: () =>
                                  setDState(() => pickedImagePath = null),
                              child: const Text(
                                'Hapus',
                                style: TextStyle(
                                  color: AppColors.netflixRed,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Produk'),
                ),
                TextField(
                  controller: catCtrl,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                ),
                TextField(
                  controller: skuCtrl,
                  decoration: const InputDecoration(labelText: 'SKU / Kode'),
                ),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Harga Jual (Rp)'),
                ),
                TextField(
                  controller: costCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Harga Modal / HPP (Rp)'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: stockCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Stok'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: unitCtrl,
                        decoration: const InputDecoration(labelText: 'Satuan'),
                      ),
                    ),
                  ],
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
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final prod = PosProduct(
                  id: existing?.id ??
                      'prod_${DateTime.now().microsecondsSinceEpoch}',
                  name: name,
                  sku: skuCtrl.text.trim(),
                  category:
                      catCtrl.text.trim().isEmpty ? 'Umum' : catCtrl.text.trim(),
                  price: double.tryParse(priceCtrl.text.trim()) ?? 0,
                  costPrice: double.tryParse(costCtrl.text.trim()) ?? 0,
                  stock: int.tryParse(stockCtrl.text.trim()) ?? 0,
                  unit: unitCtrl.text.trim().isEmpty
                      ? 'pcs'
                      : unitCtrl.text.trim(),
                  imagePath: pickedImagePath,
                );
                await pos.saveProduct(prod);
                if (dCtx.mounted) Navigator.pop(dCtx);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    skuCtrl.dispose();
    catCtrl.dispose();
    priceCtrl.dispose();
    costCtrl.dispose();
    stockCtrl.dispose();
    unitCtrl.dispose();
  }

  Widget _listThumbPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      color: AppColors.surface,
      child: const Icon(Icons.inventory_2_outlined, color: AppColors.textMuted),
    );
  }
}

// ==================== 3. TAB DATABASE PELANGGAN ====================

class _PosCustomersTab extends StatefulWidget {
  const _PosCustomersTab();

  @override
  State<_PosCustomersTab> createState() => _PosCustomersTabState();
}

class _PosCustomersTabState extends State<_PosCustomersTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final list = pos.customers.where((c) {
      if (_search.trim().isEmpty) return true;
      final q = _search.toLowerCase();
      return c.name.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.spotifyGreen,
        foregroundColor: Colors.white,
        onPressed: () => _showPosCustomerDialog(context, pos),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Tambah Pelanggan'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Cari pelanggan (${pos.customers.length})...',
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
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.spotifyGreen,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _showPosCustomerDialog(context, pos),
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: const Text('Tambah'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final cust = list[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: AppColors.surfaceElevated,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          AppColors.spotifyGreen.withValues(alpha: 0.16),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppColors.spotifyGreen,
                      ),
                    ),
                    title: Text(
                      cust.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${cust.phone.isNotEmpty ? cust.phone : 'No HP belum diisi'} • ${cust.visitCount}x belanja • Total ${PosFormat.rupiah(cust.totalSpent)}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _showPosCustomerDialog(
                            context,
                            pos,
                            existing: cust,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.netflixRed,
                            size: 20,
                          ),
                          onPressed: () => pos.deleteCustomer(cust.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showPosCustomerDialog(
  BuildContext context,
  PosProvider pos, {
  PosCustomer? existing,
  bool autoSelectOnAdd = false,
}) async {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
  final emailCtrl = TextEditingController(text: existing?.email ?? '');
  final notesCtrl = TextEditingController(text: existing?.notes ?? '');

  await showDialog<void>(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: Text(existing == null ? 'Tambah Pelanggan' : 'Edit Pelanggan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama Pelanggan'),
            ),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'No. WhatsApp / HP'),
            ),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (Opsional)'),
            ),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Catatan'),
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
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            final cust = PosCustomer(
              id: existing?.id ??
                  'cust_${DateTime.now().microsecondsSinceEpoch}',
              name: name,
              phone: phoneCtrl.text.trim(),
              email: emailCtrl.text.trim(),
              notes: notesCtrl.text.trim(),
              totalSpent: existing?.totalSpent ?? 0,
              visitCount: existing?.visitCount ?? 0,
              createdAt: existing?.createdAt ?? DateTime.now(),
            );
            await pos.saveCustomer(cust);
            if (autoSelectOnAdd && existing == null) {
              pos.setSelectedCustomer(cust);
            }
            if (dCtx.mounted) Navigator.pop(dCtx);
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  nameCtrl.dispose();
  phoneCtrl.dispose();
  emailCtrl.dispose();
  notesCtrl.dispose();
}

// ==================== 4. TAB ANALITIK PENJUALAN & LAPORAN KEUANGAN ====================

class _PosReportsTab extends StatefulWidget {
  const _PosReportsTab();

  @override
  State<_PosReportsTab> createState() => _PosReportsTabState();
}

class _PosReportsTabState extends State<_PosReportsTab> {
  String _range = 'Hari Ini';

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final summary = pos.financialSummary(_range);
    final topProducts = pos.topSellingProducts(_range);
    final dailySeries = pos.dailySalesSeries(days: 7);
    final orders = pos.ordersInRange(_range);
    final expenses = pos.expensesInRange(_range);

    final maxDayRevenue = dailySeries.fold<double>(
      1.0,
      (m, e) => e.revenue > m ? e.revenue : m,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 40),
      children: [
        // Range chips + Export PDF
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final r in const ['Hari Ini', '7 Hari', '30 Hari', 'Semua'])
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
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.darkNav,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final f = await PosPdfService.exportFinancialReportPdf(
                  profile: pos.profile,
                  rangeLabel: _range,
                  summary: summary,
                  topProducts: topProducts,
                  orders: orders,
                  expenses: expenses,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('PDF disimpan: ${f.path}')),
                  );
                }
              },
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 17),
              label: const Text('Export PDF'),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Financial KPI Grid
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.1,
          children: [
            _KpiCard(
              label: 'Total Omzet (${summary.transactionCount} trx)',
              value: PosFormat.rupiah(summary.totalRevenue),
              color: AppColors.spotifyGreen,
            ),
            _KpiCard(
              label: 'Laba Kotor',
              value: PosFormat.rupiah(summary.grossProfit),
              color: AppColors.neonCyan,
            ),
            _KpiCard(
              label: 'Pengeluaran',
              value: PosFormat.rupiah(summary.totalExpenses),
              color: AppColors.netflixRed,
            ),
            _KpiCard(
              label: 'Laba Bersih',
              value: PosFormat.rupiah(summary.netProfit),
              color: const Color(0xFF1D8F52),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // 7-Day Sales Bar Chart
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Grafik Penjualan 7 Hari Terakhir',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 110,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final day in dailySeries)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: (day.revenue / maxDayRevenue)
                                      .clamp(0.06, 1.0),
                                  child: Container(
                                    width: 18,
                                    decoration: BoxDecoration(
                                      color: day.revenue > 0
                                          ? AppColors.spotifyGreen
                                          : AppColors.surfaceHighlight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              day.label,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Top Selling Products
        if (topProducts.isNotEmpty) ...[
          const Text(
            'Produk Terlaris',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 6),
          for (final p in topProducts)
            Card(
              color: AppColors.surfaceElevated,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: Text(
                  '${p.qty}x • ${PosFormat.rupiah(p.revenue)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.spotifyGreen,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],

        // Operational Expenses
        Row(
          children: [
            const Expanded(
              child: Text(
                'Catatan Pengeluaran',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
            TextButton.icon(
              onPressed: () => _showAddExpenseDialog(context, pos),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tambah'),
            ),
          ],
        ),
        if (expenses.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Belum ada pengeluaran tercatat pada periode ini.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          )
        else
          for (final e in expenses)
            Card(
              color: AppColors.surfaceElevated,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(
                  e.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('${e.category} • ${PosFormat.dateOnly(e.createdAt)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      PosFormat.rupiah(e.amount),
                      style: const TextStyle(
                        color: AppColors.netflixRed,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () => pos.deleteExpense(e.id),
                    ),
                  ],
                ),
              ),
            ),

        const SizedBox(height: 14),
        const Text(
          'Riwayat Transaksi',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 6),
        if (orders.isEmpty)
          const Text(
            'Belum ada transaksi pada periode ini.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          )
        else
          for (final o in orders.take(30))
            Card(
              color: AppColors.surfaceElevated,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                title: Text(
                  '${o.receiptNumber} • ${PosFormat.rupiah(o.total)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                subtitle: Text(
                  '${PosFormat.dateTime(o.createdAt)} • ${o.paymentMethod}${o.customerName != null ? ' • ${o.customerName}' : ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: const Icon(Icons.receipt_long_rounded),
                onTap: () => _PosReceiptActionsSheet.show(
                  context,
                  o,
                  pos.profile,
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _showAddExpenseDialog(
    BuildContext context,
    PosProvider pos,
  ) async {
    final titleCtrl = TextEditingController();
    final catCtrl = TextEditingController(text: 'Bahan Baku');
    final amountCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Tambah Pengeluaran'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Keterangan'),
            ),
            TextField(
              controller: catCtrl,
              decoration: const InputDecoration(labelText: 'Kategori'),
            ),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Jumlah (Rp)'),
            ),
          ],
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
              final fin = context.read<FinanceProvider>();
              final exp = PosExpense(
                id: 'exp_${DateTime.now().microsecondsSinceEpoch}',
                title: title,
                category: catCtrl.text.trim().isEmpty
                    ? 'Operasional'
                    : catCtrl.text.trim(),
                amount: amount,
                createdAt: DateTime.now(),
              );
              await pos.addExpense(exp);
              await fin.saveEntry(
                FinanceEntry(
                  id: 'fin_posexp_${exp.id}',
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
              if (dCtx.mounted) Navigator.pop(dCtx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    titleCtrl.dispose();
    catCtrl.dispose();
    amountCtrl.dispose();
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
