import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';
import 'branch_price_table.dart';

class PriceReportPage extends StatefulWidget {
  const PriceReportPage({super.key});
  @override
  State<PriceReportPage> createState() => _PriceReportPageState();
}

class _PriceReportPageState extends State<PriceReportPage> {
  List<Map<String, dynamic>> _branches = [];
  dynamic _branchId;
  DateTimeRange _range = DateTimeRange(
      start: DateTime(DateTime.now().year, DateTime.now().month, 1),
      end: DateTime.now());
  Future<List<BranchPriceRow>>? _f;

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _v(dynamic v) => double.tryParse('$v') ?? 0;

  @override
  void initState() {
    super.initState();
    loadBranches().then((b) {
      if (mounted) setState(() => _branches = b);
    }).catchError((_) {});
    _load();
  }

  String _url(dynamic branchId) =>
      '/repair/price-report?from=${_d(_range.start)}&to=${_d(_range.end)}${branchId == null ? '' : '&branchId=$branchId'}';

  Future<List<BranchPriceRow>> _fetchBranch(String name, dynamic id) async {
    final d = await Api.get(_url(id));
    final m = d is Map ? d : {};
    final rows = asList(m['rows']);
    final Map<String, List<double>> byCur = {};
    for (final r in rows) {
      final cur = pick(r, ['currency']);
      final qty = _v(r['qty']);
      final buy = _v(r['amount']);
      final sale = r['saleAmount'] != null
          ? _v(r['saleAmount'])
          : _v(pick(r, ['salePrice', 'priceSale', 'sellPrice'])) * qty;
      final acc = byCur.putIfAbsent(cur, () => [0, 0]);
      acc[0] += buy;
      acc[1] += sale;
    }
    if (byCur.isEmpty) {
      return [
        BranchPriceRow(
            branch: name, currency: '', priceBuy: 0, priceSale: 0, total: 0)
      ];
    }
    return [
      for (final e in byCur.entries)
        BranchPriceRow(
            branch: name,
            currency: e.key,
            priceBuy: e.value[0],
            priceSale: e.value[1],
            total: e.value[1] > 0 ? e.value[1] : e.value[0]),
    ];
  }

  Future<List<BranchPriceRow>> _loadAll() async {
    if (_branchId != null) {
      final b = _branches.where((x) => x['id'] == _branchId).toList();
      final name =
          b.isEmpty ? '$_branchId' : pick(b.first, ['name', 'branchName', 'id']);
      return _fetchBranch(name, _branchId);
    }
    final bl = _branches.isEmpty ? await loadBranches() : _branches;
    final res = await Future.wait([
      for (final b in bl)
        _fetchBranch(pick(b, ['name', 'branchName', 'id']), b['id'])
    ]);
    return [for (final l in res) ...l];
  }

  void _load() {
    setState(() {
      _f = _loadAll();
    });
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDateRange: _range);
    if (r == null) return;
    _range = r;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ລາຍງານລາຄາອາໄຫຼ່')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<dynamic>(
          key: ValueKey('rb-${_branches.length}-$_branchId'),
          initialValue:
              _branches.any((b) => b['id'] == _branchId) ? _branchId : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'ສາຂາ'),
          items: [
            const DropdownMenuItem(value: null, child: Text('ທຸກສາຂາ')),
            for (final b in _branches)
              DropdownMenuItem(
                  value: b['id'],
                  child: Text(pick(b, ['name', 'branchName', 'id']))),
          ],
          onChanged: (v) {
            _branchId = v;
            _load();
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range),
          label: Text('${_d(_range.start)}  →  ${_d(_range.end)}'),
          onPressed: _pickRange,
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<BranchPriceRow>>(
          future: _f,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()));
            }
            if (s.hasError) return ErrorView(s.error as Object, _load);
            final rows = s.data ?? <BranchPriceRow>[];
            if (rows.isEmpty) {
              return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                      child:
                          Text('ບໍ່ມີຂໍ້ມູນ', style: TextStyle(color: p.mut))));
            }
            return BranchPriceTable(rows: rows);
          },
        ),
      ]),
    );
  }
}
