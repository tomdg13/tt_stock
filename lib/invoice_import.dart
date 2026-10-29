// Import a supplier invoice / pro-forma PDF on the receive page:
// pick PDF -> server reads the item lines -> preview (edit / untick) -> confirm.
// Confirm creates the PO (if new) with the PDF as its document, new products (with the part no as barcode)
// and a goods receipt (stock in). Everything is recorded with the logged-in user.
// Server: POST /imports/invoice/parse, POST /imports/invoice/commit, GET /imports/receipts
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

class InvoiceImportButton extends StatelessWidget {
  final VoidCallback onDone;
  const InvoiceImportButton({super.key, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: FilledButton.tonalIcon(
          onPressed: () async {
            final ok = await importInvoice(context);
            if (ok) onDone();
          },
          icon: const Icon(Icons.upload_file),
          label: const Text('ນຳເຂົ້າເອກະສານ (PDF)'),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        tooltip: 'ປະຫວັດນຳເຂົ້າ',
        icon: const Icon(Icons.history),
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const InvoiceHistoryPage())),
      ),
    ]);
  }
}

Future<Map<String, dynamic>> _upload(PlatformFile f) async {
  final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final req =
      http.MultipartRequest('POST', Uri.parse('$base/imports/invoice/parse'));
  if (Api.token != null) req.headers['Authorization'] = 'Bearer ${Api.token}';
  req.files.add(http.MultipartFile.fromBytes('file', await f.readAsBytes(),
      filename: f.name, contentType: MediaType('application', 'pdf')));
  final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 120)));
  final body = utf8.decode(res.bodyBytes);
  if (res.statusCode >= 400) {
    var msg = 'Error ${res.statusCode}';
    try {
      final d = jsonDecode(body);
      if (d is Map && d['message'] != null) {
        msg = d['message'] is List
            ? (d['message'] as List).join('\n')
            : '${d['message']}';
      }
    } catch (_) {}
    throw Exception(msg);
  }
  return Map<String, dynamic>.from(jsonDecode(body) as Map);
}

/// returns true when something was imported
Future<bool> importInvoice(BuildContext context) async {
  final picked = await FilePicker.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf']);
  if (picked.isEmpty || !context.mounted) return false;
  final nav = Navigator.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        CircularProgressIndicator(),
        SizedBox(width: 16),
        Expanded(child: Text('ກຳລັງອ່ານເອກະສານ…')),
      ]),
    ),
  );
  Map<String, dynamic>? data;
  String? err;
  try {
    data = await _upload(picked.first);
  } catch (e) {
    err = '$e';
  }
  nav.pop();
  if (!context.mounted) return false;
  if (data == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? 'ອ່ານບໍ່ໄດ້')));
    return false;
  }
  final ok = await Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => InvoicePreviewPage(data!)));
  return ok == true;
}

String _n(dynamic v) {
  final d = num.tryParse('$v') ?? 0;
  return d == d.roundToDouble() ? d.toStringAsFixed(0) : '$d';
}

class _Ln {
  final Map<String, dynamic> src;
  bool on = true;
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController cost;
  dynamic brandId;
  _Ln(this.src)
      : name = TextEditingController(text: pick(src, ['description'])),
        qty = TextEditingController(text: _n(src['qty'])),
        cost = TextEditingController(text: _n(src['unitPrice'])),
        brandId = src['brandId'];
  String get partNo => pick(src, ['partNo']);
  bool get isNew => src['productId'] == null;
  void dispose() {
    name.dispose();
    qty.dispose();
    cost.dispose();
  }
}

class InvoicePreviewPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const InvoicePreviewPage(this.data, {super.key});
  @override
  State<InvoicePreviewPage> createState() => _InvoicePreviewPageState();
}

class _InvoicePreviewPageState extends State<InvoicePreviewPage> {
  late final TextEditingController _po =
      TextEditingController(text: pick(widget.data, ['poNo']));
  final _note = TextEditingController();
  late final List<_Ln> _lines = [
    for (final m in asList(widget.data['lines'])) _Ln(m)
  ];
  late final List<Map<String, dynamic>> _brands = asList(widget.data['brands']);
  List<Map<String, dynamic>> _branches = [];
  dynamic _branchId;
  bool _busy = false;
  bool _force = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    loadBranches().then((b) {
      if (!mounted) return;
      setState(() {
        _branches = b;
        final mine = Api.user?['branchId'];
        if (b.any((x) => x['id'] == mine)) _branchId = mine;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _po.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _commit() async {
    final sel = _lines.where((l) => l.on).toList();
    String? bad;
    if (_branchId == null) bad = 'ເລືອກສາຂາ';
    if (bad == null && _po.text.trim().isEmpty) bad = 'ໃສ່ເລກ PO';
    if (bad == null && sel.isEmpty) bad = 'ເລືອກຢ່າງນ້ອຍ 1 ແຖວ';
    if (bad == null) {
      for (final l in sel) {
        if ((num.tryParse(l.qty.text.trim()) ?? 0) <= 0) {
          bad = 'ຈຳນວນບໍ່ຖືກ: ${l.partNo}';
          break;
        }
        if (l.isNew && l.brandId == null) {
          bad = 'ເລືອກ BRAND ສຳລັບ ${l.partNo}';
          break;
        }
      }
    }
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    final branchName = pick(
        _branches.firstWhere((b) => b['id'] == _branchId,
            orElse: () => <String, dynamic>{}),
        ['name']);
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ຢືນຢັນນຳເຂົ້າ'),
        content: Text(
            'ນຳເຂົ້າ ${sel.length} ລາຍການ ເຂົ້າສາຂາ $branchName\nPO: ${_po.text.trim()}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('ນຳເຂົ້າ')),
        ],
      ),
    );
    if (go != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = {
        'branchId': _branchId,
        'poNo': _po.text.trim(),
        'vendorId': widget.data['vendorId'],
        'vendorName': pick(widget.data, ['vendorName']),
        'invoiceNo': pick(widget.data, ['invoiceNo']),
        'note': _note.text.trim(),
        'force': _force,
        'file': widget.data['file'],
        'items': [
          for (final l in sel)
            {
              'partNo': l.partNo,
              'name': l.name.text.trim(),
              'qty': num.parse(l.qty.text.trim()),
              'unitCost': num.tryParse(l.cost.text.trim()) ?? 0,
              'productId': l.src['productId'],
              'brandId': l.brandId,
            }
        ],
      };
      final r = await Api.post('/imports/invoice/commit', body);
      if (!mounted) return;
      final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('ນຳເຂົ້າສຳເລັດ'),
          content: Text('GRN: ${pick(m, ['grnNo'])}\nPO: ${pick(m, ['poNo'])}\n'
              'ລາຍການ: ${pick(m, ['lines'])} · ສິນຄ້າໃໝ່: ${pick(m, [
                'createdProducts'
              ])}\n'
              'ບັນທຶກໂດຍ: ${pick(m, ['by'])}'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(d), child: const Text('ຕົກລົງ'))
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final d = widget.data;
    final warnings = (d['warnings'] is List)
        ? (d['warnings'] as List).map((e) => '$e').toList()
        : <String>[];
    final dup = pick(d, ['alreadyImported']);
    final user =
        pick(Api.user ?? <String, dynamic>{}, ['name', 'fullName', 'phone']);
    final count = _lines.where((l) => l.on).length;
    final totalQty = _lines
        .where((l) => l.on)
        .fold<num>(0, (s, l) => s + (num.tryParse(l.qty.text.trim()) ?? 0));
    return Scaffold(
      appBar: AppBar(title: const Text('ນຳເຂົ້າ Invoice')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          title: pick(
              d['file'] is Map
                  ? Map<String, dynamic>.from(d['file'] as Map)
                  : <String, dynamic>{},
              ['name']),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                'Invoice: ${pick(d, ['invoiceNo'])} · ວັນທີ: ${pick(d, [
                      'date'
                    ])}',
                style: TextStyle(color: p.mut)),
            Text('ຜູ້ສະໜອງ: ${pick(d, ['vendorName'])}',
                style: TextStyle(color: p.mut)),
            Text('ນຳເຂົ້າໂດຍ: $user',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            DropdownButtonFormField<dynamic>(
              key: ValueKey('br-$_branchId'),
              initialValue: _branchId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ສາຂາ'),
              items: [
                for (final b in _branches)
                  DropdownMenuItem<dynamic>(
                      value: b['id'], child: Text(pick(b, ['name']))),
              ],
              onChanged: (v) => setState(() => _branchId = v),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _po,
                decoration: const InputDecoration(labelText: 'ເລກ PO')),
            const SizedBox(height: 12),
            TextField(
                controller: _note,
                decoration:
                    const InputDecoration(labelText: 'ໝາຍເຫດ (ບໍ່ບັງຄັບ)')),
          ]),
        ),
        if (dup.isNotEmpty)
          Card(
            color: Colors.red.withOpacity(0.08),
            child: SwitchListTile(
              title: Text('Invoice ນີ້ເຄີຍນຳເຂົ້າແລ້ວ ($dup)',
                  style: TextStyle(color: p.bad)),
              subtitle: const Text('ເປີດເພື່ອນຳເຂົ້າຊ້ຳ'),
              value: _force,
              onChanged: (v) => setState(() => _force = v),
            ),
          ),
        if (warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('⚠ ${warnings.join('\n⚠ ')}',
                style: const TextStyle(color: Colors.orange)),
          ),
        for (final l in _lines)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Checkbox(
                          value: l.on,
                          onChanged: (v) => setState(() => l.on = v == true)),
                      Expanded(
                          child: Text(l.partNo,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700))),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (l.isNew ? Colors.orange : Colors.green)
                              .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          l.isNew ? 'ສິນຄ້າໃໝ່' : 'ມີແລ້ວ',
                          style: TextStyle(
                              fontSize: 12,
                              color: l.isNew
                                  ? Colors.orange.shade800
                                  : Colors.green.shade700),
                        ),
                      ),
                    ]),
                    if (!l.isNew)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 6),
                        child: Text(pick(l.src, ['productName']),
                            style: TextStyle(color: p.mut, fontSize: 12)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(children: [
                        TextField(
                          controller: l.name,
                          enabled: l.isNew,
                          decoration: const InputDecoration(
                              labelText: 'ຊື່ສິນຄ້າ', isDense: true),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: l.qty,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                  labelText: 'ຈຳນວນ', isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: l.cost,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'ລາຄາ/ໜ່ວຍ', isDense: true),
                            ),
                          ),
                        ]),
                        if (l.isNew) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<dynamic>(
                            key: ValueKey('b-${l.partNo}-${l.brandId}'),
                            initialValue: l.brandId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'BRAND (ສິນຄ້າໃໝ່)', isDense: true),
                            items: [
                              for (final b in _brands)
                                DropdownMenuItem<dynamic>(
                                    value: b['id'],
                                    child: Text(pick(b, ['name']))),
                            ],
                            onChanged: (v) => setState(() => l.brandId = v),
                          ),
                        ],
                      ]),
                    ),
                  ]),
            ),
          ),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: p.bad))),
        Text('ເລືອກ $count ແຖວ · ລວມ ${_n(totalQty)} ຊິ້ນ',
            style: TextStyle(color: p.mut)),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _busy ? null : _commit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ຢືນຢັນ ນຳເຂົ້າ'),
          ),
        ),
      ]),
    );
  }
}

/// latest goods receipts with the user who made them
class InvoiceHistoryPage extends StatefulWidget {
  const InvoiceHistoryPage({super.key});
  @override
  State<InvoiceHistoryPage> createState() => _InvoiceHistoryPageState();
}

class _InvoiceHistoryPageState extends State<InvoiceHistoryPage> {
  late final Future<dynamic> _f = Api.get('/imports/receipts?limit=50');

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ປະຫວັດຮັບເຂົ້າ')),
      body: FutureBuilder<dynamic>(
        future: _f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) return Center(child: Text('${s.error}'));
          final rows = asList(s.data);
          if (rows.isEmpty)
            return Center(
                child: Text('ຍັງບໍ່ມີລາຍການ', style: TextStyle(color: p.mut)));
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (c, i) {
              final m = rows[i];
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                child: ListTile(
                  title: Text(
                      '${pick(m, ['grnNo'])}${pick(m, [
                            'refNo'
                          ]).isEmpty ? '' : ' · PO ${pick(m, ['refNo'])}'}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${pick(m, ['branchName'])} · ${pick(m, [
                            'itemCount'
                          ])} ລາຍການ\n${pick(m, ['note'])}',
                      style: TextStyle(color: p.mut, fontSize: 12)),
                  isThreeLine: true,
                  trailing: Text(pick(m, ['userName']),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
