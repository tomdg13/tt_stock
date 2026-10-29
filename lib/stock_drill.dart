// Stock drill-down: Brand > Model > products (qty, min, low flag, branch, bin).
// Data: GET /stock/overview (one row per product x model x branch).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'terminal_history.dart';
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


// ------------------------------------------------------------ Stock report
class StockReport extends StatefulWidget {
  const StockReport({super.key});
  @override
  State<StockReport> createState() => _StockReportState();
}

class _StockReportState extends State<StockReport> {
  final _q = TextEditingController();
  bool _low = false;
  String _by = 'brand';
  String? _brandF;
  String? _branchF;
  String? _dBrand;
  String? _dModel;
  bool _showTerm = true;
  List<List<String>> _lines = [];
  late Future<dynamic> _f = Api.get('/stock/overview');

  static const _byLabels = {
    'brand': 'Brand',
    'model': 'ຮຸ່ນ',
    'branch': 'ສາຂາ',
    'product': 'ສິນຄ້າ',
  };

  void _reload() => setState(() {
        _f = Api.get('/stock/overview');
      });

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _branchOf(Map<String, dynamic> r) {
    final v = pick(r, ['branchName']);
    return v.isEmpty ? '(ບໍ່ມີສາຂາ)' : v;
  }

  String _keyOf(Map<String, dynamic> r) {
    if (_dBrand != null) return _modelOf(r);
    switch (_by) {
      case 'model':
        return _modelOf(r);
      case 'branch':
        return _branchOf(r);
      case 'product':
        final v = pick(r, ['productName']);
        return v.isEmpty ? '-' : v;
      default:
        return _brandOf(r);
    }
  }

  String get _groupLabel => _dBrand != null ? 'ຮຸ່ນ' : _byLabels[_by]!;

  bool get _canDrill => _dBrand != null || _by == 'brand' || _by == 'model';

  void _drill(String k) => setState(() {
        if (_dBrand != null) {
          _dModel = k;
        } else if (_by == 'brand') {
          _dBrand = k;
        } else if (_by == 'model') {
          _dModel = k;
        }
      });

  void _back() => setState(() {
        if (_dModel != null) {
          _dModel = null;
        } else {
          _dBrand = null;
        }
      });

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    final q = _q.text.trim().toLowerCase();
    return rows.where((r) {
      if (_low && !_isLow(r)) return false;
      if (_brandF != null && _brandOf(r) != _brandF) return false;
      if (_branchF != null && _branchOf(r) != _branchF) return false;
      if (_dBrand != null && _brandOf(r) != _dBrand) return false;
      if (_dModel != null && _modelOf(r) != _dModel) return false;
      if (q.isEmpty) return true;
      return pick(r, ['productName']).toLowerCase().contains(q) ||
          pick(r, ['brandName']).toLowerCase().contains(q) ||
          pick(r, ['modelName']).toLowerCase().contains(q);
    }).toList();
  }

  void _copy() {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ບໍ່ມີຂໍ້ມູນ')));
      return;
    }
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final text = _lines.map((l) => l.map(q).join(',')).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('ຄັດລອກ CSV ແລ້ວ')));
  }

  Widget _dd(String label, List<String> items, String? val,
      ValueChanged<String?> on) {
    return DropdownButton<String?>(
      isExpanded: true,
      value: items.contains(val) ? val : null,
      hint: Text(label),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text('$label: ທັງໝົດ')),
        for (final i in items)
          DropdownMenuItem<String?>(
              value: i, child: Text(i, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: on,
    );
  }

  Widget _crumbs(Pal p) {
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        Expanded(
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            InkWell(
              onTap: () => setState(() {
                _dBrand = null;
                _dModel = null;
              }),
              child: Text('ທັງໝົດ', style: TextStyle(color: p.mut)),
            ),
            if (_dBrand != null) ...[
              const Text('  ›  '),
              InkWell(
                onTap: _dModel == null
                    ? null
                    : () => setState(() => _dModel = null),
                child: Text(_dBrand!, style: bold),
              ),
            ],
            if (_dModel != null) ...[
              const Text('  ›  '),
              Text(_dModel!, style: bold),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _card(Pal p, DataTable table) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
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
      ),
    );
  }

  DataTable _mk(Pal p, List<DataColumn> cols, List<DataRow> rows) {
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

  Widget _groupView(Pal p, List<Map<String, dynamic>> rows) {
    final groups = <String, _Agg>{};
    final all = <String, double>{};
    final allP = <String>{};
    final allLow = <String>{};
    for (final r in rows) {
      final a = groups.putIfAbsent(_keyOf(r), () => _Agg());
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
    final totalQty = all.values.fold(0.0, (a, b) => a + b);
    _lines = [
      [_groupLabel, 'ສິນຄ້າ', 'ຈຳນວນ', 'ໃກ້ໝົດ'],
      for (final k in keys)
        [
          k,
          '${groups[k]!.products.length}',
          _fmt(groups[k]!.total),
          '${groups[k]!.low.length}'
        ],
      ['ລວມ', '${allP.length}', _fmt(totalQty), '${allLow.length}'],
    ];
    const bold = TextStyle(fontWeight: FontWeight.w700);
    final drill = _canDrill;
    final dataRows = <DataRow>[
      for (final k in keys)
        DataRow(
          onSelectChanged: drill ? (_) => _drill(k) : null,
          cells: [
            DataCell(Text(k, style: bold)),
            DataCell(Text('${groups[k]!.products.length}')),
            DataCell(Text(_fmt(groups[k]!.total), style: bold)),
            DataCell(Text('${groups[k]!.low.length}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: groups[k]!.low.isEmpty ? p.mut : p.bad))),
            DataCell(drill ? const Icon(Icons.chevron_right) : const Text('')),
          ],
        ),
      DataRow(cells: [
        const DataCell(Text('ລວມ', style: bold)),
        DataCell(Text('${allP.length}', style: bold)),
        DataCell(Text(_fmt(totalQty), style: bold)),
        DataCell(Text('${allLow.length}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: allLow.isEmpty ? p.mut : p.bad))),
        const DataCell(Text('')),
      ]),
    ];
    return _card(
      p,
      _mk(
        p,
        [
          DataColumn(label: Text(_groupLabel)),
          const DataColumn(label: Text('ສິນຄ້າ'), numeric: true),
          const DataColumn(label: Text('ຈຳນວນ'), numeric: true),
          const DataColumn(label: Text('ໃກ້ໝົດ'), numeric: true),
          const DataColumn(label: Text('')),
        ],
        dataRows,
      ),
    );
  }

  Widget _itemView(Pal p, List<Map<String, dynamic>> rows) {
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
    final lines = <List<String>>[
      ['ສິນຄ້າ', 'ຕ່ຳສຸດ', 'ຈຳນວນ', 'ສະຖານະ', 'ສາຂາ', 'ບິນ'],
    ];
    for (final r in list) {
      final q = _n(r, 'qty'), mn = _n(r, 'minStock');
      final low = _isLow(r);
      total += q;
      final branch = pick(r, ['branchName']);
      final bin = pick(r, ['binCode']);
      lines.add([
        pick(r, ['productName']),
        _fmt(mn),
        _fmt(q),
        low ? 'ໃກ້ໝົດ' : 'ປົກກະຕິ',
        branch,
        bin,
      ]);
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
    lines.add(['ລວມ', '', _fmt(total), '', '', '']);
    _lines = lines;
    dataRows.add(DataRow(cells: [
      const DataCell(Text('ລວມ', style: bold)),
      const DataCell(Text('')),
      DataCell(Text(_fmt(total), style: bold)),
      const DataCell(Text('')),
      const DataCell(Text('')),
      const DataCell(Text('')),
    ]));
    return _card(
      p,
      _mk(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final drilled = _dBrand != null || _dModel != null;
    return PopScope(
      canPop: !drilled,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ລາຍງານສະຕັອກ',
              style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
                icon: const Icon(Icons.copy_all_outlined),
                tooltip: 'ຄັດລອກ CSV',
                onPressed: _copy),
            IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'ໂຫຼດໃໝ່',
                onPressed: _reload),
          ],
        ),
        body: FutureBuilder(
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
            final allRows = asList(s.data);
            final brands = allRows.map(_brandOf).toSet().toList()..sort();
            final branches = allRows.map(_branchOf).toSet().toList()..sort();
            final rows = _filter(allRows);

            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
              if (!drilled) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(children: [
                    Expanded(
                        child: _dd('Brand', brands, _brandF,
                            (v) => setState(() => _brandF = v))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _dd('ສາຂາ', branches, _branchF,
                            (v) => setState(() => _branchF = v))),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('ຈັດກຸ່ມ:', style: TextStyle(color: p.mut)),
                      for (final e in _byLabels.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: _by == e.key,
                          onSelected: (_) => setState(() => _by = e.key),
                        ),
                    ],
                  ),
                ),
              ] else
                _crumbs(p),
              if (_dModel != null)
                _ViewToggle(
                    term: _showTerm,
                    onChanged: (v) => setState(() => _showTerm = v)),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text('ຍັງບໍ່ມີລາຍການ',
                            style: TextStyle(color: p.mut)))
                    : (_dModel != null
                        ? (_showTerm ? _ModelTerminals(brand: _dBrand ?? "", model: _dModel!) : _itemView(p, rows))
                        : _groupView(p, rows)),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ Terminals of a model
class _ViewToggle extends StatelessWidget {
  final bool term;
  final ValueChanged<bool> onChanged;
  const _ViewToggle({required this.term, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
              value: true, label: Text('Terminal'), icon: Icon(Icons.memory)),
          ButtonSegment(
              value: false,
              label: Text('ສະຕັອກ'),
              icon: Icon(Icons.inventory_2_outlined)),
        ],
        selected: {term},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _ModelTerminals extends StatefulWidget {
  final String model;
  final String brand;
  const _ModelTerminals({required this.model, this.brand = ''});
  @override
  State<_ModelTerminals> createState() => _ModelTerminalsState();
}

class _ModelTerminalsState extends State<_ModelTerminals> {
  late Future<dynamic> _f = Api.get('/terminals?limit=500');

  bool _match(Map<String, dynamic> t) {
    final m = widget.model.toLowerCase();
    for (final k in const ['modelName', 'model', 'typeName', 'type']) {
      final v = pick(t, [k]).toLowerCase();
      if (v.isEmpty) continue;
      if (v == m) return true;
      if (v.length >= 3 && m.length >= 3 && (v.contains(m) || m.contains(v))) {
        return true;
      }
    }
    return false;
  }

  String _typeOf(Map<String, dynamic> t) {
    final v = pick(t, ['typeName']);
    return v.isEmpty ? '(ບໍ່ມີ type)' : v;
  }

  String get _path =>
      [widget.brand, widget.model].where((e) => e.isNotEmpty).join(' › ');

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return FutureBuilder(
      future: _f,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return Center(child: Text('${s.error}', textAlign: TextAlign.center));
        }
        final all = asList(s.data);
        final ofModel = all.where(_match).toList();
        if (ofModel.isEmpty) {
          return ListView(padding: const EdgeInsets.all(16), children: [
            const SizedBox(height: 60),
            Center(
                child: Text('ບໍ່ພົບ terminal ຂອງ ${widget.model}',
                    style: TextStyle(color: p.mut))),
            if (all.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('fields: ${all.first.keys.join(', ')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.mut, fontSize: 12)),
              ),
          ]);
        }
        final byType = <String, List<Map<String, dynamic>>>{};
        for (final t in ofModel) {
          byType.putIfAbsent(_typeOf(t), () => []).add(t);
        }
        final types = byType.keys.toList()..sort();
        const bold = TextStyle(fontWeight: FontWeight.w700);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            AppCard(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minWidth: MediaQuery.of(context).size.width - 64),
                  child: DataTable(
                    showCheckboxColumn: false,
                    columnSpacing: 20,
                    horizontalMargin: 8,
                    headingRowHeight: 38,
                    dataRowMinHeight: 46,
                    dataRowMaxHeight: 54,
                    dividerThickness: 0.6,
                    headingTextStyle: TextStyle(
                        color: p.mut,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    columns: const [
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Terminal'), numeric: true),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final t in types)
                        DataRow(
                          onSelectChanged: (_) => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => _TypeTerminalsPage(
                                      path: '$_path › $t',
                                      items: byType[t]!))),
                          cells: [
                            DataCell(Text(t, style: bold)),
                            DataCell(Text('${byType[t]!.length}')),
                            const DataCell(Icon(Icons.chevron_right)),
                          ],
                        ),
                      DataRow(cells: [
                        const DataCell(Text('ລວມ', style: bold)),
                        DataCell(Text('${ofModel.length}', style: bold)),
                        const DataCell(Text('')),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TypeTerminalsPage extends StatefulWidget {
  final String path;
  final List<Map<String, dynamic>> items;
  const _TypeTerminalsPage({required this.path, required this.items});
  @override
  State<_TypeTerminalsPage> createState() => _TypeTerminalsPageState();
}

class _TypeTerminalsPageState extends State<_TypeTerminalsPage> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final q = _q.text.trim().toLowerCase();
    final list = widget.items.where((t) {
      if (q.isEmpty) return true;
      return pick(t, ['barcode']).toLowerCase().contains(q) ||
          pick(t, ['serial']).toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => pick(a, ['barcode']).compareTo(pick(b, ['barcode'])));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.path,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                hintText: 'ຄົ້ນຫາ barcode / serial',
                prefixIcon: Icon(Icons.search),
                isDense: true),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${list.length} / ${widget.items.length} terminal',
                style: TextStyle(color: p.mut, fontSize: 12)),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text('ບໍ່ພົບລາຍການ', style: TextStyle(color: p.mut)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final t in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(pick(t, ['barcode']),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text([
                            pick(t, ['serial']),
                            pick(t, ['state', 'status'])
                          ].where((e) => e.isNotEmpty).join(' · ')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => _TerminalPartsPage(
                                      path: widget.path,
                                      barcode: pick(t, ['barcode'])))),
                        ),
                      ),
                  ],
                ),
        ),
      ]),
    );
  }
}

class _TerminalPartsPage extends StatefulWidget {
  final String path;
  final String barcode;
  const _TerminalPartsPage({required this.path, required this.barcode});
  @override
  State<_TerminalPartsPage> createState() => _TerminalPartsPageState();
}

class _TerminalPartsPageState extends State<_TerminalPartsPage> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  void _reload() => setState(() {
        _f = _load();
      });

  Future<List<Map<String, dynamic>>> _load() async {
    final d = await Api.get(
        '/install/log?barcode=${Uri.encodeComponent(widget.barcode)}&limit=300');
    final rows = asList(d).where((l) {
      final up = pick(l, ['action']).toUpperCase();
      return up.startsWith('MA PART') ||
          up.startsWith('INSTALL') ||
          up.startsWith('REMOVE');
    }).toList();
    final zero = DateTime.fromMillisecondsSinceEpoch(0);
    rows.sort((a, b) =>
        (DateTime.tryParse(pick(b, ['logDate'])) ?? zero)
            .compareTo(DateTime.tryParse(pick(a, ['logDate'])) ?? zero));
    return rows;
  }

  String _actionLabel(String action) {
    final up = action.toUpperCase();
    if (up.startsWith('INSTALL')) return 'ຕິດຕັ້ງ';
    if (up.startsWith('REMOVE')) return 'ເອົາອອກ';
    return 'ໃຊ້';
  }

  String _qty(String action) {
    final m = RegExp(r'X(\d+)$').firstMatch(action.toUpperCase());
    return m == null ? '' : ' × ${m.group(1)}';
  }

  String _date(String raw) {
    final d = DateTime.tryParse(raw);
    if (d == null) return '';
    final l = d.toLocal();
    String t(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${t(l.month)}-${t(l.day)}\n${t(l.hour)}:${t(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.path} › ${widget.barcode}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'ປະຫວັດທັງໝົດ',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => HistoryPage(barcode: widget.barcode))),
          ),
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'ໂຫຼດໃໝ່',
              onPressed: _reload),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
          final rows = s.data ?? [];
          if (rows.isEmpty) {
            return Center(
                child: Text('ຍັງບໍ່ມີອາໄຫຼ່', style: TextStyle(color: p.mut)));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${rows.length} ລາຍການ',
                    style: TextStyle(color: p.mut, fontSize: 12)),
              ),
              for (final l in rows)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                        pick(l, ['productName']).isEmpty
                            ? '-'
                            : pick(l, ['productName']),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      [
                        '${_actionLabel(pick(l, ['action']))}${_qty(pick(l, ['action']))}',
                        pick(l, ['serialNo']),
                        pick(l, ['userName']),
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: TextStyle(
                          color: _actionLabel(pick(l, ['action'])) == 'ເອົາອອກ'
                              ? p.bad
                              : p.mut),
                    ),
                    trailing: Text(_date(pick(l, ['logDate'])),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: p.mut, fontSize: 12)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
