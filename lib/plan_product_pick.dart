import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'image_search.dart' show SearchTools;
import 'plan_bar.dart';
import 'product_images.dart' show productImageUrl;
import 'widgets.dart';

class PlanProductPickPage extends StatefulWidget {
  final Set<String> existing;
  final String initialQuery;
  const PlanProductPickPage({super.key, required this.existing, this.initialQuery = ""});
  @override
  State<PlanProductPickPage> createState() => _PlanProductPickPageState();
}

class _PlanProductPickPageState extends State<PlanProductPickPage> {
  final _qc = TextEditingController();
  Timer? _deb;
  List<Map<String, dynamic>> _list = [];
  final Map<String, Map<String, dynamic>> _sel = {};
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
      if (l.isNotEmpty) {
        debugPrint('[PLANPICK] first product keys: ${l.first.keys.toList()}');
      }
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
        final have = widget.existing.contains(id);
        final sub = [
          if (have) 'ມີໃນແຜນແລ້ວ',
          pick(m, ['brand', 'brandName']),
          pick(m, ['barcode', 'barcodes']),
        ].where((e) => e.isNotEmpty).join(' • ');
        return CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          value: have ? true : _sel.containsKey(id),
          secondary: _thumb(pick(m, ['imageUrl', 'image', 'photo'])),
          title: Text(pick(m, ['name', 'productName'])),
          subtitle: sub.isEmpty ? null : Text(sub),
          onChanged: have
              ? null
              : (v) => setState(() {
                    if (v == true) {
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
    return Scaffold(
      appBar: AppBar(title: Text('ເລືອກສິນຄ້າ (${_sel.length})')),
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
        summary: 'ເລືອກແລ້ວ ${_sel.length}',
        items: [
          PlanNavItem(Icons.close, 'ຍົກເລີກ', () => Navigator.pop(context)),
          PlanNavItem(
              Icons.add_task,
              'ເພີ່ມ (${_sel.length})',
              _sel.isEmpty
                  ? null
                  : () => Navigator.pop(context, _sel.values.toList())),
        ],
      ),
    );
  }
}
