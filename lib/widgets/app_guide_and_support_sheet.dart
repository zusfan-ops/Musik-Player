import 'package:flutter/material.dart';

import '../services/backend_api_service.dart';
import '../theme/app_theme.dart';

Future<void> showAppGuideAndSupportSheet(
  BuildContext context, {
  int initialTab = 0,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AppGuideAndSupportSheet(initialTab: initialTab),
  );
}

class _AppGuideAndSupportSheet extends StatefulWidget {
  const _AppGuideAndSupportSheet({required this.initialTab});

  final int initialTab;

  @override
  State<_AppGuideAndSupportSheet> createState() =>
      _AppGuideAndSupportSheetState();
}

class _AppGuideAndSupportSheetState extends State<_AppGuideAndSupportSheet>
    with SingleTickerProviderStateMixin {
  final _api = BackendApiService.instance;
  late final TabController _tabController;

  // Tab 2: Submit Request / Support
  String _category = 'feature';
  final _messageCtrl = TextEditingController();
  bool _diagnosticsConsent = true;
  bool _submitting = false;

  // Tab 3: Tickets & 2-Way Chat
  List<Map<String, dynamic>> _tickets = const [];
  bool _loadingTickets = true;
  int? _selectedTicketId;
  final _replyCtrl = TextEditingController();
  bool _sendingReply = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _loadTickets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageCtrl.dispose();
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTickets() async {
    if (mounted) setState(() => _loadingTickets = true);
    final list = await _api.fetchFeedbackTickets();
    if (!mounted) return;
    if (_tabController.index == 2 || widget.initialTab == 2) {
      await _api.markAdminRepliesAsSeen(list);
      if (!mounted) return;
    }
    setState(() {
      _tickets = list;
      _loadingTickets = false;
      if (_selectedTicketId != null &&
          !_tickets.any((t) => t['id'] == _selectedTicketId)) {
        _selectedTicketId = null;
      }
    });
  }

  Future<void> _submitRequest() async {
    final msg = _messageCtrl.text.trim();
    if (msg.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tuliskan pesan minimal 5 karakter.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final res = await _api.submitFeedbackTicket(
      category: _category,
      message: msg,
      diagnosticsConsent: _diagnosticsConsent,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res['message']?.toString() ?? 'Selesai')),
    );

    if (res['ok'] == true) {
      _messageCtrl.clear();
      final created = res['data'];
      await _loadTickets();
      if (!mounted) return;
      if (created is Map<String, dynamic> && created['id'] is int) {
        setState(() => _selectedTicketId = created['id'] as int);
      }
      _tabController.animateTo(2);
    }
  }

  Future<void> _sendReply(int ticketId) async {
    final text = _replyCtrl.text.trim();
    if (text.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Balasan minimal 2 karakter.')),
      );
      return;
    }
    setState(() => _sendingReply = true);
    final res = await _api.replyFeedbackTicket(
      ticketId: ticketId,
      message: text,
    );
    if (!mounted) return;
    setState(() => _sendingReply = false);

    if (res['ok'] == true) {
      _replyCtrl.clear();
      await _loadTickets();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? 'Gagal mengirim balasan'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.9;
    return SizedBox(
      height: maxH,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.support_agent_rounded,
                  color: Color(0xFF38BDF8),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Panduan & Pusat Bantuan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: const Color(0xFF38BDF8),
            tabs: [
              const Tab(text: 'Panduan Fitur'),
              const Tab(text: 'Minta Bantuan / Fitur'),
              Tab(text: 'Chat Admin (${_tickets.length})'),
            ],
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGuideTab(),
                _buildRequestTab(),
                _buildTicketsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideTab() {
    const sections = [
      (
        icon: Icons.person_add_alt_1_rounded,
        color: Color(0xFF38BDF8),
        title: '1. Daftar Akun & Aktivasi Toko Online',
        steps: [
          'Buka menu Profil & Setting -> Masuk / Daftar Akun.',
          'Isi Nama, Email, No. HP/WhatsApp, dan Password.',
          'Centang "Aktifkan Toko Online" jika ingin langsung membuka toko di https://mediacenter.ordr.my.id/namatoko.',
          'Isi Nama Toko, Slug Domain (tanpa spasi), Jenis Toko (coffeeshop/retail/lainnya), dan Alamat Toko.',
        ],
      ),
      (
        icon: Icons.point_of_sale_rounded,
        color: Color(0xFF4ADE80),
        title: '2. Kelola Produk POS & Terima Order Konsumen',
        steps: [
          'Tambahkan produk/menu jualan di halaman POS (Kasir).',
          'Buka tombol "Toko Online & QR" di pojok kanan atas halaman POS, lalu klik "Simpan & Sinkronkan Produk" agar menu tampil di web toko Anda.',
          'Saat konsumen memesan dari web toko, mereka wajib mengisi Nama & No. WhatsApp (otomatis tersimpan ke database konsumen) dan order langsung masuk ke tab "Antrean Order".',
        ],
      ),
      (
        icon: Icons.qr_code_2_rounded,
        color: Color(0xFFF59E0B),
        title: '3. Cetak QR Code Toko & Meja Cafe',
        steps: [
          'Di halaman POS -> "Toko Online & QR", atur Jumlah Meja jika usaha Anda adalah Cafe/Coffeeshop.',
          'Pilih nomor meja di pratinjau QR Code (?meja=1, ?meja=2, dst.) atau pilih QR Toko Utama.',
          'Klik "Cetak / Simpan PDF QR" untuk mencetak QR Code ke meja pelanggan.',
        ],
      ),
      (
        icon: Icons.storefront_rounded,
        color: Color(0xFFFB923C),
        title: '4. Discovery Toko, GPS, Booking Meja & Analitik',
        steps: [
          'Toko aktif tampil secara acak di halaman Home ("Toko & Rekomendasi Pilihan") lengkap dengan produk, alamat, dan titik GPS.',
          'Pengguna yang sudah login dapat melakukan Booking Meja pada toko bertipe coffeeshop.',
          'Pemilik toko dapat melihat analitik jumlah pengunjung toko dan produk yang paling sering dilihat di menu "Toko Online & QR".',
        ],
      ),
      (
        icon: Icons.live_tv_rounded,
        color: Color(0xFFA78BFA),
        title: '5. TV Streaming, CCTV, Film, YouTube PiP & Musik',
        steps: [
          'Nikmati Live TV IPTV & CCTV Kota real-time dengan sinkronisasi M3U otomatis.',
          'Putar Film & Serial Jellyfin dengan daftar Lanjutkan Menonton.',
          'Putar YouTube dengan Background Play & jendela Picture-in-Picture (PiP) yang dapat digeser.',
          'Pindai folder musik lokal atau simpan audio M3U untuk diputar secara offline.',
        ],
      ),
      (
        icon: Icons.support_agent_rounded,
        color: Color(0xFF38BDF8),
        title: '6. Permintaan Bantuan, Fitur Baru & Chat Admin',
        steps: [
          'Gunakan tab "Minta Bantuan / Fitur" untuk melaporkan kendala atau mengusulkan fitur baru.',
          'Admin akan melihat detail laporan Anda di Admin Console dan dapat membalas langsung.',
          'Pantau status tiket dan balas pesan admin secara 2 arah melalui tab "Chat Admin".',
        ],
      ),
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, idx) {
        final s = sections[idx];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(s.icon, color: s.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...s.steps.map(
                (step) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                      Expanded(
                        child: Text(
                          step,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRequestTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Kirim Permintaan Bantuan atau Penambahan Fitur',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pesan Anda akan langsung masuk ke panel Admin untuk ditindaklanjuti. Anda dapat berdiskusi 2 arah di tab Chat Admin.',
          style: TextStyle(color: Colors.white60, fontSize: 12.5),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _category,
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Kategori Permintaan',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'feature',
              child: Text('Permintaan Penambahan Fitur'),
            ),
            DropdownMenuItem(
              value: 'other',
              child: Text('Permintaan Bantuan Penggunaan'),
            ),
            DropdownMenuItem(
              value: 'complaint',
              child: Text('Keluhan Layanan / POS'),
            ),
            DropdownMenuItem(
              value: 'bug',
              child: Text('Laporan Error / Bug'),
            ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _category = v);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _messageCtrl,
          maxLines: 5,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Jelaskan kebutuhan atau kendala Anda',
            hintText:
                'Contoh: Tolong tambahkan fitur cetak struk Bluetooth ukuran 80mm atau bantu setting QR meja...',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _diagnosticsConsent,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Sertakan info platform perangkat (tanpa path file lokal)',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          onChanged: (v) => setState(() => _diagnosticsConsent = v ?? true),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _submitting ? null : _submitRequest,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: Text(_submitting ? 'Mengirim...' : 'Kirim ke Admin'),
        ),
      ],
    );
  }

  Widget _buildTicketsTab() {
    if (_loadingTickets) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_tickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.forum_outlined,
                color: Colors.white38,
                size: 44,
              ),
              const SizedBox(height: 10),
              const Text(
                'Belum ada tiket bantuan atau permintaan fitur.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _tabController.animateTo(1),
                icon: const Icon(Icons.add_comment_rounded),
                label: const Text('Buat Permintaan Baru'),
              ),
            ],
          ),
        ),
      );
    }

    final selected = _selectedTicketId != null
        ? _tickets.cast<Map<String, dynamic>?>().firstWhere(
              (t) => t?['id'] == _selectedTicketId,
              orElse: () => null,
            )
        : null;

    if (selected != null) {
      return _buildThreadView(selected);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Pilih tiket untuk melihat & membalas pesan Admin',
                  style: TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
              ),
              IconButton(
                tooltip: 'Muat ulang',
                onPressed: _loadTickets,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            itemCount: _tickets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, idx) {
              final t = _tickets[idx];
              final id = t['id'] as int? ?? 0;
              final status = t['status']?.toString() ?? 'open';
              final category = t['category']?.toString() ?? 'other';
              final msgCount = (t['messages'] as List?)?.length ?? 1;
              return Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selectedTicketId = id),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Tiket #$id • ${category.toUpperCase()}',
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: status == 'resolved' || status == 'closed'
                                    ? const Color(0xFF22C55E)
                                        .withValues(alpha: 0.2)
                                    : const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: status == 'resolved' ||
                                          status == 'closed'
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFFFBBF24),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t['message']?.toString() ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 13,
                              color: Colors.white54,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$msgCount pesan • Ketuk untuk buka chat',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildThreadView(Map<String, dynamic> ticket) {
    final id = ticket['id'] as int? ?? 0;
    final status = ticket['status']?.toString() ?? 'open';
    final messages = (ticket['messages'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        const <Map<String, dynamic>>[];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: AppColors.surface,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => setState(() => _selectedTicketId = null),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tiket #$id (${ticket['category'] ?? ''})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Status: $status',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh chat',
                onPressed: _loadTickets,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: messages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, idx) {
              final m = messages[idx];
              final isAdmin = m['sender_type'] == 'admin';
              return Align(
                alignment:
                    isAdmin ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isAdmin
                        ? const Color(0xFF0EA5E9).withValues(alpha: 0.16)
                        : const Color(0xFF22C55E).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isAdmin
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.35)
                          : const Color(0xFF4ADE80).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAdmin
                            ? 'Admin (${m['sender_name'] ?? 'Support'})'
                            : 'Anda',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isAdmin
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFF4ADE80),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        m['body']?.toString() ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _replyCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Tulis balasan ke Admin...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _sendingReply ? null : () => _sendReply(id),
                child: _sendingReply
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
