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

  void _showPos(BranchPriceRow r) {
    final p = pal(context);
    final list = _pos
        .where((x) =>
            '${x['branchId']}' == r.branchId &&
            (r.currency.isEmpty || pick(x, ['currency']) == r.currency))
        .toList();
    final sum = list.fold<double>(0, (s, x) => s + _v(x['total']));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(r.branch,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('${_d(_range.start)}  →  ${_d(_range.end)}',
                    style: TextStyle(color: p.mut, fontSize: 12)),
              ),
              const Divider(height: 1),
              if (list.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                        child: Text('ບໍ່ມີຂໍ້ມູນ',
                            style: TextStyle(color: p.mut))))
              else
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final x in list)
                      ListTile(
                        title: Text(pick(x, ['poNo']).isEmpty
                            ? 'ບໍ່ມີ PO'
                            : 'PO ${pick(x, ['poNo'])}'),
                        subtitle: Text(
                            '${pick(x, ['grnNo'])} · ${pick(x, ['receiptDate']).split('T').first}',
                            style: TextStyle(color: p.mut, fontSize: 12)),
                        trailing: Text(
                            '${_n(x['total'])} ${pick(x, ['currency'])}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                  ]),
                ),
              if (list.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                        'ລວມ ${sum.toStringAsFixed(2)} ${r.currency}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
            return BranchPriceTable(rows: rows, onTap: _showPos);
          },
        ),
      ]),
    );
  }
}
