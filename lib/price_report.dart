import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

class PriceReportPage extends StatefulWidget {
  const PriceReportPage({super.key});
  @override
  State<PriceReportPage> createState() => _PriceReportPageState();
}

class _PriceReportPageState extends State<PriceReportPage> {
  List<Map<String, dynamic>> _branches = [];
  dynamic _branchId = Api.user?['branchId'];
  DateTimeRange _range = DateTimeRange(
      start: DateTime(DateTime.now().year, DateTime.now().month, 1),
      end: DateTime.now());
  Future<dynamic>? _f;

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    loadBranches().then((b) {
      if (mounted) setState(() => _branches = b);
    }).catchError((_) {});
    _load();
  }

  void _load() {
    setState(() {
      _f = Api.get(
          '/repair/price-report?from=${_d(_range.start)}&to=${_d(_range.end)}${_branchId != null ? '&branchId=$_branchId' : ''}');
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

  String _n(dynamic v) => (num.tryParse('$v') ?? 0).toStringAsFixed(2);

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
        FutureBuilder(
          future: _f,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()));
            }
            if (s.hasError) return ErrorView(s.error!, _load);
            final d = s.data is Map ? s.data as Map : {};
            final rows = asList(d['rows']);
            final tot = d['totals'] is Map ? d['totals'] as Map : {};
            if (rows.isEmpty) {
              return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                      child:
                          Text('ບໍ່ມີຂໍ້ມູນ', style: TextStyle(color: p.mut))));
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in rows)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: p.bd))),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pick(r, ['productName'])),
                                Text(
                                    pick(r, ['poNo']).isEmpty
                                        ? '${pick(r, ['qty'])} ຊິ້ນ · ບໍ່ມີ PO'
                                        : 'PO ${pick(r, ['poNo'])} · ${pick(r, [
                                                'qty'
                                              ])} × ${_n(r['unitCost'])} ${pick(r, [
                                                'currency'
                                              ])}',
                                    style:
                                        TextStyle(color: p.mut, fontSize: 12)),
                              ]),
                        ),
                        Text(
                            pick(r, ['poNo']).isEmpty
                                ? '-'
                                : '${_n(r['amount'])} ${pick(r, ['currency'])}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  const SizedBox(height: 12),
                  for (final e in tot.entries)
                    Text('ລວມ ${_n(e.value)} ${e.key}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                ]);
          },
        ),
      ]),
    );
  }
}
