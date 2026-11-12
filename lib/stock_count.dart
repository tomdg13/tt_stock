import 'package:flutter/material.dart';
import 'api.dart';
import 'screens.dart' show BarcodeScanPage;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'dart:convert' as cv;
import 'package:archive/archive.dart' as ar;
import 'package:file_picker/file_picker.dart' as fp;
import 'po_excel.dart' show sharePoXlsx, XlImage;
import 'product_images.dart' show productImageUrl;
import 'crud.dart' show openEdit;
import 'specs.dart' show crudSpec;
import 'widgets.dart';

String _s(num n) => n % 1 == 0 ? n.toInt().toString() : n.toString();

List<Map<String, dynamic>> _list(dynamic d) {
  final raw = d is Map ? (d['data'] ?? d['items'] ?? d['rows'] ?? []) : d;
  return asList(raw);
}

dynamic _unwrap(dynamic d) {
  if (d is Map && d['data'] is Map) return d['data'];
  return d;
}

String _day(dynamic v) => '${v ?? ''}'.split('T').first;

Color _statusColor(String s) {
  if (s == 'OPEN') return Colors.orange;
  if (s == 'CANCELLED') return Colors.grey;
  return Colors.green;
}

String _statusLabel(String s) {
  if (s == 'OPEN') return 'ກຳລັງນັບ';
  if (s == 'CANCELLED') return 'ຍົກເລີກ';
  return 'ປິດແລ້ວ';
}

// ---------------------------------------------------------------------------
// 1) list of audits + create new audit
// ---------------------------------------------------------------------------
List<Object>? _xlThumb(Uint8List b) {
  final im = img.decodeImage(b);
  if (im == null) return null;
  final sq = img.copyResizeCropSquare(im, size: 96);
  final jpg = Uint8List.fromList(img.encodeJpg(sq, quality: 78));
  return <Object>[jpg, 48, 48];
}

class StockCountPage extends StatefulWidget {
  const StockCountPage({super.key});
  @override
  State<StockCountPage> createState() => _StockCountPageState();
}

class _StockCountPageState extends State<StockCountPage> {
  List<Map<String, dynamic>> _audits = [];
  bool _busy = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = await Api.get('/stock/audits?limit=100');
      if (mounted) setState(() => _audits = _list(d));
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _create() async {
    final id = await showDialog<String>(
        context: context, builder: (_) => const _NewAuditDialog());
    if (id == null || !mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => AuditPage(auditId: id)));
    _load();
  }

  Future<void> _open(Map<String, dynamic> a) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AuditPage(auditId: '${a['id']}')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ນັບສະຕັອກ'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'ໂຫຼດໃໝ່',
              onPressed: _busy ? null : _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: const Text('ສ້າງການນັບໃໝ່')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_err!, style: TextStyle(color: cs.error)),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load, child: const Text('ລອງໃໝ່')),
                      ])))
              : _audits.isEmpty
                  ? const Center(child: Text('ຍັງບໍ່ມີການນັບ'))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: _audits.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _tile(_audits[i]),
                    ),
    );
  }

  Widget _tile(Map<String, dynamic> a) {
    final status = '${a['status'] ?? ''}';
    final total = num0(a['total']).toInt();
    final counted = num0(a['counted']).toInt();
    final col = _statusColor(status);
    return ListTile(
      onTap: () => _open(a),
      title: Text('${a['countNo'] ?? ''}'),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${a['branchName'] ?? ''}  •  ${_day(a['createdAt'])}'),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: total == 0 ? 0 : counted / total),
        const SizedBox(height: 2),
        Text('ນັບແລ້ວ $counted/$total', style: const TextStyle(fontSize: 12)),
      ]),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: col.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12)),
        child: Text(_statusLabel(status),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: col)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// create-audit dialog: choose branch, note, include zero-stock items
// ---------------------------------------------------------------------------
class _NewAuditDialog extends StatefulWidget {
  const _NewAuditDialog();
  @override
  State<_NewAuditDialog> createState() => _NewAuditDialogState();
}

class _NewAuditDialogState extends State<_NewAuditDialog> {
  List<Map<String, dynamic>> _branches = [];
  String? _branchId;
  final _note = TextEditingController();
  bool _zero = false;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final d = await Api.get('/branches');
      final list = _list(d);
      if (!mounted) return;
      setState(() {
        _branches = list;
        if (list.isNotEmpty) _branchId = pick(list.first, ['id']);
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _go() async {
    if (_branchId == null) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      var res = await Api.post('/stock/audits', {
        'branchId': int.parse(_branchId!),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'includeZero': _zero,
      });
      res = _unwrap(res);
      final id = res is Map ? '${res['id']}' : '';
      if (!mounted) return;
      Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('ສ້າງການນັບໃໝ່'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String?>(
            key: ValueKey(_branchId),
            initialValue: _branchId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'ສາຂາ / ສາງ'),
            items: [
              for (final b in _branches)
                DropdownMenuItem<String?>(
                    value: pick(b, ['id']), child: Text(pick(b, ['name']))),
            ],
            onChanged: _busy ? null : (v) => setState(() => _branchId = v),
          ),
          const SizedBox(height: 8),
          TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'ໝາຍເຫດ')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ລວມລາຍການທີ່ສະຕັອກ 0'),
            value: _zero,
            onChanged: _busy ? null : (v) => setState(() => _zero = v),
          ),
          if (_err != null)
            Text(_err!, style: TextStyle(color: cs.error, fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('ຍົກເລີກ')),
        FilledButton(
            onPressed: (_busy || _branchId == null) ? null : _go,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ສ້າງ')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2) one audit: all items to check, count each item, close
// ---------------------------------------------------------------------------
class AuditPage extends StatefulWidget {
  final String auditId;
  const AuditPage({super.key, required this.auditId});
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  Map<String, dynamic> _h = {};
  List<Map<String, dynamic>> _lines = [];
  Map<String, String> _imgById = {};
  Map<String, Map<String, dynamic>> _info = {};
  String _q = '';
  int _tab = 1;
  int _filter = 0; // 0 all, 1 not counted, 2 counted, 3 differences
  bool _busy = true;
  String? _err;

  bool get _isOpen => '${_h['status']}' == 'OPEN';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = _unwrap(await Api.get('/stock/audits/${widget.auditId}'));
      final h = Map<String, dynamic>.from(d as Map);
      final lines = asList(h['lines']);
      if (!mounted) return;
      setState(() {
        _h = h;
        _lines = lines;
      });
      _loadExtras('${h['branchId']}');
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  // thumbnails + bin / brand / model (best effort, the audit works without them)
  Future<void> _loadExtras(String branchId) async {
    try {
      final d = await Api.get('/products?limit=2000');
      final byId = <String, String>{};
      for (final m in _list(d)) {
        final img = pick(m, ['imageUrl', 'image', 'photo']);
        final id = pick(m, ['id', 'productId']);
        if (img.isNotEmpty && id.isNotEmpty) byId[id] = img;
      }
      if (mounted) setState(() => _imgById = byId);
    } catch (_) {}
    try {
      final d = await Api.get('/stock/balances?branchId=$branchId&limit=2000');
      final info = <String, Map<String, dynamic>>{};
      for (final m in _list(d)) {
        info['${m['productId']}'] = m;
      }
      if (mounted) setState(() => _info = info);
    } catch (_) {}
  }

  String _imgOf(Map<String, dynamic> r) {
    final own = pick(r, ['imageUrl', 'image', 'photo']);
    return own.isNotEmpty ? own : (_imgById['${r['productId']}'] ?? '');
  }

  Widget _thumb(String raw, {double size = 48}) {
    final cs = Theme.of(context).colorScheme;
    final ph = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant),
    );
    final url = productImageUrl(raw);
    if (url.isEmpty) return ph;
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (c) => Dialog(
          child: InteractiveViewer(
            child: Image.network(url, webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Icon(Icons.broken_image_outlined))),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url, webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ph),
      ),
    );
  }

  // save one counted qty at once (null = clear the count)
  Future<void> _setQty(Map<String, dynamic> r, num? v) async {
    final pid = '${r['productId']}';
    try {
      await Api.put(
          '/stock/audits/${widget.auditId}/lines/$pid', {'countedQty': v});
      if (!mounted) return;
      setState(() {
        _lines = [
          for (final x in _lines)
            '${x['productId']}' == pid
                ? {
                    ...x,
                    'countedQty': v,
                    'diff': v == null ? null : v - num0(x['systemQty']),
                  }
                : x
        ];
      });
    } catch (e) {
      _snack('ບັນທຶກບໍ່ສຳເລັດ: $e');
    }
  }

  Future<void> _askQty(Map<String, dynamic> r) async {
    if (!_isOpen) return;
    final cur = r['countedQty'] == null ? null : num0(r['countedQty']);
    final c = TextEditingController(text: cur == null ? '' : _s(cur));
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(pick(r, ['productName'])),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _thumb(_imgOf(r), size: 100)),
              const SizedBox(height: 12),
              Text('ໃນລະບົບ: ${_s(num0(r['systemQty']))} ${pick(r, ['unit'])}'),
              const SizedBox(height: 8),
              TextField(
                controller: c,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'ຈຳນວນທີ່ນັບໄດ້'),
                onSubmitted: (t) => Navigator.pop(d, t),
              ),
            ]),
        actions: [
          if (cur != null)
            TextButton(
                onPressed: () => Navigator.pop(d, '__clear__'),
                child: const Text('ລຶບການນັບ')),
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(d, c.text),
              child: const Text('ຕົກລົງ')),
        ],
      ),
    );
    if (v == null) return;
    if (v == '__clear__') {
      await _setQty(r, null);
      return;
    }
    final n = num.tryParse(v.trim());
    if (n != null && n >= 0) await _setQty(r, n);
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const BarcodeScanPage()));
    if (code == null || code.isEmpty) return;
    try {
      var pr =
          await Api.get('/products/by-barcode/${Uri.encodeComponent(code)}');
      if (pr is Map && pr['data'] is Map) pr = pr['data'];
      final pid = pr is Map
          ? pick(Map<String, dynamic>.from(pr), ['id', 'productId'])
          : '';
      final hit = _lines.where((r) => '${r['productId']}' == pid).toList();
      if (hit.isEmpty) {
        _snack('ບໍ່ພົບອາໄຫຼ່ໃນການນັບນີ້: $code');
        return;
      }
      await _askQty(hit.first);
    } catch (e) {
      _snack('ບໍ່ພົບ Barcode: $code');
    }
  }

  Future<void> _close() async {
    final left = _lines.where((r) => r['countedQty'] == null).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ປິດການນັບ?'),
        content: Text(left > 0
            ? 'ຍັງເຫຼືອ $left ລາຍການທີ່ຍັງບໍ່ໄດ້ນັບ. ປິດແລ້ວຈະແກ້ໄຂບໍ່ໄດ້.'
            : 'ນັບຄົບທຸກລາຍການແລ້ວ. ປິດແລ້ວຈະແກ້ໄຂບໍ່ໄດ້.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('ປິດການນັບ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/stock/audits/${widget.auditId}/close', {'force': true});
      _load();
    } catch (e) {
      _snack('ປິດບໍ່ສຳເລັດ: $e');
    }
  }

  Future<void> _cancelAudit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ຍົກເລີກການນັບນີ້?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('ບໍ່')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('ຍົກເລີກການນັບ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/stock/audits/${widget.auditId}/cancel', {});
      _load();
    } catch (e) {
      _snack('ຍົກເລີກບໍ່ສຳເລັດ: $e');
    }
  }

  Future<void> _editProduct(Map<String, dynamic> r) async {
    final sp = crudSpec('prod');
    if (sp == null) {
      _snack('ບໍ່ພົບໜ້າແກ້ໄຂສິນຄ້າ');
      return;
    }
    final row = <String, dynamic>{
      ...r,
      'id': r['productId'],
      'name': pick(r, ['productName']),
    };
    final changed = await openEdit(context, sp, row);
    if (changed == true) _loadExtras('${_h['branchId']}');
  }

  bool _match(Map<String, dynamic> r) {
    final q = _q.trim().toUpperCase();
    if (q.isNotEmpty) {
      final inf = _info['${r['productId']}'] ?? const <String, dynamic>{};
      final s = [
        pick(r, ['productName']),
        pick(inf, ['binCode']),
        pick(inf, ['brandName']),
        pick(inf, ['modelName']),
      ].join(' ').toUpperCase();
      if (!s.contains(q)) return false;
    }
    final counted = r['countedQty'] != null;
    if (_filter == 1) return !counted;
    if (_filter == 2) return counted;
    if (_filter == 3) {
      return counted && num0(r['countedQty']) != num0(r['systemQty']);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _lines.where(_match).toList();
    int counted = 0;
    int diffItems = 0;
    num diffQty = 0;
    num sysTotal = 0;
    for (final r in _lines) {
      sysTotal += num0(r['systemQty']);
      if (r['countedQty'] == null) continue;
      counted++;
      final d = num0(r['countedQty']) - num0(r['systemQty']);
      diffQty += d;
      if (d != 0) diffItems++;
    }
    final total = _lines.length;
    final status = '${_h['status'] ?? ''}';
    return Scaffold(
      appBar: AppBar(
        title: Text('${_h['countNo'] ?? 'ນັບສະຕັອກ'}'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'ໂຫຼດໃໝ່',
              onPressed: _busy ? null : _load),
          if (_isOpen)
            IconButton(
                icon: const Icon(Icons.task_alt),
                tooltip: 'ປິດການນັບ',
                onPressed: _busy ? null : _close),
          if (_isOpen)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'cancel') _cancelAudit();
                if (v == 'add') _addMissing();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('ດຶງລາຍການທີ່ຂາດ')),
                PopupMenuItem(value: 'cancel', child: Text('ຍົກເລີກການນັບ')),
              ],
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab == 2 ? 2 : 1,
        onDestinationSelected: (i) {
          if (i == 0) {
            if (_isOpen) _scan();
          } else if (i == 3) {
            _exportXlsx();
          } else if (i == 4) {
            _importXlsx();
          } else {
            setState(() => _tab = i);
          }
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.qr_code_scanner), label: 'ສະແກນ'),
          NavigationDestination(icon: Icon(Icons.view_list), label: 'ລາຍການ'),
          NavigationDestination(
              icon: Icon(Icons.table_chart), label: 'ຕາຕະລາງ'),
          NavigationDestination(
              icon: Icon(Icons.table_view_outlined), label: 'Excel'),
          NavigationDestination(
              icon: Icon(Icons.upload_file_outlined), label: 'ອັບໂຫຼດ'),
        ],
      ),
      body: _busy && _lines.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_err!, style: TextStyle(color: cs.error)),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load, child: const Text('ລອງໃໝ່')),
                      ])))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                                child: Text(
                                    '${_h['branchName'] ?? ''}  •  ${_day(_h['createdAt'])}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600))),
                            Text(_statusLabel(status),
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _statusColor(status))),
                          ]),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                              value: total == 0 ? 0 : counted / total),
                          const SizedBox(height: 8),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _sum('ລາຍການທັງໝົດ', '$total'),
                                _sum('ນັບແລ້ວ', '$counted'),
                                _sum('ຍັງເຫຼືອ', '${total - counted}'),
                                _sum('ລາຍການຜິດ', '$diffItems'),
                                _sum('ຜົນຕ່າງ',
                                    '${diffQty > 0 ? '+' : ''}${_s(diffQty)}'),
                              ]),
                          const SizedBox(height: 4),
                          Text('ໃນລະບົບລວມ ${_s(sysTotal)}',
                              style: const TextStyle(fontSize: 11)),
                        ]),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TextField(
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'ຄົ້ນຫາອາໄຫຼ່'),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final f in const [
                          [0, 'ທັງໝົດ'],
                          [1, 'ຍັງບໍ່ນັບ'],
                          [2, 'ນັບແລ້ວ'],
                          [3, 'ຜິດ'],
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('${f[1]}'),
                              selected: _filter == f[0],
                              onSelected: (_) =>
                                  setState(() => _filter = f[0] as int),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(child: Text('ບໍ່ມີຂໍ້ມູນ'))
                        : _tab == 2
                            ? _table(rows)
                            : ListView.separated(
                                padding: const EdgeInsets.only(bottom: 8),
                                itemCount: rows.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) => _row(rows[i]),
                              ),
                  ),
                ]),
    );
  }

  static List<String> _sortKeys = ['bin', 'brand', 'name'];
  static const _sortOpts = <String, String>{
    '': '— ບໍ່ໃຊ້ —',
    'bin': 'ທີ່ເກັບ (location)',
    'brand': 'Brand',
    'model': 'Model',
    'name': 'ລາຍການ',
    'unit': 'ໜ່ວຍ',
    'id': 'productId',
  };

  static bool _xlPhotos = true;
  static bool _xlCodes = true;

  Future<List<String>?> _askSort() {
    final cur = [..._sortKeys, '', '', ''].take(3).toList();
    var photos = _xlPhotos;
    var codes = _xlCodes;
    return showDialog<List<String>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('ຕັ້ງຄ່າກ່ອນ Export'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DropdownButtonFormField<String>(
                    initialValue: cur[i],
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: i == 0 ? 'ລຽງຕາມ' : 'ແລ້ວຕາມ'),
                    items: [
                      for (final e in _sortOpts.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setS(() => cur[i] = v ?? ''),
                  ),
                ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ໃສ່ຮູບ (ຊ້າກວ່າ)'),
                value: photos,
                onChanged: (v) => setS(() => photos = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ໃສ່ barcode'),
                value: codes,
                onChanged: (v) => setS(() => codes = v),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('ຍົກເລີກ')),
            FilledButton(
                onPressed: () {
                  final keys = <String>[];
                  for (final k in cur) {
                    if (k.isNotEmpty && !keys.contains(k)) keys.add(k);
                  }
                  _sortKeys = keys;
                  _xlPhotos = photos;
                  _xlCodes = codes;
                  Navigator.pop(c, keys);
                },
                child: const Text('Export')),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _sorted(List<String> keys) {
    String val(Map<String, dynamic> r, String k) {
      final inf = _info['${r['productId']}'] ?? const <String, dynamic>{};
      switch (k) {
        case 'bin':
          return pick(inf, ['binCode']);
        case 'brand':
          return pick(inf, ['brandName']);
        case 'model':
          return pick(inf, ['modelName']);
        case 'name':
          return pick(r, ['productName']);
        case 'unit':
          return pick(r, ['unit']);
        default:
          return '${r['productId']}';
      }
    }

    int nat(String a, String b) {
      final re = RegExp(r'\d+|\D+');
      final x = re.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
      final y = re.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
      for (var i = 0; i < x.length && i < y.length; i++) {
        final pn = int.tryParse(x[i]);
        final qn = int.tryParse(y[i]);
        final c = (pn != null && qn != null)
            ? pn.compareTo(qn)
            : x[i].compareTo(y[i]);
        if (c != 0) return c;
      }
      return x.length.compareTo(y.length);
    }

    final ents = _lines.asMap().entries.toList();
    ents.sort((a, b) {
      for (final k in keys) {
        final x = val(a.value, k);
        final y = val(b.value, k);
        if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
        final c = nat(x, y);
        if (c != 0) return c;
      }
      return a.key.compareTo(b.key);
    });
    return [for (final e in ents) e.value];
  }

  Future<void> _addMissing() async {
    if (!_isOpen) return;
    setState(() => _busy = true);
    try {
      final r =
          await Api.post('/stock/audits/${widget.auditId}/add-missing', {});
      final n = r is Map ? num0(r['added']).toInt() : 0;
      await _load();
      _snack(n == 0 ? 'ບໍ່ມີລາຍການໃໝ່' : 'ເພີ່ມ $n ລາຍການ');
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack('ບໍ່ສຳເລັດ: $e');
    }
  }

  Future<void> _exportXlsx() async {
    final keys = await _askSort();
    if (keys == null || !mounted) return;
    final lines = _sorted(keys);
    var busyOpen = false;
    void closeBusy() {
      if (busyOpen && mounted) {
        busyOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    try {
      if (_xlPhotos || _xlCodes) {
        busyOpen = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
            content: Row(children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('ກຳລັງສ້າງໄຟລ໌…')),
            ]),
          ),
        );
      }

      final bc = <String, String>{};
      if (_xlCodes) {
        final ids = [for (final r in lines) '${r['productId']}'];
        for (var i = 0; i < ids.length; i += 8) {
          await Future.wait(ids.skip(i).take(8).map((id) async {
            try {
              final d = await Api.get(
                  '/products/${Uri.encodeComponent(id)}/barcodes');
              if (d is List) bc[id] = d.map((e) => '$e').join(', ');
            } catch (_) {}
          }));
        }
      }

      final thumbs = <String, List<Object>>{};
      if (_xlPhotos) {
        final urls = <String>{
          for (final r in lines)
            if (productImageUrl(_imgOf(r)).isNotEmpty)
              productImageUrl(_imgOf(r)),
        };
        final list = urls.toList();
        for (var i = 0; i < list.length; i += 8) {
          await Future.wait(list.skip(i).take(8).map((u) async {
            try {
              final res = await http
                  .get(Uri.parse(u))
                  .timeout(const Duration(seconds: 15));
              if (res.statusCode == 200) {
                final t = await compute(_xlThumb, res.bodyBytes);
                if (t != null) thumbs[u] = t;
              }
            } catch (_) {}
          }));
        }
      }

      String hf(String s) => s.replaceAll('&', '&&');
      final created = '${_h['createdAt'] ?? ''}';
      final date = created.length >= 10 ? created.substring(0, 10) : '';
      final cn = hf('${_h['countNo'] ?? ''}');
      final br = hf('${_h['branchName'] ?? ''}');
      final rows = <List<Object>>[
        [
          'productId',
          'ທີ່ເກັບ',
          'brand',
          'model',
          'image',
          'ລາຍການ',
          'barcode',
          'ໜ່ວຍ',
          'ໃນລະບົບ',
          'ນັບໄດ້',
        ],
      ];
      final images = <XlImage>[];
      final heights = <int, double>{};
      for (final r in lines) {
        final id = '${r['productId']}';
        final inf = _info[id] ?? const <String, dynamic>{};
        final sys = num0(r['systemQty']);
        final c = r['countedQty'] == null ? null : num0(r['countedQty']);
        final u = productImageUrl(_imgOf(r));
        final t = thumbs[u];
        if (t != null) {
          images.add(XlImage(
              row: rows.length,
              col: 4,
              key: u,
              bytes: t[0] as Uint8List,
              w: t[1] as int,
              h: t[2] as int));
          heights[rows.length] = 40.0;
        }
        rows.add([
          int.tryParse(id) ?? 0,
          pick(inf, ['binCode']),
          pick(inf, ['brandName']),
          pick(inf, ['modelName']),
          '',
          pick(r, ['productName']),
          bc[id] ?? '',
          pick(r, ['unit']),
          sys % 1 == 0 ? sys.toInt() : sys,
          c == null ? '' : (c % 1 == 0 ? c.toInt() : c),
        ]);
      }
      closeBusy();
      await sharePoXlsx(
        fileName: '${_h['countNo'] ?? 'count'}.xlsx',
        rows: rows,
        boldRows: {0},
        widths: [10, 9, 11.3, 14, 10, 70, 18, 8, 12, 12],
        images: images,
        rowHeights: heights,
        pageHeader: '&L Lao Development Bank&C&Bນັບສະຕັອກ $cn&B&R$br • $date',
        pageFooter:
            '&Lຜູ້ນັບ: ______________   ຜູ້ກວດ: ______________&Cໜ້າ &P / &N&R&D',
      );
    } catch (e) {
      closeBusy();
      _snack('Export ບໍ່ສຳເລັດ: $e');
    }
  }

  String _un(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  Map<int, String> _readCounts(List<int> bytes) {
    final z = ar.ZipDecoder().decodeBytes(bytes);
    String? txt(bool Function(String) test) {
      for (final f in z.files) {
        if (test(f.name)) return cv.utf8.decode(f.content as List<int>);
      }
      return null;
    }

    final tRe = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);
    final ss = <String>[];
    final sx = txt((n) => n == 'xl/sharedStrings.xml');
    if (sx != null) {
      for (final m in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(sx)) {
        ss.add(_un(tRe.allMatches(m.group(1)!).map((e) => e.group(1)!).join()));
      }
    }
    final sheet = txt((n) => n == 'xl/worksheets/sheet1.xml') ??
        txt((n) => n.startsWith('xl/worksheets/sheet') && n.endsWith('.xml'));
    if (sheet == null) throw 'ບໍ່ພົບ sheet ໃນໄຟລ໌';

    final grid = <Map<String, String>>[];
    for (final rm in RegExp(r'<row\b[^>]*?(?:/>|>(.*?)</row>)', dotAll: true)
        .allMatches(sheet)) {
      final cells = <String, String>{};
      for (final cm in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true)
          .allMatches(rm.group(1) ?? '')) {
        final at = cm.group(1)!;
        final body = cm.group(2) ?? '';
        final ref = RegExp(r'r="([A-Z]+)\d+"').firstMatch(at)?.group(1);
        if (ref == null) continue;
        final t = RegExp(r'\bt="(\w+)"').firstMatch(at)?.group(1);
        final vRaw =
            RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1);
        String v;
        if (t == 's') {
          final i = int.tryParse(vRaw ?? '');
          v = (i != null && i < ss.length) ? ss[i] : '';
        } else if (t == 'inlineStr') {
          v = _un(tRe.allMatches(body).map((e) => e.group(1)!).join());
        } else {
          v = _un(vRaw ?? '');
        }
        cells[ref] = v.trim();
      }
      grid.add(cells);
    }

    String? idCol;
    String? qtyCol;
    var start = 0;
    for (var i = 0; i < grid.length; i++) {
      String? a;
      String? b;
      for (final e in grid[i].entries) {
        if (e.value == 'productId') a = e.key;
        if (e.value == 'ນັບໄດ້') b = e.key;
      }
      if (a != null && b != null) {
        idCol = a;
        qtyCol = b;
        start = i + 1;
        break;
      }
    }
    if (idCol == null || qtyCol == null) {
      throw 'ບໍ່ພົບຫົວຕາຕະລາງ productId / ນັບໄດ້';
    }
    final out = <int, String>{};
    for (var i = start; i < grid.length; i++) {
      final raw = grid[i][idCol] ?? '';
      final pid = int.tryParse(raw) ?? double.tryParse(raw)?.toInt();
      if (pid != null) out[pid] = grid[i][qtyCol] ?? '';
    }
    return out;
  }

  Future<void> _importXlsx() async {
    if (!_isOpen) {
      _snack('ການນັບປິດແລ້ວ ນຳເຂົ້າບໍ່ໄດ້');
      return;
    }
    try {
      final r = await fp.FilePicker.pickFiles(
          type: fp.FileType.custom, allowedExtensions: ['xlsx']);
      if (r.isEmpty) return;
      final pf = r.first;
      final bytes = await pf.readAsBytes();
      if (bytes == null) throw 'ອ່ານໄຟລ໌ບໍ່ໄດ້';
      final ups = _readCounts(bytes);
      final byId = <int, Map<String, dynamic>>{
        for (final x in _lines) (int.tryParse('${x['productId']}') ?? -1): x
      };
      final todo = <MapEntry<Map<String, dynamic>, num>>[];
      var bad = 0, unknown = 0, same = 0;
      for (final e in ups.entries) {
        if (e.value.isEmpty) continue;
        final row = byId[e.key];
        if (row == null) {
          unknown++;
          continue;
        }
        final n = num.tryParse(e.value.replaceAll(',', ''));
        if (n == null || n < 0) {
          bad++;
          continue;
        }
        if (row['countedQty'] != null && num0(row['countedQty']) == n) {
          same++;
          continue;
        }
        todo.add(MapEntry(row, n));
      }
      if (!mounted) return;
      if (todo.isEmpty) {
        _snack('ບໍ່ມີລາຍການໃໝ່ (ບໍ່ປ່ຽນ $same • ຜິດ $bad • ບໍ່ພົບ $unknown)');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('ອັບໂຫຼດຈຳນວນນັບ'),
          content: Text(
              'ຈະບັນທຶກ ${todo.length} ລາຍການ\nບໍ່ປ່ຽນ $same • ຜິດ $bad • ບໍ່ພົບ $unknown'),
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
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      for (final e in todo) {
        await _setQty(e.key, e.value);
      }
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('ບັນທຶກແລ້ວ ${todo.length} ລາຍການ');
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack('ອັບໂຫຼດບໍ່ສຳເລັດ: $e');
    }
  }

  Widget _table(List<Map<String, dynamic>> rows) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          headingRowHeight: 40,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 60,
          columns: const [
            DataColumn(label: Text('ລາຍການ')),
            DataColumn(label: Text('ທີ່ເກັບ')),
            DataColumn(label: Text('ໃນລະບົບ'), numeric: true),
            DataColumn(label: Text('ນັບໄດ້'), numeric: true),
            DataColumn(label: Text('ຕ່າງ'), numeric: true),
          ],
          rows: rows.map((r) {
            final sys = num0(r['systemQty']);
            final c = r['countedQty'] == null ? null : num0(r['countedQty']);
            final diff = c == null ? null : c - sys;
            final inf = _info['${r['productId']}'] ?? const <String, dynamic>{};
            return DataRow(
              onSelectChanged: _isOpen ? (_) => _askQty(r) : null,
              cells: [
                DataCell(SizedBox(
                    width: 200,
                    child: Text(pick(r, ['productName']),
                        maxLines: 2, overflow: TextOverflow.ellipsis))),
                DataCell(Text(pick(inf, ['binCode']))),
                DataCell(Text(_s(sys))),
                DataCell(Text(c == null ? '-' : _s(c))),
                DataCell(Text(
                    diff == null ? '-' : '${diff > 0 ? '+' : ''}${_s(diff)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: diff == null || diff == 0 ? null : Colors.red))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _sum(String label, String value) => Column(children: [
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);

  Widget _row(Map<String, dynamic> r) {
    final sys = num0(r['systemQty']);
    final unit = pick(r, ['unit']);
    final c = r['countedQty'] == null ? null : num0(r['countedQty']);
    final diff = c == null ? null : c - sys;
    final inf = _info['${r['productId']}'] ?? const <String, dynamic>{};
    final sub = [
      pick(inf, ['binCode']),
      pick(inf, ['brandName']),
      pick(inf, ['modelName']),
    ].where((e) => e.isNotEmpty).join(' • ');
    final sp = crudSpec('prod');
    final canEdit = sp != null && sp.canEdit;
    return Column(children: [
      ListTile(
        onTap: _isOpen ? () => _askQty(r) : null,
        leading: _thumb(_imgOf(r)),
        title: Text(pick(r, ['productName'])),
        subtitle: sub.isEmpty ? null : Text(sub),
        trailing: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('ໃນລະບົບ ${_s(sys)} $unit',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              Text(c == null ? 'ຍັງບໍ່ນັບ' : 'ນັບໄດ້ ${_s(c)} $unit',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c == null
                          ? Colors.grey
                          : diff == 0
                              ? Colors.green
                              : Colors.red)),
              if (diff != null && diff != 0)
                Text('ຕ່າງ ${diff > 0 ? '+' : ''}${_s(diff)}',
                    style: const TextStyle(fontSize: 12, color: Colors.red)),
            ]),
        ),
      ),
      if (_isOpen)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            FilledButton.tonalIcon(
              onPressed: () => _askQty(r),
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('ໃສ່ຈຳນວນ'),
              style:
                  FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            if (canEdit) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _editProduct(r),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('ແກ້ໄຂສິນຄ້າ'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ],
          ]),
        ),
    ]);
  }
}
