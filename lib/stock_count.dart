import 'package:flutter/material.dart';
import 'api.dart';
import 'screens.dart' show BarcodeScanPage;
import 'product_images.dart' show productImageUrl;
import 'crud.dart' show openEdit;
import 'specs.dart' show crudSpec;
import 'widgets.dart';

class StockCountPage extends StatefulWidget {
  const StockCountPage({super.key});
  @override
  State<StockCountPage> createState() => _StockCountPageState();
}

class _StockCountPageState extends State<StockCountPage> {
  List<Map<String, dynamic>> _branches = [];
  String? _branchId;
  List<Map<String, dynamic>> _rows = [];
  final Map<String, num> _counted = {};
  Map<String, String> _imgById = {};
  String _q = '';
  int _filter = 0; // 0 = all, 1 = not counted, 2 = differences
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _loadImgs();
    _loadBranches();
  }

  List<Map<String, dynamic>> _list(dynamic d) {
    final raw = d is Map ? (d['data'] ?? d['items'] ?? d['rows'] ?? []) : d;
    return asList(raw);
  }

  String _s(num n) => n % 1 == 0 ? n.toInt().toString() : n.toString();

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // same source as the product menu: /products -> imageUrl
  Future<void> _loadImgs() async {
    try {
      final d = await Api.get('/products?limit=2000');
      final byId = <String, String>{};
      for (final m in _list(d)) {
        final img = pick(m, ['imageUrl', 'image', 'photo']);
        if (img.isEmpty) continue;
        final id = pick(m, ['id', 'productId']);
        if (id.isNotEmpty) byId[id] = img;
      }
      if (mounted) setState(() => _imgById = byId);
    } catch (_) {}
  }

  String _imgOf(Map<String, dynamic> r) {
    final own = pick(r, ['imageUrl', 'image', 'photo']);
    return own.isNotEmpty ? own : (_imgById['${r['productId']}'] ?? '');
  }

  Widget _thumb(String raw) {
    final cs = Theme.of(context).colorScheme;
    final ph = Container(
      width: 48,
      height: 48,
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
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ph),
      ),
    );
  }

  Future<void> _loadBranches() async {
    try {
      final d = await Api.get('/branches');
      final list = _list(d);
      if (!mounted) return;
      setState(() => _branches = list);
      // open with the first branch already selected so the stock list shows at once
      if (_branchId == null && list.isNotEmpty) {
        setState(() => _branchId = pick(list.first, ['id']));
        _loadParts();
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _loadParts({bool keepCounts = false}) async {
    if (_branchId == null) return;
    setState(() {
      _busy = true;
      _err = null;
      if (!keepCounts) _counted.clear();
    });
    try {
      final d = await Api.get('/stock/balances?branchId=$_branchId&limit=2000');
      if (mounted) setState(() => _rows = _list(d));
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  // same edit screen as Product menu -> pencil
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
    if (changed == true) {
      _loadImgs();
      _loadParts(keepCounts: true);
    }
  }

  Future<void> _askQty(Map<String, dynamic> r) async {
    final id = '${r['productId']}';
    final c = TextEditingController(
        text: _counted[id] == null ? '' : _s(_counted[id]!));
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(pick(r, ['productName'])),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ໃນລະບົບ: ${_s(num0(r['qtyOnHand']))} ${pick(r, ['unit'])}'),
              const SizedBox(height: 8),
              TextField(
                controller: c,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'ຈຳນວນທີ່ນັບໄດ້'),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(d, c.text),
              child: const Text('ຕົກລົງ')),
        ],
      ),
    );
    final n = num.tryParse((v ?? '').trim());
    if (n != null && n >= 0) setState(() => _counted[id] = n);
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
      final hit = _rows.where((r) => '${r['productId']}' == pid).toList();
      if (hit.isEmpty) {
        _snack('ບໍ່ພົບອາໄຫຼ່ໃນສາຂານີ້: $code');
        return;
      }
      await _askQty(hit.first);
    } catch (e) {
      _snack('ບໍ່ພົບ Barcode: $code');
    }
  }

  Future<void> _save() async {
    if (_counted.isEmpty || _branchId == null) return;
    setState(() => _busy = true);
    try {
      final res = await Api.post('/stock/counts', {
        'branchId': int.parse(_branchId!),
        'items': [
          for (final e in _counted.entries)
            {'productId': int.parse(e.key), 'countedQty': e.value}
        ],
      });
      if (!mounted) return;
      final no = res is Map ? '${res['countNo'] ?? ''}' : '';
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('ບັນທຶກແລ້ວ'),
          content: Text('ເລກທີ່ນັບ: $no\nຈຳນວນລາຍການ: ${_counted.length}'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(d), child: const Text('ຕົກລົງ'))
          ],
        ),
      );
    } catch (e) {
      _snack('ບັນທຶກບໍ່ສຳເລັດ: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  bool _match(Map<String, dynamic> r) {
    final q = _q.trim().toUpperCase();
    if (q.isNotEmpty) {
      final s = [
        pick(r, ['productName']),
        pick(r, ['binCode']),
        pick(r, ['brandName']),
        pick(r, ['modelName']),
      ].join(' ').toUpperCase();
      if (!s.contains(q)) return false;
    }
    final c = _counted['${r['productId']}'];
    if (_filter == 1) return c == null;
    if (_filter == 2) return c != null && c != num0(r['qtyOnHand']);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _rows.where(_match).toList();
    num diffTotal = 0;
    int diffParts = 0;
    num sysTotal = 0;
    for (final r in _rows) {
      sysTotal += num0(r['qtyOnHand']);
      final c = _counted['${r['productId']}'];
      if (c == null) continue;
      final d = c - num0(r['qtyOnHand']);
      diffTotal += d;
      if (d != 0) diffParts++;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('ນັບສະຕັອກ'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'ໂຫຼດໃໝ່',
              onPressed: (_busy || _branchId == null)
                  ? null
                  : () {
                      _loadImgs();
                      _loadParts();
                    }),
          IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'ບັນທຶກ',
              onPressed: (_busy || _counted.isEmpty) ? null : _save),
        ],
      ),
      floatingActionButton: _branchId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('ສະແກນ')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: DropdownButtonFormField<String?>(
            key: ValueKey(_branchId),
            initialValue: _branchId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'ສາຂາ / ສາງ'),
            items: [
              for (final b in _branches)
                DropdownMenuItem<String?>(
                    value: pick(b, ['id']), child: Text(pick(b, ['name']))),
            ],
            onChanged: (v) {
              setState(() => _branchId = v);
              _loadParts();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), labelText: 'ຄົ້ນຫາອາໄຫຼ່'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        if (_rows.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _sum('ລາຍການ', '${_rows.length}'),
                      _sum('ໃນສະຕັອກລວມ', _s(sysTotal)),
                      _sum('ນັບແລ້ວ', '${_counted.length}/${_rows.length}'),
                      _sum('ລາຍການຜິດ', '$diffParts'),
                      _sum('ຜົນຕ່າງ',
                          '${diffTotal > 0 ? '+' : ''}${_s(diffTotal)}'),
                    ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              for (final f in const [
                [0, 'ທັງໝົດ'],
                [1, 'ຍັງບໍ່ນັບ'],
                [2, 'ຜິດ'],
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${f[1]}'),
                    selected: _filter == f[0],
                    onSelected: (_) => setState(() => _filter = f[0] as int),
                  ),
                ),
            ]),
          ),
        ],
        if (_err != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_err!, style: TextStyle(color: cs.error))),
        Expanded(
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? Center(
                      child: Text(_branchId == null
                          ? 'ເລືອກສາຂາກ່ອນ'
                          : 'ບໍ່ມີຂໍ້ມູນ'))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
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
    final id = '${r['productId']}';
    final sys = num0(r['qtyOnHand']);
    final unit = pick(r, ['unit']);
    final c = _counted[id];
    final diff = c == null ? null : c - sys;
    final sub = [
      pick(r, ['binCode']),
      pick(r, ['brandName']),
      pick(r, ['modelName']),
    ].where((e) => e.isNotEmpty).join(' • ');
    final sp = crudSpec('prod');
    final canEdit = sp != null && sp.canEdit;
    return Column(children: [
      ListTile(
        onTap: () => _askQty(r),
        leading: _thumb(_imgOf(r)),
        title: Text(pick(r, ['productName'])),
        subtitle: sub.isEmpty ? null : Text(sub),
        trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('ໃນສະຕັອກ ${_s(sys)} $unit',
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
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          FilledButton.tonalIcon(
            onPressed: () => _askQty(r),
            icon: const Icon(Icons.edit_note, size: 18),
            label: const Text('ໃສ່ຈຳນວນ'),
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact),
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
