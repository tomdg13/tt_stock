import 'package:flutter/material.dart';
import 'api.dart';
import 'screens.dart' show BarcodeScanPage;
import 'lao.dart';
import 'theme.dart';
import 'widgets.dart';
import 'screens.dart' show BarcodeScanPage;

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
  String _q = '';
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  List<Map<String, dynamic>> _list(dynamic d) {
    final raw = d is Map ? (d['data'] ?? d['items'] ?? d['rows'] ?? []) : d;
    return asList(raw);
  }

  String _s(num n) => n % 1 == 0 ? n.toInt().toString() : n.toString();

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _loadBranches() async {
    try {
      final d = await Api.get('/branches');
      if (mounted) setState(() => _branches = _list(d));
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _loadParts() async {
    if (_branchId == null) return;
    setState(() {
      _busy = true;
      _err = null;
      _counted.clear();
    });
    try {
      final d = await Api.get('/stock/balances?branchId=$_branchId&limit=2000');
      if (mounted) setState(() => _rows = _list(d));
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _busy = false);
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _q.trim().toUpperCase();
    final rows = _rows.where((r) {
      if (q.isEmpty) return true;
      final s = [
        pick(r, ['productName']),
        pick(r, ['binCode']),
        pick(r, ['brandName']),
        pick(r, ['modelName']),
      ].join(' ').toUpperCase();
      return s.contains(q);
    }).toList();
    num diffTotal = 0;
    int diffParts = 0;
    for (final r in _rows) {
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
        if (_rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _sum('ນັບແລ້ວ', '${_counted.length}/${_rows.length}'),
                      _sum('ລາຍການຜິດ', '$diffParts'),
                      _sum('ຜົນຕ່າງລວມ',
                          '${diffTotal > 0 ? '+' : ''}${_s(diffTotal)}'),
                    ]),
              ),
            ),
          ),
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
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);

  Widget _row(Map<String, dynamic> r) {
    final id = '${r['productId']}';
    final sys = num0(r['qtyOnHand']);
    final c = _counted[id];
    final diff = c == null ? null : c - sys;
    final sub = [
      pick(r, ['binCode']),
      pick(r, ['brandName']),
      pick(r, ['modelName']),
    ].where((e) => e.isNotEmpty).join(' • ');
    return ListTile(
      onTap: () => _askQty(r),
      title: Text(pick(r, ['productName'])),
      subtitle: sub.isEmpty ? null : Text(sub),
      trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('ລະບົບ ${_s(sys)} ${pick(r, ['unit'])}',
                style: const TextStyle(fontSize: 12)),
            Text(c == null ? 'ຍັງບໍ່ນັບ' : 'ນັບໄດ້ ${_s(c)}',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c == null
                        ? Colors.grey
                        : diff == 0
                            ? Colors.green
                            : Colors.red)),
            if (diff != null && diff != 0)
              Text('${diff > 0 ? '+' : ''}${_s(diff)}',
                  style: const TextStyle(fontSize: 12, color: Colors.red)),
          ]),
    );
  }
}
