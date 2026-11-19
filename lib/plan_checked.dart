import 'package:flutter/material.dart';
import 'api.dart';
import 'image_search.dart' show SearchTools;
import 'plan_bar.dart';
import 'plan_pick.dart';
import 'plan_pdf.dart';
import 'product_images.dart' show productImageUrl;
import 'widgets.dart';

class PlanCheckedPage extends StatefulWidget {
  final Map<String, dynamic> plan;
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onSave;
  final Future<void> Function() onExport;
  const PlanCheckedPage(
      {super.key,
      required this.plan,
      required this.items,
      required this.onSave,
      required this.onExport});
  @override
  State<PlanCheckedPage> createState() => _PlanCheckedPageState();
}

class _PlanCheckedPageState extends State<PlanCheckedPage> {
  final _sc = TextEditingController();
  String _s = '';
  bool _full = false;

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _onS(String v) => setState(() => _s = v.trim().toLowerCase());

  Widget _thumb(String raw) {
    final url = productImageUrl(raw);
    final holder = Container(
        width: 40,
        height: 40,
        color: Colors.black12,
        child: const Icon(Icons.inventory_2_outlined, size: 20));
    if (url.isEmpty) return holder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
          width: 40,
          height: 40,
          child: Image.network(url,
              fit: BoxFit.cover,
              headers: Api.token == null
                  ? null
                  : {'Authorization': 'Bearer ${Api.token}'},
              errorBuilder: (_, __, ___) => holder)),
    );
  }

  String _q(num v) => v % 1 == 0 ? '${v.toInt()}' : '$v';

  String _cell(Map<String, dynamic> x, String k) {
    final v = x[k];
    if (v == null) return '-';
    return _q(num0(v));
  }

  Future<void> _addMore() async {
    final pool = widget.items.where((x) => x['done'] == true ? false : true).toList();
    if (pool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ຕິກຄົບທຸກລາຍການແລ້ວ')));
      return;
    }
    final r = await Navigator.of(context).push<List<Map<String, dynamic>>>(
        MaterialPageRoute(
            builder: (_) =>
                PlanPickPage(items: pool, onExport: widget.onExport)));
    if (r == null || r.isEmpty) return;
    setState(() {
      for (final x in r) {
        x['done'] = true;
      }
    });
    await widget.onSave();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ເພີ່ມແລ້ວ ${r.length} ລາຍການ')));
    }
  }

  Future<void> _edit(Map<String, dynamic> x) async {
    final c = TextEditingController(
        text: x['buyQty'] == null ? '' : _q(num0(x['buyQty'])));
    final must = x['must'] ?? x['qty'];
    final r = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${x['name'] ?? ''}', maxLines: 2),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ຕ້ອງຊື້ ${_cell({'v': must}, 'v')}   ສະຕັອກ ${_cell(x, 'stock')}'),
              Text('ໃຊ້ ${_cell(x, 'used')}   ຊື້ຕົວຈິງ (PO) ${_poCell(x)}'),
              const SizedBox(height: 8),
              TextField(
                  controller: c,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'ຊື້ແຜນນີ້ (${x['unit'] ?? ''})')),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(d, c.text),
              child: const Text('ຕົກລົງ')),
        ],
      ),
    );
    if (r == null) return;
    final t = r.trim();
    final v = num.tryParse(t);
    if (t.isNotEmpty && v == null) return;
    setState(() {
      if (t.isEmpty) {
        x.remove('buyQty');
      } else {
        x['buyQty'] = v;
      }
    });
    await widget.onSave();
  }

  String _poCell(Map<String, dynamic> x) {
    final v = x['po'];
    if (v == null) return '-';
    final n = num0(v);
    return n == 0 ? '-' : _q(n);
  }

  List<DataColumn> _columns() {
    return [
      const DataColumn(label: Text('#')),
      const DataColumn(label: Text('ຮູບ')),
      const DataColumn(label: Text('ສິນຄ້າ')),
      if (_full) const DataColumn(label: Text('ສະຕັອກ'), numeric: true),
      if (_full) const DataColumn(label: Text('ນັບຕົວຈິງ'), numeric: true),
      if (_full) const DataColumn(label: Text('ໃຊ້'), numeric: true),
      const DataColumn(label: Text('ຕ້ອງຊື້'), numeric: true),
      const DataColumn(label: Text('ໜ່ວຍ')),
      if (_full)
        const DataColumn(label: Text('ຊື້ຕົວຈິງ (PO)'), numeric: true),
      const DataColumn(label: Text('ຊື້ແຜນນີ້'), numeric: true),
      if (_full) const DataColumn(label: Text('brand')),
      if (_full) const DataColumn(label: Text('ທີ່ເກັບ')),
    ];
  }

  DataRow _row(int i, Map<String, dynamic> r, ColorScheme cs) {
    return DataRow(onSelectChanged: (_) => _edit(r), cells: [
      DataCell(Text('${i + 1}')),
      DataCell(_thumb('${r['imageUrl'] ?? ''}')),
      DataCell(ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _full ? 200 : 170),
          child: Text('${r['name'] ?? ''}',
              maxLines: 2, overflow: TextOverflow.ellipsis))),
      if (_full) DataCell(Text(_cell(r, 'stock'))),
      if (_full) DataCell(Text(_cell(r, 'counted'))),
      if (_full) DataCell(Text(_cell(r, 'used'))),
      DataCell(Text(r['must'] == null ? _cell(r, 'qty') : _cell(r, 'must'),
          style: const TextStyle(fontWeight: FontWeight.w700))),
      DataCell(Text('${r['unit'] ?? ''}')),
      if (_full) DataCell(Text(_poCell(r))),
      DataCell(Text(_cell(r, 'buyQty'),
          style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary))),
      if (_full) DataCell(Text('${r['brand'] ?? ''}')),
      if (_full) DataCell(Text('${r['bin'] ?? ''}')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = widget.items.where((x) => x['done'] == true).toList();
    rows.sort((a, b) {
      final c = '${a['brand'] ?? ''}'.compareTo('${b['brand'] ?? ''}');
      if (c == 0) return '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
      return c;
    });
    final shown = rows.where((x) {
      if (_s.isEmpty) return true;
      return ['name', 'brand', 'bin']
          .any((k) => '${x[k] ?? ''}'.toLowerCase().contains(_s));
    }).toList();
    var total = 0.0;
    var filled = 0;
    for (final r in rows) {
      if (r['buyQty'] == null) continue;
      total += num0(r['buyQty']).toDouble();
      filled++;
    }
    final shownTxt =
        _s.isEmpty ? '' : ' • ສະແດງ ${shown.length}/${rows.length}';
    return Scaffold(
      appBar: AppBar(title: Text('ລາຍການທີ່ຕິກ (${rows.length})')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _sc,
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: 'ຄົ້ນຫາອາໄຫຼ່',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  SearchTools(onResult: (v) {
                    _sc.text = v;
                    _onS(v);
                  }),
                  IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _sc.clear();
                        _onS('');
                      }),
                ])),
            onChanged: _onS,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            ChoiceChip(
                label: const Text('ຫຍໍ້'),
                selected: _full == false,
                onSelected: (_) => setState(() => _full = false)),
            const SizedBox(width: 8),
            ChoiceChip(
                label: const Text('ເຕັມ'),
                selected: _full,
                onSelected: (_) => setState(() => _full = true)),
          ]),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(rows.isEmpty
                      ? 'ຍັງບໍ່ມີລາຍການທີ່ຕິກ'
                      : 'ບໍ່ພົບລາຍການ'))
              : SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      showCheckboxColumn: false,
                      columnSpacing: 14,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 64,
                      headingRowColor:
                          WidgetStatePropertyAll(cs.surfaceContainerHighest),
                      columns: _columns(),
                      rows: [
                        for (var i = 0; i < shown.length; i++)
                          _row(i, shown[i], cs),
                      ],
                    ),
                  ),
                ),
        ),
      ]),
      bottomNavigationBar: PlanBar(
        summary:
            'ລວມ ${rows.length} ລາຍການ • ໃສ່ແລ້ວ $filled • ຊື້ແຜນນີ້ ${_q(total)}$shownTxt',
        onSave: widget.onSave,
        onExport: widget.onExport,
        onPdf: () => exportPlanPdf(widget.plan, widget.items),
        onAdd: _addMore,
      ),
    );
  }
}
