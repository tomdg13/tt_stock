import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'image_search.dart' show SearchTools;
import 'plan_bar.dart';
import 'product_images.dart' show productImageUrl;
import 'widgets.dart';

class PlanPickResult {
  final List<Map<String, dynamic>> add;
  final Set<String> tick;
  final Set<String> untick;
  final Set<String> remove;
  const PlanPickResult(this.add, this.tick, this.untick, this.remove);
  bool get isEmpty =>
      add.isEmpty && tick.isEmpty && untick.isEmpty && remove.isEmpty;
}

void applyPlanPick(List<Map<String, dynamic>> items, PlanPickResult r) {
  final have = <String>{for (final x in items) '${x['key']}'};
  for (final x in r.add) {
    if (have.add('${x['key']}')) items.add(x);
  }
  for (final x in items) {
    final k = '${x['key']}';
    if (r.tick.contains(k)) x['done'] = true;
    if (r.untick.contains(k)) x['done'] = false;
  }
  items.removeWhere((x) => r.remove.contains('${x['key']}'));
}

class PlanProductPickPage extends StatefulWidget {
  final Map<String, Map<String, dynamic>> existing;
  final String initialQuery;
  const PlanProductPickPage(
      {super.key, required this.existing, this.initialQuery = ''});
  @override
  State<PlanProductPickPage> createState() => _PlanProductPickPageState();
}

class _PlanProductPickPageState extends State<PlanProductPickPage> {
  final _qc = TextEditingController();
  Timer? _deb;
  List<Map<String, dynamic>> _list = [];
  final Map<String, Map<String, dynamic>> _sel = {};
  final Map<String, bool> _on = {};
  bool _loading = true;
  Object? _err;

  @override
  void initState() {
    super.initState();
    _qc.text = widget.initialQuery;
    _load();
  }

  @override
  void dispose() {
    _deb?.cancel();
    _qc.dispose();
    super.dispose();
  }

  String _id(Map<String, dynamic> m) {
    final id = pick(m, ['id', 'productId']);
    return id.isNotEmpty ? id : pick(m, ['name', 'productName']);
  }

  bool _was(String id) {
    final ex = widget.existing[id];
    return ex is Map<String, dynamic> && ex['done'] == true;
  }

  int get _changes {
    var n = _sel.length;
    _on.forEach((k, v) {
      if (v == _was(k)) return;
      n++;
    });
    return n;
  }

  PlanPickResult _result() {
    final tick = <String>{};
    final untick = <String>{};
    final remove = <String>{};
    _on.forEach((k, v) {
      if (v == _was(k)) return;
      final ex = widget.existing[k];
      final isNew = ex is Map<String, dynamic> && ex['isNew'] == true;
      if (v) {
        tick.add(k);
      } else if (isNew) {
        remove.add(k);
      } else {
        untick.add(k);
      }
    });
    return PlanPickResult(_sel.values.toList(), tick, untick, remove);
  }

  Map<String, dynamic> _toItem(Map<String, dynamic> m) {
    final unit = pick(m, ['unit', 'unitName', 'uom']);
    return {
      'key': _id(m),
      'name': pick(m, ['name', 'productName']),
      'brand': pick(m, ['brand', 'brandName']),
      'bin': pick(m, ['binCode']),
      'unit': unit.isEmpty ? 'ອັນ' : unit,
      'imageUrl': pick(m, ['imageUrl', 'image', 'photo']),
      'qty': 0,
      'done': true,
      'isNew': true,
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final q = Uri.encodeQueryComponent(_qc.text.trim());
      final d = await Api.get('/products?limit=50&active=1&q=$q');
      final l = asList(d);
      if (mounted) {
        setState(() {
          _list = l;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e;
          _loading = false;
        });
      }
    }
  }

  void _onQ(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 500), _load);
  }

  Widget _thumb(String raw) {
    final url = productImageUrl(raw);
    final holder = Container(
        width: 44,
        height: 44,
        color: Colors.black12,
        child: const Icon(Icons.image_outlined, size: 20));
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

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err case final Object e) {
      return ErrorView(e, _load);
    }
    if (_list.isEmpty) return const Center(child: Text('ບໍ່ພົບສິນຄ້າ'));
    return ListView.builder(
      itemCount: _list.length,
      itemBuilder: (_, i) {
        final m = _list[i];
        final id = _id(m);
        final ex = widget.existing[id];
        final inPlan = ex is Map<String, dynamic>;
        final isNew = ex is Map<String, dynamic> && ex['isNew'] == true;
        final checked = inPlan ? (_on[id] ?? _was(id)) : _sel.containsKey(id);
        var status = '';
        if (inPlan) {
          if (checked == _was(id)) {
            status = isNew
                ? 'ເຄື່ອງທີ່ບໍ່ເຄີຍຊື້ • ໃນແຜນ'
                : (checked ? 'ໃນແຜນແລ້ວ' : 'ໃນແຜນ (ຍັງບໍ່ຕິກ)');
          } else {
            status = checked
                ? 'ຈະຕິກ'
                : (isNew ? 'ຈະເອົາອອກຈາກແຜນ' : 'ຈະເອົາຕິກອອກ');
          }
        }
        final sub = [
          status,
          pick(m, ['brand', 'brandName']),
          pick(m, ['barcode', 'barcodes']),
        ].where((e) => e.isNotEmpty).join(' • ');
        return CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          value: checked,
          secondary: _thumb(pick(m, ['imageUrl', 'image', 'photo'])),
          title: Text(pick(m, ['name', 'productName'])),
          subtitle: sub.isEmpty ? null : Text(sub),
          onChanged: (v) => setState(() {
            if (inPlan) {
              _on[id] = v == true;
            } else if (v == true) {
              _sel[id] = _toItem(m);
            } else {
              _sel.remove(id);
            }
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _changes;
    return Scaffold(
      appBar: AppBar(title: Text('ເລືອກສິນຄ້າ ($n)')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _qc,
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: 'ຄົ້ນຫາສິນຄ້າ',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  SearchTools(onResult: (v) {
                    _qc.text = v;
                    _deb?.cancel();
                    _load();
                  }),
                  IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _qc.clear();
                        _deb?.cancel();
                        _load();
                      }),
                ])),
            onChanged: _onQ,
          ),
        ),
        Expanded(child: _body()),
      ]),
      bottomNavigationBar: PlanNav(
        summary: 'ເພີ່ມ ${_sel.length} • ແກ້ໄຂ ${n - _sel.length}',
        items: [
          PlanNavItem(Icons.close, 'ຍົກເລີກ', () => Navigator.pop(context)),
          PlanNavItem(Icons.save_outlined, 'ບັນທຶກ ($n)',
              n == 0 ? null : () => Navigator.pop(context, _result())),
        ],
      ),
    );
  }
}
