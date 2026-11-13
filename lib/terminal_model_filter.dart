import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// MODEL chips above a terminal list (same look as the product form).
/// Default ticks = the ATM's own model. Untick all = show everything.
class ModelFilterBody extends StatefulWidget {
  final String atmId;
  final Widget Function(bool Function(Map<String, dynamic>) modelFilter)
      builder;
  const ModelFilterBody(
      {super.key, required this.atmId, required this.builder});
  @override
  State<ModelFilterBody> createState() => _ModelFilterBodyState();
}

class _ModelFilterBodyState extends State<ModelFilterBody> {
  static String _n(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ກ-ໝ]'), '');
  List<Map<String, dynamic>> _models = [];
  final _sel = <String>{};
  String _brand = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var atm = <String, dynamic>{};
      if (widget.atmId.isNotEmpty) {
        final d = await Api.get('/atms/${Uri.encodeComponent(widget.atmId)}');
        if (d is Map) atm = Map<String, dynamic>.from(d);
      }
      final brand = pick(atm, ['atmType', 'atmBrand', 'brandName', 'brand']);
      final model = pick(atm, [
        'atmVersion',
        'atm_version',
        'version',
        'atmModel',
        'modelName',
        'model'
      ]);
      final rows = asList(await Api.get('/models'));
      var list = rows;
      final bn = _n(brand);
      if (bn.isNotEmpty) {
        final f = rows.where((r) {
          final b = _n(pick(r, ['brandName']));
          return b.isNotEmpty && (b == bn || bn.contains(b));
        }).toList();
        if (f.isNotEmpty) list = f;
      }
      final hay = _n(model);
      if (!mounted) return;
      setState(() {
        _brand = brand;
        _models = list;
        if (hay.isNotEmpty) {
          for (final r in list) {
            final nm = _n(pick(r, ['name']));
            if (nm.isNotEmpty && hay.contains(nm)) _sel.add(nm);
          }
        }
      });
    } catch (_) {}
  }

  bool _ok(Map<String, dynamic> m) {
    if (_sel.isEmpty) return true;
    final t = _n([
      pick(m, ['modelName', 'model']),
      pick(m, ['serial'])
    ].join(' '));
    return _sel.any((x) => t.contains(x));
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Column(children: [
      if (_models.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                    'MODEL ທີ່ສະແດງ${_brand.isEmpty ? '' : ' ($_brand)'}',
                    style: TextStyle(color: p.mut, fontSize: 14)),
              ),
              TextButton(
                onPressed: _sel.isEmpty ? null : () => setState(_sel.clear),
                child: const Text('ສະແດງທັງໝົດ'),
              ),
            ]),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in _models)
                FilterChip(
                  label: Text(pick(r, ['name'])),
                  selected: _sel.contains(_n(pick(r, ['name']))),
                  onSelected: (on) => setState(() {
                    final k = _n(pick(r, ['name']));
                    if (on) {
                      _sel.add(k);
                    } else {
                      _sel.remove(k);
                    }
                  }),
                ),
            ]),
          ]),
        ),
      Expanded(child: widget.builder(_ok)),
    ]);
  }
}
