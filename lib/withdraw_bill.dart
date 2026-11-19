import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'api.dart';
import 'withdraw_docs.dart';
import 'ldb_letterhead.dart' show LdbLetterhead, loadLetterhead;
import 'price_report_export.dart' show buildWithdrawalPdf;
import 'product_images.dart' show productImageUrl;

/// ໃບເບີກອາໄຫຼ່: one withdrawal as a bill. The preview shows the LDB letterhead;
/// print / share build the PDF with buildWithdrawalPdf (same method as the price
/// report: letterhead as page background, Lao words as images).
/// [data] = one row of GET /withdrawals.
class WithdrawBillPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const WithdrawBillPage(this.data, {super.key});
  @override
  State<WithdrawBillPage> createState() => _WithdrawBillPageState();
}

class _WithdrawBillPageState extends State<WithdrawBillPage> {
  late Map<String, dynamic> _d = widget.data;
  bool _busy = false;
  final Map<String, String> _img = {};
  LdbLetterhead? _lh;
  Future<void>? _loading;

  String get _name => '${_d['withdrawNo'] ?? 'withdraw'}';

  static String _s(dynamic v) => v == null ? '' : '$v';

  static String _stLabel(String st) => st == 'requested'
      ? 'ລໍຖ້າອະນຸມັດ (ຍັງບໍ່ຕັດສະຕັອກ)'
      : st == 'open'
          ? 'ອະນຸມັດແລ້ວ (ຕັດສະຕັອກແລ້ວ)'
          : st == 'closed'
              ? 'ປິດແລ້ວ'
              : st;

  static String _when(dynamic v) {
    final s = _s(v);
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    final l = d.toLocal();
    String t(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${t(l.month)}-${t(l.day)} ${t(l.hour)}:${t(l.minute)}';
  }

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[WD] bill page open: no=${_d['withdrawNo']} status=${_d['status']} items=${(_d['items'] as List?)?.length ?? 0}');
    _loading = _loadAll();
  }

  /// Letterhead (same as the price report) + first image of every part.
  Future<void> _loadAll() async {
    try {
      final l = await loadLetterhead();
      if (mounted) setState(() => _lh = l);
      debugPrint('[WD] bill: letterhead ready');
    } catch (e) {
      debugPrint('[WD] bill: letterhead FAILED: $e');
    }
    final items = _d['items'] is List ? _d['items'] as List : const [];
    for (final it in items) {
      if (it is! Map) continue;
      final id = '${it['productId'] ?? ''}';
      if (id.isEmpty || _img.containsKey(id)) continue;
      _img[id] = '';
      try {
        final d = await Api.get('/products/${Uri.encodeComponent(id)}/images');
        if (d is List && d.isNotEmpty && d.first is Map) {
          _img[id] = '${(d.first as Map)['url'] ?? ''}';
        }
      } catch (e) {
        debugPrint('[WD] bill: image $id FAILED: $e');
      }
    }
    if (mounted) setState(() {});
  }

  /// Adds the ATM's model / location / branch (GET /atms/:id) for the letter table.
  Future<Map<String, dynamic>> _withAtm() async {
    final m = Map<String, dynamic>.from(_d);
    final atmId = '${_d['atmId'] ?? ''}';
    if (atmId.isNotEmpty) {
      try {
        final a = await Api.get('/atms/${Uri.encodeComponent(atmId)}');
        if (a is Map) {
          m['atmModel'] = '${a['atmVersion'] ?? ''}';
          m['atmLocation'] = '${a['atmLocation'] ?? ''}';
          m['atmBranch'] = '${a['atmBranchId'] ?? ''}'
              .replaceFirst(RegExp(r'^[A-Z0-9]+-\d+\s+'), '');
        }
      } catch (e) {
        debugPrint('[WD] bill: atm lookup failed: $e');
      }
    }
    return m;
  }

  Future<Uint8List> _pdf() async {
    await _loading;
    final urls = <String, String>{
      for (final e in _img.entries)
        if (e.value.isNotEmpty) e.key: productImageUrl(e.value),
    };
    debugPrint('[WD] bill: buildWithdrawalPdf no=$_name images=${urls.length}');
    final bytes = await buildWithdrawalPdf(await _withAtm(), urls);
    debugPrint('[WD] bill: PDF built ${bytes.length} bytes');
    return bytes;
  }

  Future<void> _run(Future<void> Function(Uint8List) fn) async {
    setState(() => _busy = true);
    try {
      await fn(await _pdf());
    } catch (e) {
      debugPrint('[WD] bill: PDF/print FAILED: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ອະນຸມັດເບີກ'),
        content: const Text('ຈະຕັດສະຕັອກອາໄຫຼ່ຕາມໃບນີ້ທັນທີ. ດຳເນີນການຕໍ່ບໍ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('ຢືນຢັນ')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await Api.post('/withdrawals/${_d['id']}/approve', {});
      final list = await Api.get('/withdrawals');
      if (list is List) {
        for (final w in list) {
          if (w is Map && '${w['id']}' == '${_d['id']}') {
            _d = Map<String, dynamic>.from(w);
            break;
          }
        }
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ອະນຸມັດແລ້ວ ຕັດສະຕັອກແລ້ວ')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reloads this withdrawal (document status changes after an upload).
  Future<void> _reloadD() async {
    try {
      final list = await Api.get('/withdrawals');
      if (list is List) {
        for (final w in list) {
          if (w is Map && '${w['id']}' == '${_d['id']}') {
            if (mounted) setState(() => _d = Map<String, dynamic>.from(w));
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('[WD] bill: reload failed: $e');
    }
  }

  Widget _sheet() {
    final d = _d;
    final items = d['items'] is List ? d['items'] as List : const [];
    const base = TextStyle(color: Colors.black, fontSize: 14, height: 1.4);
    const bold = TextStyle(
        color: Colors.black,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.4);
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: bold)),
            Expanded(child: Text(v.isEmpty ? '-' : v, style: base)),
          ]),
        );
    Widget cell(String t, {bool head = false}) => Padding(
          padding: const EdgeInsets.all(6),
          child: Text(t, style: head ? bold : base),
        );
    Widget pic(String id) {
      final url = productImageUrl(_img[id] ?? '');
      return Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          width: 48,
          height: 48,
          child: url.isEmpty
              ? const Icon(Icons.memory, color: Colors.black38)
              : Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.memory, color: Colors.black38)),
        ),
      );
    }

    Widget sign(String title) => Expanded(
          child: Column(children: [
            const SizedBox(height: 64),
            Container(
                height: 1,
                color: Colors.black54,
                margin: const EdgeInsets.symmetric(horizontal: 16)),
            const SizedBox(height: 4),
            Text(title, style: bold),
            const SizedBox(height: 4),
            const Text('ວັນທີ ........../........../..........', style: base),
          ]),
        );
    final bc = _s(d['barcode']);
    final atm = _s(d['atmId']);
    final lh = _lh;
    return Container(
      width: 595,
      constraints: const BoxConstraints(minHeight: 842),
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (lh != null)
                Image.memory(lh.headerPng,
                    width: 595, height: 595 * lh.headerRatio, fit: BoxFit.fill),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
                child: DefaultTextStyle(
                  style: base,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('ໃບເບີກອາໄຫຼ່',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 24,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('ເລກທີ່: ${_s(d['withdrawNo'])}',
                            textAlign: TextAlign.center, style: bold),
                        const SizedBox(height: 16),
                        kv('ວັນທີ', _when(d['createdAt'])),
                        kv('ສາຂາ', _s(d['branchName'])),
                        kv('ຜູ້ບັນທຶກ', _s(d['createdBy'])),
                        kv('ສະຖານະ', _stLabel(_s(d['status']))),
                        if (atm.isNotEmpty) kv('ຕູ້ ATM', atm),
                        if (bc.isNotEmpty) kv('Terminal', bc),
                        const SizedBox(height: 12),
                        const Text('ລາຍການອາໄຫຼ່ທີ່ເບີກ', style: bold),
                        const SizedBox(height: 6),
                        Table(
                          border: TableBorder.all(color: Colors.black54),
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          columnWidths: const {
                            0: FixedColumnWidth(48),
                            1: FixedColumnWidth(60),
                            2: FlexColumnWidth(3),
                            3: FixedColumnWidth(64),
                          },
                          children: [
                            TableRow(children: [
                              cell('ລຳດັບ', head: true),
                              cell('ຮູບ', head: true),
                              cell('ຊື່ອາໄຫຼ່', head: true),
                              cell('ຈຳນວນ', head: true),
                            ]),
                            for (var n = 0; n < items.length; n++)
                              TableRow(children: [
                                cell('${n + 1}'),
                                pic('${(items[n] as Map)['productId'] ?? ''}'),
                                cell(_s((items[n] as Map)['productName'])),
                                cell(_s((items[n] as Map)['qty'])),
                              ]),
                          ],
                        ),
                        const SizedBox(height: 12),
                        kv('ໝາຍເຫດ', _s(d['note'])),
                        const SizedBox(height: 24),
                        Row(children: [
                          sign('ຜູ້ເບີກ'),
                          sign('ຜູ້ອະນຸມັດ'),
                        ]),
                      ]),
                ),
              ),
            ],
          ),
          if (lh != null)
            Image.memory(lh.footerPng,
                width: 595, height: 595 * lh.footerRatio, fit: BoxFit.fill),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ໃບເບີກອາໄຫຼ່ · $_name')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          FittedBox(fit: BoxFit.fitWidth, child: _sheet()),
          if ('${_d['status']}' == 'open' || '${_d['status']}' == 'closed') ...[
            const SizedBox(height: 16),
            WithdrawDocsSection(_d, onChanged: _reloadD),
          ],
          if ('${_d['status']}' == 'requested') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _busy ? null : _approve,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('ອະນຸມັດເບີກ (ຕັດສະຕັອກ)'),
              ),
            ),
          ],
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run((bytes) async {
                          await Printing.layoutPdf(
                              onLayout: (_) async => bytes, name: _name);
                        }),
                icon: const Icon(Icons.print_outlined),
                label: const Text('ພິມ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run((bytes) async {
                          await Printing.sharePdf(
                              bytes: bytes, filename: '$_name.pdf');
                        }),
                icon: const Icon(Icons.ios_share),
                label: const Text('ແຊຣ໌ PDF'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
