import 'package:flutter/material.dart';
import 'api.dart';
import 'screens.dart' show BarcodeScanPage;
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
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AuditPage(auditId: id)));
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
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
      subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${a['branchName'] ?? ''}  •  ${_day(a['createdAt'])}'),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: total == 0 ? 0 : counted / total),
            const SizedBox(height: 2),
            Text('ນັບແລ້ວ $counted/$total',
                style: const TextStyle(fontSize: 12)),
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
            child: Image.network(url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Icon(Icons.broken_image_outlined))),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url,
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
              Text(
                  'ໃນລະບົບ: ${_s(num0(r['systemQty']))} ${pick(r, ['unit'])}'),
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
    final code = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const BarcodeScanPage()));
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
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'cancel', child: Text('ຍົກເລີກການນັບ')),
              ],
            ),
        ],
      ),
      floatingActionButton: _isOpen
          ? FloatingActionButton.extended(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('ສະແກນ'))
          : null,
      body: _busy && _lines.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) => _row(rows[i]),
                          ),
                  ),
                ]),
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
        trailing: Column(
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
