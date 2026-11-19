import 'package:flutter/material.dart';
import 'api.dart';
import 'image_search.dart' show SearchTools;
import 'plan_bar.dart';
import 'product_images.dart' show productImageUrl;

class PlanPickPage extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onExport;
  const PlanPickPage({super.key, required this.items, required this.onExport});
  @override
  State<PlanPickPage> createState() => _PlanPickPageState();
}

class _PlanPickPageState extends State<PlanPickPage> {
  final _qc = TextEditingController();
  String _q = '';
  final Set<Map<String, dynamic>> _sel = {};

  @override
  void dispose() {
    _qc.dispose();
    super.dispose();
  }

  void _onQ(String v) => setState(() => _q = v.trim().toLowerCase());

  Widget _thumb(String raw) {
    final url = productImageUrl(raw);
    final holder = Container(
        width: 44,
        height: 44,
        color: Colors.black12,
        child: const Icon(Icons.inventory_2_outlined, size: 20));
    if (url.isEmpty) return holder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
          width: 44,
          height: 44,
          child: Image.network(url,
              fit: BoxFit.cover,
              headers: Api.token == null
                  ? null
                  : {'Authorization': 'Bearer ${Api.token}'},
              errorBuilder: (_, __, ___) => holder)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = widget.items.where((x) {
      if (_q.isEmpty) return true;
      return ['name', 'brand', 'bin']
          .any((k) => '${x[k] ?? ''}'.toLowerCase().contains(_q));
    }).toList();
    final nSel = shown.where((x) => _sel.contains(x)).length;
    return Scaffold(
      appBar: AppBar(title: Text('ເລືອກເພີ່ມ (${_sel.length})')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _qc,
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: 'ຄົ້ນຫາອາໄຫຼ່',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  SearchTools(onResult: (v) {
                    _qc.text = v;
                    _onQ(v);
                  }),
                  IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _qc.clear();
                        _onQ('');
                      }),
                ])),
            onChanged: _onQ,
          ),
        ),
        Material(
          color: cs.surfaceContainerHighest,
          child: CheckboxListTile(
            tristate: true,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: nSel == 0 ? false : (nSel == shown.length ? true : null),
            title: Text('ເລືອກທັງໝົດ (${shown.length})',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            onChanged: (_) => setState(() {
              if (nSel == shown.length) {
                for (final x in shown) {
                  _sel.remove(x);
                }
              } else {
                _sel.addAll(shown);
              }
            }),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('ບໍ່ມີຂໍ້ມູນ'))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final x = shown[i];
                    final sub = ['${x['brand'] ?? ''}', '${x['bin'] ?? ''}']
                        .where((e) => e.isNotEmpty)
                        .join(' • ');
                    return CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _sel.contains(x),
                      secondary: _thumb('${x['imageUrl'] ?? ''}'),
                      title: Text('${x['name'] ?? ''}'),
                      subtitle: sub.isEmpty ? null : Text(sub),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _sel.add(x);
                        } else {
                          _sel.remove(x);
                        }
                      }),
                    );
                  }),
        ),
      ]),
      bottomNavigationBar: PlanNav(
        summary: 'ເລືອກແລ້ວ ${_sel.length} / ${widget.items.length}',
        items: [
          PlanNavItem(Icons.save_outlined, 'ບັນທຶກ (${_sel.length})',
              _sel.isEmpty ? null : () => Navigator.pop(context, _sel.toList())),
          PlanNavItem(Icons.checklist, 'ລາຍການ',
              () => Navigator.pop(context, <Map<String, dynamic>>[])),
          PlanNavItem(Icons.table_view_outlined, 'Excel',
              () => widget.onExport()),
        ],
      ),
    );
  }
}
