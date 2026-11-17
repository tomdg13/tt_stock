// Many bins (locations) per product, each with an optional qty.
// Server: GET/PUT /products/:id/bins   body: {bins:[{binId, qty}]}
import 'package:flutter/material.dart';
import 'api.dart';

class BinRow {
  String? binId;
  String qty;
  BinRow({this.binId, this.qty = ''});
}

class ProductBinsController {
  final rows = <BinRow>[];
  bool dirty = false;

  Future<void> apply(String productId) async {
    final seen = <String>{};
    final list = <Map<String, dynamic>>[];
    for (final r in rows) {
      final id = r.binId;
      if (id == null || !seen.add(id)) continue;
      final q = r.qty.trim();
      list.add({
        'binId': int.tryParse(id) ?? id,
        'qty': q.isEmpty ? null : num.tryParse(q),
      });
    }
    await Api.put('/products/${Uri.encodeComponent(productId)}/bins',
        {'bins': list});
    dirty = false;
  }
}

class ProductBinsEditor extends StatefulWidget {
  final String? productId; // null while adding a new product
  final ProductBinsController controller;
  const ProductBinsEditor(
      {super.key, required this.productId, required this.controller});
  @override
  State<ProductBinsEditor> createState() => _ProductBinsEditorState();
}

class _ProductBinsEditorState extends State<ProductBinsEditor> {
  final _opts = <String, String>{}; // bin id -> label
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List _asList(dynamic d) {
    if (d is List) return d;
    if (d is Map && d['data'] is List) return d['data'] as List;
    return const [];
  }

  Future<void> _load() async {
    try {
      for (final b in _asList(await Api.get('/bins'))) {
        if (b is! Map) continue;
        final code = '${b['code'] ?? ''}';
        final name = '${b['name'] ?? ''}';
        _opts['${b['id']}'] = name.isEmpty ? code : '$code · $name';
      }
      final c = widget.controller;
      final pid = widget.productId;
      if (pid != null && pid.isNotEmpty) {
        final d = await Api.get('/products/${Uri.encodeComponent(pid)}/bins');
        c.rows.clear();
        for (final r in _asList(d)) {
          if (r is! Map) continue;
          c.rows.add(BinRow(
              binId: '${r['binId']}',
              qty: r['qty'] == null ? '' : '${r['qty']}'));
        }
      }
      if (c.rows.isEmpty) c.rows.add(BinRow());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(8),
          child: Center(child: CircularProgressIndicator()));
    }
    final used = c.rows.map((r) => r.binId).whereType<String>().toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ບ່ອນເກັບ (ເພີ່ມໄດ້ຫຼາຍບ່ອນ)',
          style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 8),
      for (final r in List<BinRow>.from(c.rows))
        Padding(
          key: ObjectKey(r),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                value: _opts.containsKey(r.binId) ? r.binId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'ບ່ອນເກັບ'),
                items: [
                  for (final e in _opts.entries)
                    if (e.key == r.binId || !used.contains(e.key))
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() {
                  r.binId = v;
                  c.dirty = true;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextFormField(
                initialValue: r.qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ຈຳນວນ'),
                onChanged: (v) {
                  r.qty = v;
                  c.dirty = true;
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() {
                c.rows.remove(r);
                c.dirty = true;
              }),
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('ເພີ່ມບ່ອນເກັບ'),
          onPressed: () => setState(() {
            c.rows.add(BinRow());
            c.dirty = true;
          }),
        ),
      ),
    ]);
  }
}
