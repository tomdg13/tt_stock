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
  List<dynamic> _pos = [];
  List<dynamic> _items = [];
  DateTimeRange _range = DateTimeRange(
      start: DateTime(DateTime.now().year, DateTime.now().month, 1),
      end: DateTime.now());
  Future<List<BranchPriceRow>>? _f;

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _v(dynamic v) => double.tryParse('$v') ?? 0;
  String _n(dynamic v) => _v(v).toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    loadBranches().then((b) {
      if (mounted) setState(() => _branches = b);
    }).catchError((_) {});
    _load();
  }

  String _url() =>
      '/repair/price-report-branch?from=${_d(_range.start)}&to=${_d(_range.end)}${_branchId == null ? '' : '&branchId=$_branchId'}';

  Future<List<BranchPriceRow>> _loadAll() async {
    final bl = _branches.isEmpty ? await loadBranches() : _branches;
    final d = await Api.get(_url());
    final m = d is Map ? d : {};
    final pur = asList(m['purchases']);
    final usd = asList(m['used']);
    _pos = asList(m['pos']);
    _items = asList(m['items']);
    final list = _branchId == null
        ? bl
        : bl.where((b) => '${b['id']}' == '$_branchId').toList();
    final out = <BranchPriceRow>[];
    for (final b in list) {
      final id = '${b['id']}';
      final name = pick(b, ['name', 'branchName', 'id']);
      final cur = <String, List<double>>{};
      for (final r in pur) {
        if ('${r['branchId']}' == id) {
          final a = cur.putIfAbsent(pick(r, ['currency']), () => [0.0, 0.0]);
          a[0] += _v(r['total']);
        }
      }
      for (final r in usd) {
        if ('${r['branchId']}' == id) {
          final a = cur.putIfAbsent(pick(r, ['currency']), () => [0.0, 0.0]);
          a[1] += _v(r['used']);
        }
      }
      if (cur.isEmpty) {
        out.add(BranchPriceRow(
            branchId: id,
            branch: name,
            currency: '',
            priceBuy: 0,
            priceSale: 0,
            total: 0));
      } else {
        for (final e in cur.entries) {
          out.add(BranchPriceRow(
              branchId: id,
              branch: name,
              currency: e.key,
              priceBuy: e.value[0],
              priceSale: e.value[1],
              total: e.value[0] - e.value[1]));
        }
      }
    }
    return out;
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

  List<BranchPoItem> _posFor(BranchPriceRow r) {
    final list = _pos
        .where((x) =>
            '${x['branchId']}' == r.branchId &&
            (r.currency.isEmpty || pick(x, ['currency']) == r.currency))
        .toList();
    return [
      for (final x in list)
        BranchPoItem(
            id: '${x['id']}',
            po: pick(x, ['poNo']).isEmpty
                ? 'ບໍ່ມີ PO'
                : 'PO ${pick(x, ['poNo'])}',
            sub:
                '${pick(x, ['grnNo'])} · ${pick(x, ['receiptDate']).split('T').first}',
            amount: '${_n(x['total'])} ${pick(x, ['currency'])}',
            lines: [
              for (final e in _items.where((e) => '${e['grnId']}' == '${x['id']}'))
                BranchLineItem(
                    name: pick(e, ['partNo']).isEmpty
                        ? pick(e, ['name'])
                        : '${pick(e, ['partNo'])} · ${pick(e, ['name'])}',
                    sub: '${pick(e, ['qty'])} × ${_n(e['unitCost'])}',
                    amount: _n(e['amount'])),
            ]),
    ];
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
            return BranchPriceTable(
                key: ValueKey('t-${_range.start}-${_range.end}-$_branchId'),
                rows: rows,
                children: _posFor);
          },
        ),
      ]),
    );
  }
}
