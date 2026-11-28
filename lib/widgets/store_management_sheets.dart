import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../providers/pos_provider.dart';
import '../services/backend_api_service.dart';
import '../theme/app_theme.dart';

/// Store Settings, QR Code (Domain & Cafe Table), Online Order Queue (POS),
/// Table Bookings, and Store View Analytics sheet for registered store owners.
Future<void> showStoreSettingsAndQrSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _StoreManagementSheet(),
  );
}

class _StoreManagementSheet extends StatefulWidget {
  const _StoreManagementSheet();

  @override
  State<_StoreManagementSheet> createState() => _StoreManagementSheetState();
}

class _StoreManagementSheetState extends State<_StoreManagementSheet> {
  final _api = BackendApiService.instance;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _nameCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _waCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _tablesCtrl = TextEditingController(text: '10');
  String _storeType = 'coffeeshop';
  String _qrTable = '';

  Map<String, dynamic> _analytics = const {};
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _bookings = const [];
  List<Map<String, dynamic>> _customers = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _slugCtrl.dispose();
    _descCtrl.dispose();
    _addrCtrl.dispose();
    _waCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _tablesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = await _api.getToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Silakan login akun cloud di Profil & Setting untuk mengelola Toko Online.';
      });
      return;
    }

    final data = await _api.fetchMyStore();
    if (!mounted) return;
    if (data != null && data['store'] is Map<String, dynamic>) {
      final st = data['store'] as Map<String, dynamic>;
      _nameCtrl.text = st['name']?.toString() ?? '';
      _slugCtrl.text = st['slug']?.toString() ?? '';
      _descCtrl.text = st['description']?.toString() ?? '';
      _addrCtrl.text = st['address']?.toString() ?? '';
      _waCtrl.text = st['whatsapp_number']?.toString() ?? '';
      _latCtrl.text = st['latitude']?.toString() ?? '';
      _lngCtrl.text = st['longitude']?.toString() ?? '';
      _tablesCtrl.text = (st['tables_count'] ?? 10).toString();
      _storeType = st['store_type']?.toString() ?? 'coffeeshop';

      _analytics = (data['analytics'] as Map<String, dynamic>?) ?? const {};
      _orders = (data['orders'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      _bookings = (data['bookings'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      _customers = (data['customers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    setState(() => _loading = false);
  }

  Future<void> _saveAndSyncPosProducts() async {
    if (_nameCtrl.text.trim().length < 2 || _slugCtrl.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama toko dan domain (min. 3 huruf) wajib diisi.')),
      );
      return;
    }
    setState(() => _saving = true);
    final pos = context.read<PosProvider>();
    final productsPayload = pos.products
        .map(
          (prod) => {
            'client_uid': prod.id,
            'name': prod.name,
            'category': prod.category,
            'price': prod.price,
            'stock': prod.stock,
            'unit': prod.unit,
            'is_active': prod.isActive,
          },
        )
        .toList();

    final err = await _api.upsertMyStore(
      name: _nameCtrl.text,
      slug: _slugCtrl.text,
      storeType: _storeType,
      description: _descCtrl.text,
      address: _addrCtrl.text,
      latitude: double.tryParse(_latCtrl.text.trim()),
      longitude: double.tryParse(_lngCtrl.text.trim()),
      whatsappNumber: _waCtrl.text,
      tablesCount: int.tryParse(_tablesCtrl.text.trim()) ?? 0,
      products: productsPayload,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengaturan toko & produk POS tersinkron!')),
      );
      await _load();
    }
  }

  String get _qrTargetUrl {
    final slug = _slugCtrl.text.trim().toLowerCase();
    final base = 'https://mediacenter.ordr.my.id/$slug';
    if (_qrTable.isEmpty) return base;
    return '$base?meja=${Uri.encodeQueryComponent(_qrTable)}';
  }

  Future<void> _exportQrPdf() async {
    final slug = _slugCtrl.text.trim().toLowerCase();
    if (slug.isEmpty) return;
    final doc = pw.Document();
    final url = _qrTargetUrl;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (_) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                _nameCtrl.text.trim().isEmpty ? slug : _nameCtrl.text.trim(),
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              if (_qrTable.isNotEmpty) ...[
                pw.SizedBox(height: 6),
                pw.Text('Meja $_qrTable', style: const pw.TextStyle(fontSize: 16)),
              ],
              pw.SizedBox(height: 18),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: url,
                width: 200,
                height: 200,
              ),
              pw.SizedBox(height: 14),
              pw.Text('Scan untuk melihat menu & order:', style: const pw.TextStyle(fontSize: 12)),
              pw.Text(url, style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'qr-$slug${_qrTable.isEmpty ? '' : '-meja-$_qrTable'}.pdf'));
    await file.writeAsBytes(await doc.save());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'QR Menu ${_nameCtrl.text}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.storefront_rounded, color: AppColors.spotifyGreen),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Toko Online, QR & Antrean POS',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Pengaturan Toko'),
                Tab(text: 'QR Code & Meja'),
                Tab(text: 'Antrean Order'),
                Tab(text: 'Analisa & Konsumen'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, textAlign: TextAlign.center),
                          ),
                        )
                      : TabBarView(
                          children: [
                            // Tab 1: Pengaturan Toko
                            ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                TextField(
                                  controller: _nameCtrl,
                                  decoration: const InputDecoration(labelText: 'Nama Toko'),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _slugCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Domain Toko',
                                    prefixText: 'https://mediacenter.ordr.my.id/',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: _storeType,
                                  decoration: const InputDecoration(labelText: 'Jenis Toko'),
                                  items: const [
                                    DropdownMenuItem(value: 'coffeeshop', child: Text('Coffeeshop / Cafe')),
                                    DropdownMenuItem(value: 'resto', child: Text('Restoran / Kuliner')),
                                    DropdownMenuItem(value: 'retail', child: Text('Retail / Minimarket')),
                                    DropdownMenuItem(value: 'jasa', child: Text('Jasa')),
                                    DropdownMenuItem(value: 'umum', child: Text('Umum')),
                                  ],
                                  onChanged: (v) => setState(() => _storeType = v ?? 'umum'),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _addrCtrl,
                                  decoration: const InputDecoration(labelText: 'Alamat Toko'),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _waCtrl,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(labelText: 'No. WhatsApp Toko'),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _latCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                        decoration: const InputDecoration(labelText: 'Latitude GPS'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _lngCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                        decoration: const InputDecoration(labelText: 'Longitude GPS'),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_storeType == 'coffeeshop' || _storeType == 'resto') ...[
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _tablesCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Jumlah Meja (Cafe/Resto)'),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _saving ? null : _saveAndSyncPosProducts,
                                  icon: const Icon(Icons.cloud_upload_rounded),
                                  label: Text(_saving ? 'Menyimpan...' : 'Simpan Toko & Sinkron Produk POS'),
                                ),
                              ],
                            ),

                            // Tab 2: QR Code & Meja
                            ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                if (_slugCtrl.text.trim().isEmpty)
                                  const Text('Simpan domain toko di tab Pengaturan Toko terlebih dahulu.')
                                else ...[
                                  if (_storeType == 'coffeeshop' || _storeType == 'resto')
                                    DropdownButtonFormField<String>(
                                      initialValue: _qrTable,
                                      decoration: const InputDecoration(labelText: 'Pilih Meja (Opsional untuk Cafe)'),
                                      items: [
                                        const DropdownMenuItem(value: '', child: Text('Menu Umum (Tanpa Meja)')),
                                        for (int m = 1; m <= (int.tryParse(_tablesCtrl.text) ?? 10).clamp(1, 50); m++)
                                          DropdownMenuItem(value: '$m', child: Text('Meja $m')),
                                      ],
                                      onChanged: (v) => setState(() => _qrTable = v ?? ''),
                                    ),
                                  const SizedBox(height: 16),
                                  Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: QrImageView(
                                        data: _qrTargetUrl,
                                        size: 210,
                                        backgroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SelectableText(
                                    _qrTargetUrl,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _exportQrPdf,
                                    icon: const Icon(Icons.print_rounded),
                                    label: const Text('Cetak / Bagikan PDF QR Code'),
                                  ),
                                ],
                              ],
                            ),

                            // Tab 3: Antrean Order Online POS & Booking
                            ListView(
                              padding: const EdgeInsets.all(14),
                              children: [
                                Text('Antrean Order Online (${_orders.length})',
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 8),
                                if (_orders.isEmpty)
                                  const Text('Belum ada pesanan online masuk.')
                                else
                                  for (final ord in _orders)
                                    Card(
                                      child: ListTile(
                                        title: Text('${ord['order_code']} • ${ord['customer_name']}'),
                                        subtitle: Text(
                                          'WA: ${ord['customer_whatsapp']}'
                                          '${ord['table_number'] != null ? ' • ${ord['table_number']}' : ''}\n'
                                          'Total: Rp ${ord['total_amount']} • Status: ${ord['status']}',
                                        ),
                                        trailing: PopupMenuButton<String>(
                                          onSelected: (st) async {
                                            final id = (ord['id'] as num?)?.toInt() ?? 0;
                                            if (id > 0) {
                                              await _api.updateStoreOrderStatus(id, st);
                                              await _load();
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(value: 'preparing', child: Text('Proses')),
                                            PopupMenuItem(value: 'completed', child: Text('Selesai')),
                                            PopupMenuItem(value: 'cancelled', child: Text('Batalkan')),
                                          ],
                                        ),
                                      ),
                                    ),
                                const SizedBox(height: 14),
                                Text('Booking Meja (${_bookings.length})',
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 8),
                                if (_bookings.isEmpty)
                                  const Text('Belum ada booking meja.')
                                else
                                  for (final b in _bookings)
                                    Card(
                                      child: ListTile(
                                        title: Text('${b['customer_name']} • ${b['table_number']}'),
                                        subtitle: Text(
                                          'WA: ${b['customer_whatsapp']} • ${b['guests_count']} tamu • ${b['status']}',
                                        ),
                                      ),
                                    ),
                              ],
                            ),

                            // Tab 4: Analisa Toko & Konsumen
                            ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _StatChip('Dilihat', '${_analytics['views_count'] ?? 0}'),
                                    _StatChip('Konsumen', '${_analytics['customers_count'] ?? 0}'),
                                    _StatChip('Order', '${_analytics['orders_count'] ?? 0}'),
                                    _StatChip('Booking', '${_analytics['bookings_count'] ?? 0}'),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text('Produk Paling Banyak Dilihat',
                                    style: TextStyle(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 6),
                                for (final tp in (_analytics['top_products'] as List<dynamic>? ?? const []))
                                  ListTile(
                                    dense: true,
                                    title: Text((tp as Map)['name']?.toString() ?? ''),
                                    trailing: Text('${tp['views_count'] ?? 0} views'),
                                  ),
                                const Divider(),
                                const Text('Database Konsumen (Nama & WhatsApp)',
                                    style: TextStyle(fontWeight: FontWeight.w800)),
                                for (final c in _customers)
                                  ListTile(
                                    dense: true,
                                    title: Text(c['name']?.toString() ?? ''),
                                    subtitle: Text(c['whatsapp']?.toString() ?? ''),
                                    trailing: Text('${c['orders_count'] ?? 1}x order'),
                                  ),
                              ],
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $value'));
  }
}

/// Public store detail + products + GPS + Coffeeshop table booking sheet.
Future<void> showStoreDetailSheet(
  BuildContext context,
  Map<String, dynamic> store,
) async {
  final slug = store['slug']?.toString() ?? '';
  if (slug.isNotEmpty) {
    unawaited(BackendApiService.instance.trackStoreView(slug));
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final products = (store['products'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final isCoffee = store['store_type'] == 'coffeeshop';
      final lat = store['latitude'];
      final lng = store['longitude'];

      return SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.78,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_rounded, color: AppColors.spotifyGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    store['name']?.toString() ?? 'Toko',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                ),
                Chip(label: Text((store['store_type']?.toString() ?? 'umum').toUpperCase())),
              ],
            ),
            if (store['address'] != null && store['address'].toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Alamat: ${store['address']}'),
            ],
            if (lat != null && lng != null) ...[
              const SizedBox(height: 4),
              Text('GPS: $lat, $lng', style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 12),
            if (isCoffee)
              FilledButton.icon(
                onPressed: () => _showBookingDialog(ctx, store),
                icon: const Icon(Icons.table_restaurant_rounded),
                label: const Text('Booking Meja Coffeeshop (Khusus User Terdaftar)'),
              ),
            const SizedBox(height: 14),
            Text('Menu & Produk (${products.length})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            for (final p in products)
              Card(
                child: ListTile(
                  title: Text(p['name']?.toString() ?? ''),
                  subtitle: Text('Rp ${p['price'] ?? 0} / ${p['unit'] ?? 'pcs'}'),
                  onTap: () {
                    final pid = (p['id'] as num?)?.toInt();
                    if (slug.isNotEmpty && pid != null) {
                      unawaited(BackendApiService.instance.trackStoreView(slug, productId: pid));
                    }
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}

Future<void> _showBookingDialog(
  BuildContext context,
  Map<String, dynamic> store,
) async {
  final token = await BackendApiService.instance.getToken();
  if (!context.mounted) return;
  if (token == null || token.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hanya user yang sudah register & login yang bisa booking meja.'),
      ),
    );
    return;
  }
  final waCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  String tableNum = 'Meja 1';
  int guests = 2;

  await showDialog<void>(
    context: context,
    builder: (dlgCtx) => StatefulBuilder(
      builder: (dlgCtx, setDlg) => AlertDialog(
        title: Text('Booking Meja • ${store['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: tableNum,
              items: [
                for (int i = 1; i <= ((store['tables_count'] as num?)?.toInt() ?? 10).clamp(1, 50); i++)
                  DropdownMenuItem(value: 'Meja $i', child: Text('Meja $i')),
              ],
              onChanged: (v) => setDlg(() => tableNum = v ?? 'Meja 1'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: waCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'No. WhatsApp Anda'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              final err = await BackendApiService.instance.bookCoffeeshopTable(
                slug: store['slug']?.toString() ?? '',
                tableNumber: tableNum,
                guestsCount: guests,
                bookingTime: DateTime.now().add(const Duration(hours: 2)),
                customerWhatsapp: waCtrl.text,
                notes: notesCtrl.text,
              );
              if (dlgCtx.mounted) Navigator.pop(dlgCtx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err ?? 'Booking $tableNum berhasil dikirim!')),
                );
              }
            },
            child: const Text('Booking Sekarang'),
          ),
        ],
      ),
    ),
  );
  waCtrl.dispose();
  notesCtrl.dispose();
}

/// Disguised Native Ad Card (Image or Video) blended between home cards.
class NativeAdCard extends StatefulWidget {
  final Map<String, dynamic> ad;
  const NativeAdCard({super.key, required this.ad});

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  VideoPlayerController? _videoCtrl;

  @override
  void initState() {
    super.initState();
    final mediaType = widget.ad['media_type']?.toString() ?? 'image';
    final url = widget.ad['media_url']?.toString() ?? '';
    if (mediaType == 'video' && url.startsWith('http')) {
      _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(url))
        ..setLooping(true)
        ..setVolume(0)
        ..initialize().then((_) {
          if (mounted) {
            _videoCtrl?.play();
            setState(() {});
          }
        }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.ad['title']?.toString() ?? '';
    final desc = widget.ad['description']?.toString() ?? '';
    final mediaUrl = widget.ad['media_url']?.toString() ?? '';
    final mediaType = widget.ad['media_type']?.toString() ?? 'image';
    final adId = (widget.ad['id'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () {
        if (adId > 0) {
          unawaited(BackendApiService.instance.trackAdClick(adId));
        }
      },
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.highlight(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 112,
              width: double.infinity,
              child: mediaType == 'video' &&
                      _videoCtrl != null &&
                      _videoCtrl!.value.isInitialized
                  ? VideoPlayer(_videoCtrl!)
                  : Image.network(
                      mediaUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: AppColors.elevated(context),
                        child: const Center(child: Icon(Icons.campaign_rounded)),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: AppColors.subtext(context)),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Disponsori',
                    style: TextStyle(fontSize: 10, color: AppColors.subtext(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
