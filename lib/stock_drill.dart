// Stock drill-down: Brand > Model > products (qty, min, low flag, branch, bin).
// Data: GET /stock/overview (one row per product x model x branch).
import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

const _kNoBrand = '(ບໍ່ມີ Brand)';
const _kNoModel = '(ບໍ່ມີຮຸ່ນ)';

double _n(Map<String, dynamic> r, String k) =>
    double.tryParse(pick(r, [k])) ?? 0;

String _fmt(double v) {
  final neg = v < 0;
  final a = v.abs();
  final s = a == a.roundToDouble() ? a.round().toString() : a.toStringAsFixed(2);
  final parts = s.split('.');
  parts[0] = parts[0]
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return (neg ? '-' : '') + parts.join('.');
}

String _brandOf(Map<String, dynamic> r) {
  final v = pick(r, ['brandName']);
  return v.isEmpty ? _kNoBrand : v;
}

String _modelOf(Map<String, dynamic> r) {
  final v = pick(r, ['modelName']);
  return v.isEmpty ? _kNoModel : v;
}

bool _isLow(Map<String, dynamic> r) {
  final mn = _n(r, 'minStock');
  return mn > 0 && _n(r, 'qty') < mn;
}

class _Agg {
  final products = <String>{};
  final qty = <String, double>{};
  final low = <String>{};
  double get total => qty.values.fold(0.0, (a, b) => a + b);
}

class StockDrill extends StatefulWidget {
  const StockDrill({super.key});
  @override
  State<StockDrill> createState() => _StockDrillState();
}

class _StockDrillState extends State<StockDrill> {
  final _q = TextEditingController();
  bool _low = false;
  String? _brand;
  String? _model;
  late Future<dynamic> _f = Api.get('/stock/overview');

  void _reload() => setState(() {
        _f = Api.get('/stock/overview');
      });

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    final q = _q.text.trim().toLowerCase();
    return rows.where((r) {
      if (_low && !_isLow(r)) return false;
      if (q.isEmpty) return true;
      return pick(r, ['productName']).toLowerCase().contains(q) ||
          pick(r, ['brandName']).toLowerCase().contains(q) ||
          pick(r, ['modelName']).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  hintText: 'ຄົ້ນຫາສິນຄ້າ / Brand / ຮຸ່ນ',
                  prefixIcon: Icon(Icons.search)),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('ໃກ້ໝົດ'),
            selected: _low,
            onSelected: (v) => setState(() => _low = v),
          ),
        ]),
      ),
      _crumbs(p),
      Expanded(
        child: FutureBuilder(
          future: _f,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (s.hasError) {
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${s.error}', textAlign: TextAlign.center),
                TextButton(onPressed: _reload, child: const Text('ລອງໃໝ່')),
              ]));
            }
            final rows = _filter(asList(s.data));
            return RefreshIndicator(
                onRefresh: () async => _reload(), child: _body(p, rows));
          },
        ),
      ),
    ]);
  }

  Widget _crumbs(Pal p) {
    if (_brand == null) return const SizedBox(height: 4);
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            if (_model != null) {
              _model = null;
            } else {
              _brand = null;
            }
          }),
        ),
        Expanded(
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            InkWell(
              onTap: () => setState(() {
                _brand = null;
                _model = null;
              }),
              child: Text('ທັງໝົດ', style: TextStyle(color: p.mut)),
            ),
            const Text('  ›  '),
            InkWell(
              onTap: _model == null ? null : () => setState(() => _model = null),
              child: Text(_brand!, style: bold),
            ),
            if (_model != null) ...[
              const Text('  ›  '),
              Text(_model!, style: bold),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _body(Pal p, List<Map<String, dynamic>> rows) {
    var scoped = rows;
    if (_brand != null) {
      scoped = scoped.where((r) => _brandOf(r) == _brand).toList();
    }
    if (_model != null) {
      scoped = scoped.where((r) => _modelOf(r) == _model).toList();
    }
    if (scoped.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 120),
        Center(child: Text('ຍັງບໍ່ມີລາຍການ', style: TextStyle(color: p.mut))),
      ]);
    }
    if (_brand == null) return _groupTable(p, scoped, byBrand: true);
    if (_model == null) return _groupTable(p, scoped, byBrand: false);
    return _itemTable(p, scoped);
  }

  Widget _wrap(Widget table) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        AppCard(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 64),
              child: table,
            ),
          ),
        ),
      ],
    );
  }

  DataTable _table(Pal p, List<DataColumn> cols, List<DataRow> rows,
      {bool selectable = false}) {
    return DataTable(
      showCheckboxColumn: false,
      columnSpacing: 20,
      horizontalMargin: 8,
      headingRowHeight: 38,
      dataRowMinHeight: 46,
      dataRowMaxHeight: 54,
      dividerThickness: 0.6,
      headingTextStyle:
          TextStyle(color: p.mut, fontSize: 12, fontWeight: FontWeight.w600),
      columns: cols,
      rows: rows,
    );
  }

  Widget _groupTable(Pal p, List<Map<String, dynamic>> rows,
      {required bool byBrand}) {
    final groups = <String, _Agg>{};
    final all = <String, double>{};
    final allP = <String>{};
    final allLow = <String>{};
    for (final r in rows) {
      final key = byBrand ? _brandOf(r) : _modelOf(r);
      final a = groups.putIfAbsent(key, () => _Agg());
      final pid = pick(r, ['productId']);
      final pk = '$pid|${pick(r, ['branchId'])}';
      a.products.add(pid);
      a.qty[pk] = _n(r, 'qty');
      all[pk] = _n(r, 'qty');
      allP.add(pid);
      if (_isLow(r)) {
        a.low.add(pid);
        allLow.add(pid);
      }
    }
    final keys = groups.keys.toList()
      ..sort((x, y) {
        final ax = x.startsWith('('), ay = y.startsWith('(');
        if (ax != ay) return ax ? 1 : -1;
        return x.toLowerCase().compareTo(y.toLowerCase());
      });
    const bold = TextStyle(fontWeight: FontWeight.w700);
    final dataRows = <DataRow>[
      for (final k in keys)
        DataRow(
          onSelectChanged: (_) => setState(() {
            if (byBrand) {
              _brand = k;
              _model = null;
            } else {
              _model = k;
            }
          }),
          cells: [
            DataCell(Text(k, style: bold)),
            DataCell(Text('${groups[k]!.products.length}')),
            DataCell(Text(_fmt(groups[k]!.total), style: bold)),
            DataCell(Text('${groups[k]!.low.length}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: groups[k]!.low.isEmpty ? p.mut : p.bad))),
            const DataCell(Icon(Icons.chevron_right)),
          ],
        ),
      DataRow(cells: [
        const DataCell(Text('ລວມ', style: bold)),
        DataCell(Text('${allP.length}', style: bold)),
        DataCell(Text(_fmt(all.values.fold(0.0, (a, b) => a + b)),
            style: bold)),
        DataCell(Text('${allLow.length}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: allLow.isEmpty ? p.mut : p.bad))),
        const DataCell(Text('')),
      ]),
    ];
    return _wrap(_table(
      p,
      [
        DataColumn(label: Text(byBrand ? 'Brand' : 'ຮຸ່ນ')),
        const DataColumn(label: Text('ສິນຄ້າ'), numeric: true),
        const DataColumn(label: Text('ຈຳນວນ'), numeric: true),
        const DataColumn(label: Text('ໃກ້ໝົດ'), numeric: true),
        const DataColumn(label: Text('')),
      ],
      dataRows,
    ));
  }

  Widget _itemTable(Pal p, List<Map<String, dynamic>> rows) {
    final list = [...rows]..sort((a, b) {
        final c = pick(a, ['productName'])
            .toLowerCase()
            .compareTo(pick(b, ['productName']).toLowerCase());
        if (c != 0) return c;
        return pick(a, ['branchName']).compareTo(pick(b, ['branchName']));
      });
    const bold = TextStyle(fontWeight: FontWeight.w700);
    double total = 0;
    final dataRows = <DataRow>[];
    for (final r in list) {
      final q = _n(r, 'qty'), mn = _n(r, 'minStock');
      final low = _isLow(r);
      total += q;
      final branch = pick(r, ['branchName']);
      final bin = pick(r, ['binCode']);
      dataRows.add(DataRow(cells: [
        DataCell(Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pick(r, ['productName']),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (pick(r, ['unit']).isNotEmpty)
              Text(pick(r, ['unit']),
                  style: TextStyle(color: p.mut, fontSize: 12)),
          ],
        )),
        DataCell(Text(_fmt(mn), style: TextStyle(color: p.mut))),
        DataCell(Text(_fmt(q),
            style: TextStyle(
                fontWeight: FontWeight.w700, color: low ? p.bad : p.tx))),
        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(low ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              size: 16, color: low ? p.bad : p.mut),
          const SizedBox(width: 4),
          Text(low ? 'ໃກ້ໝົດ' : 'ປົກກະຕິ',
              style: TextStyle(color: low ? p.bad : p.mut, fontSize: 13)),
        ])),
        DataCell(Text(branch.isEmpty ? 'ຍັງບໍ່ມີສະຕັອກ' : branch)),
        DataCell(Text(bin.isEmpty ? '-' : bin)),
      ]));
    }
    dataRows.add(DataRow(cells: [
      const DataCell(Text('ລວມ', style: bold)),
      const DataCell(Text('')),
      DataCell(Text(_fmt(total), style: bold)),
      const DataCell(Text('')),
      const DataCell(Text('')),
      const DataCell(Text('')),
    ]));
    return _wrap(_table(
      p,
      const [
        DataColumn(label: Text('ສິນຄ້າ')),
        DataColumn(label: Text('ຕ່ຳສຸດ'), numeric: true),
        DataColumn(label: Text('ຈຳນວນ'), numeric: true),
        DataColumn(label: Text('ສະຖານະ')),
        DataColumn(label: Text('ສາຂາ')),
        DataColumn(label: Text('ບິນ')),
      ],
      dataRows,
    ));
  }
}
