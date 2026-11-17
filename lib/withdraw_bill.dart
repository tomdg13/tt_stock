import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'api.dart';

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
                columnWidths: const {
                  0: FixedColumnWidth(56),
                  1: FlexColumnWidth(3),
                  2: FixedColumnWidth(70),
                },
                children: [
                  TableRow(children: [
                    cell('ລຳດັບ', head: true),
                    cell('ຊື່ອາໄຫຼ່', head: true),
                    cell('ຈຳນວນ', head: true),
                  ]),
                  for (var n = 0; n < items.length; n++)
                    TableRow(children: [
                      cell('${n + 1}'),
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
