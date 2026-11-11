// Budget: bought and used per fiscal year, stock now, need until a target year, amount to buy.
// Server: GET /stock/budget?fm=10&toYear=2028&pct=0&branchId=
import 'package:flutter/material.dart';
import 'api.dart';
import 'budget_excel.dart';
import 'product_images.dart' show productImageUrl;
import 'widgets.dart';

String _n(num v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

String _money(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (v < 0 ? '-' : '') + b.toString();
}

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});
  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  final _pct = TextEditingController(text: '0');
  int _fm = 10;
  int _toYear = DateTime.now().year + 2;
  dynamic _branchId;
  List<Map<String, dynamic>> _branches = [];
  Future<dynamic>? _f;
  Map<String, dynamic>? _last;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    loadBranches().then((b) {
      if (mounted) setState(() => _branches = b);
    }).catchError((_) {});
    _run();
  }

  @override
  void dispose() {
    _pct.dispose();
    super.dispose();
  }

  void _run() {
    final pct = int.tryParse(_pct.text.trim()) ?? 0;
    final q = [
      'fm=$_fm',
      'toYear=$_toYear',
      'pct=$pct',
      if (_branchId != null) 'branchId=$_branchId'
    ].join('&');
    final f = Api.get('/stock/budget?$q');
    setState(() {
      _f = f;
      _last = null;
    });
    f.then((d) {
      var x = d;
      if (x is Map && x['data'] is Map) x = x['data'];
      if (x is Map && mounted && identical(_f, f)) {
        setState(() => _last = Map<String, dynamic>.from(x));
      }
    }).catchError((_) {});
  }

  Future<void> _export() async {
    final d = _last;
    if (d == null) return;
    setState(() => _exporting = true);
    try {
      var bn = 'ທຸກສາຂາ';
      for (final b in _branches) {
        if ('${b['id']}' == '$_branchId') bn = pick(b, ['name']);
      }
      await exportBudgetXlsx(d, branchName: bn);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ສົ່ງອອກບໍ່ສຳເລັດ: $e')));
      }
    }
    if (mounted) setState(() => _exporting = false);
  }

  Widget _thumb(String raw) {
    final url = productImageUrl(raw);
    final holder = Container(
        width: 48,
        height: 48,
        color: Colors.black12,
        child: const Icon(Icons.inventory_2_outlined));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url.isEmpty
          ? holder
          : SizedBox(
              width: 48,
              height: 48,
              child: Image.network(url,
                  fit: BoxFit.cover,
                  headers: Api.token == null
                      ? null
                      : {'Authorization': 'Bearer ${Api.token}'},
                  errorBuilder: (_, __, ___) => holder)),
    );
  }

  Widget _table(List<String> head, List<List<String>> rows) {
    Widget cell(String t, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(t,
            style: TextStyle(
                fontSize: bold ? 11 : 12,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal)));
    return Table(children: [
      TableRow(children: [for (final h in head) cell(h, bold: true)]),
      for (final r in rows) TableRow(children: [for (final c in r) cell(c)]),
    ]);
  }

  Widget _filters() {
    final thisYear = DateTime.now().year;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<dynamic>(
            initialValue: _branchId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'ສາຂາ'),
            items: [
              const DropdownMenuItem<dynamic>(
                  value: null, child: Text('ທຸກສາຂາ')),
              for (final b in _branches)
                DropdownMenuItem<dynamic>(
                    value: b['id'], child: Text(pick(b, ['name']))),
            ],
            onChanged: (v) {
              _branchId = v;
              _run();
            },
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 10, label: Text('ຕຸລາ - ກັນຍາ')),
              ButtonSegment(value: 1, label: Text('ມັງກອນ - ທັນວາ')),
            ],
            selected: {_fm},
            onSelectionChanged: (s) {
              _fm = s.first;
              _run();
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _toYear,
                decoration: const InputDecoration(labelText: 'ຮອດສິ້ນປີ'),
                items: [
                  for (var y = thisYear; y <= thisYear + 6; y++)
                    DropdownMenuItem<int>(value: y, child: Text('$y')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _toYear = v;
                  _run();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _pct,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ເຜື່ອ (%)'),
                onSubmitted: (_) => _run(),
              ),
            ),
            IconButton(onPressed: _run, icon: const Icon(Icons.refresh)),
          ]),
        ]),
      ),
    );
  }

  Widget _summary(Map<String, dynamic> d) {
    final years = asList(d['budgetByYear']);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ງົບປະມານທີ່ຕ້ອງໃຊ້ຊື້',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final y in years)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text('${y['label']}')),
                Text(_money(num0(y['amount']))),
              ]),
            ),
          const Divider(),
          Row(children: [
            const Expanded(
                child: Text('ລວມ',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            Text(_money(num0(d['totalAmount'])),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          const Text('ລາຄາຕາມ COST_PRICE ຂອງສິນຄ້າ • ຄິດຈາກການໃຊ້ 12 ເດືອນຜ່ານມາ',
              style: TextStyle(fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _item(Map<String, dynamic> it, List<Map<String, dynamic>> past) {
    final unit = pick(it, ['unit']);
    final bought = (it['bought'] as List?) ?? const [];
    final used = (it['used'] as List?) ?? const [];
    final plan = asList(it['plan']);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: _thumb(pick(it, ['imageUrl'])),
        title: Text(pick(it, ['productName'])),
        subtitle: Text(
            'ສະຕັອກ ${_n(num0(it['stock']))} $unit  •  ໃຊ້/ປີ ${_n(num0(it['ratePerYear']))}\n'
            'ຕ້ອງຊື້ ${_n(num0(it['totalBuy']))} $unit'),
        trailing: Text(_money(num0(it['totalAmount'])),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Align(
              alignment: Alignment.centerLeft,
              child: Text('ລາຄາຕໍ່ໜ່ວຍ ${_money(num0(it['unitCost']))}',
                  style: const TextStyle(fontSize: 11))),
          const SizedBox(height: 6),
          _table(['ປີທີ່ຜ່ານມາ', 'ຊື້ແລ້ວ', 'ໃຊ້ໄປ'], [
            for (var i = 0; i < past.length; i++)
              [
                '${past[i]['label']}',
                i < bought.length ? _n(num0(bought[i])) : '0',
                i < used.length ? _n(num0(used[i])) : '0',
              ]
          ]),
          const SizedBox(height: 10),
          _table(['ປີຕໍ່ໄປ', 'ຕ້ອງໃຊ້', 'ຕ້ອງຊື້', 'ເງິນ'], [
            for (final x in plan)
              [
                '${x['label']}',
                _n(num0(x['need'])),
                _n(num0(x['buy'])),
                _money(num0(x['amount'])),
              ]
          ]),
        ],
      ),
    );
  }

  Widget _result(Map<String, dynamic> d) {
    final past = asList(d['pastYears']);
    final items = asList(d['items']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _summary(d),
      const SizedBox(height: 4),
      if (items.isEmpty)
        const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('ບໍ່ມີຂໍ້ມູນ')))
      else
        for (final it in items) _item(it, past),
    ]);
  }

  Widget _bottomBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_last == null || _exporting) ? null : _export,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.table_view_outlined),
              label: const Text('ສົ່ງອອກ Excel'),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ງົບປະມານອາໄຫຼ່')),
      bottomNavigationBar: _bottomBar(),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _filters(),
        const SizedBox(height: 12),
        FutureBuilder<dynamic>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text('${snap.error}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 8),
                  FilledButton(
                      onPressed: _run, child: const Text('ລອງໃໝ່')),
                ]),
              );
            }
            var d = snap.data;
            if (d is Map && d['data'] is Map) d = d['data'];
            if (d is! Map) return const SizedBox();
            return _result(Map<String, dynamic>.from(d));
          },
        ),
      ]),
    );
  }
}
