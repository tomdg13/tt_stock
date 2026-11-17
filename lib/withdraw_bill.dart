import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'api.dart';
import 'product_images.dart' show productImageUrl;

/// ໃບເບີກອາໄຫຼ່: one withdrawal as a bill, print or share as PDF.
/// [data] = one row of GET /withdrawals (withdrawNo, branchName, createdAt,
/// createdBy, note, barcode, atmId, items[]).
class WithdrawBillPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const WithdrawBillPage(this.data, {super.key});
  @override
  State<WithdrawBillPage> createState() => _WithdrawBillPageState();
}

class _WithdrawBillPageState extends State<WithdrawBillPage> {
  late Map<String, dynamic> _d = widget.data;
  final _key = GlobalKey();
  bool _busy = false;
  final Map<String, String> _img = {};
  Future<void>? _imgLoad;

  @override
  void initState() {
    super.initState();
    _imgLoad = _loadImages();
  }

  /// First image of every part on the bill (GET /products/:id/images).
  Future<void> _loadImages() async {
    final items = _d['items'] is List ? _d['items'] as List : const [];
    for (final it in items) {
      if (it is! Map) continue;
      final id = '${it['productId'] ?? ''}';
      if (id.isEmpty || _img.containsKey(id)) continue;
      _img[id] = '';
      try {
        final d = await Api.get('/products/${Uri.encodeComponent(id)}/images');
        if (d is List && d.isNotEmpty && d.first is Map) {
          final u = '${(d.first as Map)['url'] ?? ''}';
          if (u.isNotEmpty) _img[id] = u;
        }
      } catch (_) {
        _img[id] = '';
      }
    }
    if (mounted) setState(() {});
  }

  /// The PDF is a picture of the sheet: wait until every part image is loaded.
  Future<void> _waitImages() async {
    await _imgLoad;
    if (!mounted) return;
    for (final u in _img.values) {
      if (u.isEmpty) continue;
      try {
        await precacheImage(NetworkImage(productImageUrl(u)), context)
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
      if (!mounted) return;
    }
    await WidgetsBinding.instance.endOfFrame;
  }

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

  Future<Uint8List> _pdf() async {
    await _waitImages();
    final obj = _key.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) throw Exception('ໜ້າຍັງບໍ່ພ້ອມ');
    final image = await obj.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw Exception('ສ້າງຮູບບໍ່ໄດ້');
    final img = pw.MemoryImage(data.buffer.asUint8List());
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (_) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
    ));
    return doc.save();
  }

  Future<void> _run(Future<void> Function(Uint8List) fn) async {
    setState(() => _busy = true);
    try {
      await fn(await _pdf());
    } catch (e) {
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
    return Container(
      width: 595,
      color: Colors.white,
      padding: const EdgeInsets.all(32),
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
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
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
              Row(children: [sign('ຜູ້ເບີກ'), sign('ຜູ້ອະນຸມັດ')]),
              const SizedBox(height: 16),
            ]),
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
          FittedBox(
            fit: BoxFit.fitWidth,
            child: RepaintBoundary(key: _key, child: _sheet()),
          ),
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
