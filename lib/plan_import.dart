// Import a supplier document (invoice / pro forma / quotation / PO) -> review -> draft Purchase Plan.
// Server: POST /plans/import/preview (multipart "file"), POST /plans/import (multipart "file" + "data" JSON)
// Open with:  Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanImportPage()));
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api.dart';
import 'pages.dart' show pickProduct;
import 'widgets.dart' show pick;

const _cur = ['LAK', 'THB', 'USD', 'CNY'];

MediaType _mime(String n) {
  final l = n.toLowerCase();
  if (l.endsWith('.pdf')) return MediaType('application', 'pdf');
  if (l.endsWith('.png')) return MediaType('image', 'png');
  if (l.endsWith('.webp')) return MediaType('image', 'webp');
  return MediaType('image', 'jpeg');
}

String _fmt(dynamic v) {
  final n = v is num ? v : (num.tryParse('$v') ?? 0);
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

double _d(String s) => double.tryParse(s.trim().replaceAll(',', '')) ?? 0;

Future<Map<String, dynamic>> _upload(String path, PlatformFile f,
    [Map<String, String> fields = const {}]) async {
  final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final req = http.MultipartRequest('POST', Uri.parse('$base$path'));
  if (Api.token != null) req.headers['Authorization'] = 'Bearer ${Api.token}';
  req.fields.addAll(fields);
  final bytes = await f.readAsBytes();
  req.files.add(http.MultipartFile.fromBytes('file', bytes,
      filename: f.name, contentType: _mime(f.name)));
  final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 150)));
  dynamic d;
  try {
    d = jsonDecode(utf8.decode(res.bodyBytes));
  } catch (_) {}
  if (res.statusCode >= 400) {
    var msg = 'Error ${res.statusCode}';
    if (d is Map && d['message'] != null) {
      final m = d['message'];
      msg = m is List ? m.join('\n') : '$m';
    }
    throw Exception(msg);
  }
  return Map<String, dynamic>.from(d as Map);
}

Future<List<Map<String, dynamic>>> _list(String p) async {
  final d = await Api.get(p);
  return d is List ? d.map((e) => Map<String, dynamic>.from(e)).toList() : [];
}

class _L {
  bool on = true;
  bool create = false;
  int? productId;
  String? productName;
  final String partNo, desc;
  final double? lastPrice;
  final TextEditingController qty, price;
  _L(Map m)
      : partNo = '${m['partNo'] ?? ''}',
        desc = '${m['description'] ?? ''}',
        productId = m['productId'] is num ? (m['productId'] as num).toInt() : null,
        productName = m['productName']?.toString(),
        lastPrice = m['lastPrice'] is num ? (m['lastPrice'] as num).toDouble() : null,
        qty = TextEditingController(text: _fmt(m['qty'])),
        price = TextEditingController(text: _fmt(m['unitPrice'])) {
    create = productId == null;
  }
  double get total => _d(qty.text) * _d(price.text);
}

class PlanImportPage extends StatefulWidget {
  const PlanImportPage({super.key});
  @override
  State<PlanImportPage> createState() => _PlanImportPageState();
}

class _PlanImportPageState extends State<PlanImportPage> {
  PlatformFile? _file;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _prev;
  List<_L> _lines = [];
  List<String> _warn = [];
  List<Map<String, dynamic>> _vendors = [], _brands = [], _branches = [];
  String _vendorId = '__new__';
  String? _brandId, _branchId, _currency;
  final _newVendor = TextEditingController();
  final _po = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final r = await Future.wait(
            [_list('/vendors'), _list('/brands'), _list('/branches')]);
        if (mounted) setState(() { _vendors = r[0]; _brands = r[1]; _branches = r[2]; });
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    }();
  }

  Future<void> _choose() async {
    final r = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp']);
    if (r.isEmpty) return;
    setState(() { _file = r.first; _busy = true; _error = null; _prev = null; });
    try {
      final d = await _upload('/plans/import/preview', _file!);
      final doc = Map<String, dynamic>.from(d['doc'] ?? {});
      if (!mounted) return;
      setState(() {
        _prev = d;
        _lines = (d['lines'] as List).map((e) => _L(Map<String, dynamic>.from(e))).toList();
        _warn = (d['warnings'] as List? ?? []).map((e) => '$e').toList();
        _vendorId = d['vendor'] != null ? '${d['vendor']['id']}' : '__new__';
        _newVendor.text = '${doc['vendorName'] ?? ''}';
        _brandId = d['brandId']?.toString();
        _currency = _cur.contains(doc['currency']) ? doc['currency'] : null;
        _po.text = '${d['suggestedPoNo'] ?? ''}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFor(_L l) async {
    final p = await pickProduct(context);
    if (p == null) return;
    setState(() {
      l.productId = int.tryParse(pick(p, ['id']));
      l.productName = pick(p, ['name']);
      l.create = false;
    });
  }

  Future<void> _save() async {
    final sel = _lines.where((l) => l.on).toList();
    String? err;
    if (_brandId == null) err = 'ເລືອກ BRAND';
    else if (_branchId == null) err = 'ເລືອກສາຂາປາຍທາງ';
    else if (_currency == null) err = 'ເລືອກສະກຸນເງິນ';
    else if (_po.text.trim().isEmpty) err = 'ໃສ່ເລກ PO';
    else if (_vendorId == '__new__' && _newVendor.text.trim().isEmpty) err = 'ໃສ່ຊື່ Vendor';
    else if (sel.isEmpty) err = 'ບໍ່ມີລາຍການທີ່ເລືອກ';
    else if (sel.any((l) => _d(l.qty.text) <= 0)) err = 'ຈຳນວນຕ້ອງຫຼາຍກວ່າ 0';
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final doc = _prev!['doc'];
      final body = {
        'vendorId': _vendorId == '__new__' ? null : int.parse(_vendorId),
        'newVendorName': _newVendor.text.trim(),
        'brandId': int.parse(_brandId!),
        'destBranchId': int.parse(_branchId!),
        'currency': _currency,
        'poNo': _po.text.trim(),
        'note': _note.text.trim(),
        'doc': doc,
        'lines': [
          for (final l in sel)
            {
              'productId': l.productId,
              'create': l.productId == null && l.create,
              'partNo': l.partNo,
              'description': l.desc,
              'qty': _d(l.qty.text),
              'unitPrice': _d(l.price.text),
            }
        ],
      };
      final r = await _upload('/plans/import', _file!, {'data': jsonEncode(body)});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ສ້າງແຜນ ${r['planNo']} ແລ້ວ (${r['items']} ລາຍການ)')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dd(String label, String? value, List<Map<String, dynamic>> items,
      void Function(String?) onCh, {bool addNew = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [
          if (addNew) const DropdownMenuItem(value: '__new__', child: Text('+ ສ້າງ Vendor ໃໝ່')),
          for (final m in items)
            DropdownMenuItem(value: '${m['id']}', child: Text(pick(m, ['name']), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onCh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = _prev == null ? null : Map<String, dynamic>.from(_prev!['doc']);
    final sum = _lines.where((l) => l.on).fold<double>(0, (s, l) => s + l.total);
    return Scaffold(
      appBar: AppBar(title: const Text('ນຳເຂົ້າເອກະສານ')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          FilledButton.icon(
            onPressed: _busy ? null : _choose,
            icon: const Icon(Icons.upload_file),
            label: Text(_file == null ? 'ເລືອກໄຟລ໌ (PDF / ຮູບ)' : _file!.name, overflow: TextOverflow.ellipsis),
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_busy && _prev == null) const Center(child: Text('ກຳລັງອ່ານເອກະສານ... (ອາດໃຊ້ເວລາ 10-40 ວິນາທີ)')),
          if (_error != null)
            Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Colors.red.shade900)))),
          if (doc != null) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${doc['docType']}  ${doc['docNo'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${doc['vendorName'] ?? ''}   ${doc['docDate'] ?? ''}'),
                  Text('Freight ${_fmt(doc['freight'])} · Bank ${_fmt(doc['bankCharge'])} · VAT ${_fmt(doc['vat'])} · Total ${doc['total'] == null ? '-' : _fmt(doc['total'])}'),
                ]),
              ),
            ),
            for (final w in _warn)
              Card(color: Colors.orange.shade50, child: ListTile(dense: true, leading: const Icon(Icons.warning_amber, color: Colors.orange), title: Text(w))),
            const SizedBox(height: 8),
            _dd('Vendor', _vendorId, _vendors, (v) => setState(() => _vendorId = v ?? '__new__'), addNew: true),
            if (_vendorId == '__new__')
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(controller: _newVendor, decoration: const InputDecoration(labelText: 'ຊື່ Vendor ໃໝ່', border: OutlineInputBorder())),
              ),
            _dd('BRAND', _brandId, _brands, (v) => setState(() => _brandId = v)),
            _dd('ສາຂາປາຍທາງ', _branchId, _branches, (v) => setState(() => _branchId = v)),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<String>(
                value: _currency,
                decoration: const InputDecoration(labelText: 'ສະກຸນເງິນ', border: OutlineInputBorder()),
                items: [for (final c in _cur) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setState(() => _currency = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(controller: _po, decoration: const InputDecoration(labelText: 'ເລກ PO', border: OutlineInputBorder())),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(controller: _note, decoration: const InputDecoration(labelText: 'ໝາຍເຫດ (ບໍ່ບັງຄັບ)', border: OutlineInputBorder())),
            ),
            Text('ລາຍການ (${_lines.where((l) => l.on).length}/${_lines.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            for (final l in _lines) _lineCard(l),
            const SizedBox(height: 8),
            Text('ລວມ: ${sum.toStringAsFixed(2)} ${_currency ?? ''}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('ບັນທຶກເປັນແຜນຈັດຊື້ (draft)')),
            const SizedBox(height: 24),
          ],
        ]),
      ),
    );
  }

  Widget _lineCard(_L l) {
    final matched = l.productId != null;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: !l.on ? Colors.grey : matched ? Colors.green : Colors.orange, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Checkbox(value: l.on, onChanged: (v) => setState(() => l.on = v ?? true)),
            Expanded(child: Text(l.desc, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
          if (l.partNo.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 12), child: Text('P/N ${l.partNo}', style: const TextStyle(fontSize: 12))),
          if (l.on) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: matched
                  ? Row(children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 18),
                      const SizedBox(width: 4),
                      Expanded(child: Text(l.productName ?? '', overflow: TextOverflow.ellipsis)),
                      TextButton(onPressed: () => _pickFor(l), child: const Text('ປ່ຽນ')),
                      TextButton(onPressed: () => setState(() { l.productId = null; l.productName = null; l.create = true; }), child: const Text('ຍົກເລີກ')),
                    ])
                  : Row(children: [
                      const Icon(Icons.fiber_new, color: Colors.orange, size: 18),
                      const SizedBox(width: 4),
                      Expanded(child: Row(children: [
                        Switch(value: l.create, onChanged: (v) => setState(() => l.create = v)),
                        const Flexible(child: Text('ສ້າງສິນຄ້າໃໝ່', overflow: TextOverflow.ellipsis)),
                      ])),
                      TextButton(onPressed: () => _pickFor(l), child: const Text('ເລືອກສິນຄ້າ')),
                    ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(children: [
                Expanded(child: TextField(controller: l.qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'ຈຳນວນ', isDense: true, border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: l.price, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'ລາຄາ', helperText: l.lastPrice == null ? null : 'ຄັ້ງກ່ອນ ${_fmt(l.lastPrice)}', isDense: true, border: const OutlineInputBorder()))),
                const SizedBox(width: 8),
                Text(l.total.toStringAsFixed(2)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
