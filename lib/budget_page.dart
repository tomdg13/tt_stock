// Budget: bought and used per fiscal year, stock now, need until a target year, amount to buy.
// Server: GET /stock/budget?fm=10&toYear=2028&pct=0&branchId=
// Saved budgets: POST /stock/budget-plans, PUT /stock/budget-plans/:id
import 'dart:async';
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
  // plan == null -> new budget. plan != null -> open a saved budget.
  final Map<String, dynamic>? plan;
  const BudgetPage({super.key, this.plan});
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
  bool _saving = false;
  Timer? _deb;
  Set<int> _poIds = {};
  Set<int> _auditIds = {};
  List<Map<String, dynamic>> _pos = [];
  List<Map<String, dynamic>> _audits = [];
  dynamic _planId;
  String _planName = '';

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    if (p != null) {
      _planId = p['id'];
      _planName = '${p['name'] ?? ''}';
      _fm = int.tryParse('${p['fm']}') ?? 10;
      _toYear = int.tryParse('${p['toYear']}') ?? _toYear;
      _pct.text = '${int.tryParse('${p['pct']}') ?? 0}';
      _poIds = {
        for (final x in '${p['poIds'] ?? ''}'.split(','))
          if (int.tryParse(x.trim()) != null) int.parse(x.trim())
      };
      _auditIds = {
        for (final x in '${p['auditIds'] ?? ''}'.split(','))
          if (int.tryParse(x.trim()) != null) int.parse(x.trim())
      };
    }
    _loadPos();
    _loadAudits();
    final wantBranch = p?['branchId'];
    final hasBranch = wantBranch != null && '$wantBranch'.isNotEmpty;
    loadBranches().then((b) {
      if (!mounted) return;
      setState(() {
        _branches = b;
        if (hasBranch) {
          for (final x in b) {
            if ('${x['id']}' == '$wantBranch') _branchId = x['id'];
          }
        }
      });
      if (hasBranch) _run();
    }).catchError((_) {
      if (hasBranch && mounted) _run();
    });
    if (!hasBranch) _run();
  }

  String _branchNameOf() {
    if (_branchId == null) return 'ທຸກສາຂາ';
    for (final b in _branches) {
      if ('${b['id']}' == '$_branchId') return pick(b, ['name']);
    }
    return '${widget.plan?['branchName'] ?? ''}';
  }

  String _settingsLine() =>
      '${_branchNameOf()} • ${_fm == 1 ? 'ມັງກອນ - ທັນວາ' : 'ຕຸລາ - ກັນຍາ'} • ຮອດ $_toYear';

  int _poId(Map<String, dynamic> p) => int.tryParse('${p['id']}') ?? 0;

  Future<void> _loadPos() async {
    try {
      var d = await Api.get('/purchase-orders');
      if (d is Map && d['data'] != null) d = d['data'];
      if (d is List && mounted) {
        setState(() => _pos = [
              for (final x in d)
                if (x is Map) Map<String, dynamic>.from(x)
            ]);
      }
    } catch (_) {}
  }

  String _poLabel() => [
        for (final p in _pos)
          if (_poIds.contains(_poId(p))) pick(p, ['poNo'])
      ].join(', ');

  Future<void> _pickPos() async {
    final sel = {..._poIds};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('ເລືອກ PO'),
          content: SizedBox(
            width: double.maxFinite,
            child: _pos.isEmpty
                ? const Text('ບໍ່ມີ PO')
                : ListView(shrinkWrap: true, children: [
                    for (final p in _pos)
                      CheckboxListTile(
                        dense: true,
                        value: sel.contains(_poId(p)),
                        title: Text(pick(p, ['poNo'])),
                        subtitle: Text([
                          pick(p, ['vendor']),
                          pick(p, ['title'])
                        ].where((e) => e.isNotEmpty).join(' • ')),
                        onChanged: (v) => setD(() {
                          if (v == true) {
                            sel.add(_poId(p));
                          } else {
                            sel.remove(_poId(p));
                          }
                        }),
                      ),
                  ]),
          ),
          actions: [
            TextButton(
                onPressed: () => setD(() => sel.clear()),
                child: const Text('ລ້າງ')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ຍົກເລີກ')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ຕົກລົງ')),
          ],
        ),
      ),
    );
    if (ok == true) {
      _poIds = sel;
      _run();
    }
  }

  int _auditId(Map<String, dynamic> a) => int.tryParse('${a['id']}') ?? 0;

  Future<void> _loadAudits() async {
    try {
      var d = await Api.get('/stock/audits?limit=100');
      if (d is Map && d['data'] != null) d = d['data'];
      if (d is List && mounted) {
        setState(() => _audits = [
              for (final x in d)
                if (x is Map) Map<String, dynamic>.from(x)
            ]);
      }
    } catch (_) {}
  }

  String _auditLabel() => [
        for (final a in _audits)
          if (_auditIds.contains(_auditId(a))) pick(a, ['countNo'])
      ].join(', ');

  Future<void> _pickAudits() async {
    final sel = {..._auditIds};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('ເລືອກໃບນັບສະຕັອກ'),
          content: SizedBox(
            width: double.maxFinite,
            child: _audits.isEmpty
                ? const Text('ບໍ່ມີໃບນັບສະຕັອກ')
                : ListView(shrinkWrap: true, children: [
                    for (final a in _audits)
                      CheckboxListTile(
                        dense: true,
                        value: sel.contains(_auditId(a)),
                        title: Text(pick(a, ['countNo'])),
                        subtitle: Text('${pick(a, ['branchName'])} • '
                            '${pick(a, ['createdAt']).split('T').first} • '
                            'ນັບແລ້ວ ${_n(num0(a['counted']))}/${_n(num0(a['total']))}'),
                        onChanged: (v) => setD(() {
                          if (v == true) {
                            sel.add(_auditId(a));
                          } else {
                            sel.remove(_auditId(a));
                          }
                        }),
                      ),
                  ]),
          ),
          actions: [
            TextButton(
                onPressed: () => setD(() => sel.clear()),
                child: const Text('ລ້າງ')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ຍົກເລີກ')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ຕົກລົງ')),
          ],
        ),
      ),
    );
    if (ok == true) {
      _auditIds = sel;
      _run();
    }
  }

  @override
  void dispose() {
    _deb?.cancel();
    _pct.dispose();
    super.dispose();
  }

  void _run() {
    final pct = int.tryParse(_pct.text.trim()) ?? 0;
    final q = [
      'fm=$_fm',
      'toYear=$_toYear',
      'pct=$pct',
      if (_poIds.isNotEmpty) 'poIds=${_poIds.join(',')}',
      if (_auditIds.isNotEmpty) 'auditIds=${_auditIds.join(',')}',
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

  Future<String?> _askName() {
    final c = TextEditingController(text: _planName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ບັນທຶກງົບປະມານ'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'ຊື່ງົບປະມານ'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('ບັນທຶກ')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final d = _last;
    if (d == null) return;
    final name = await _askName();
    if (name == null || name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final body = {
        'name': name,
        'fm': _fm,
        'toYear': _toYear,
        'pct': int.tryParse(_pct.text.trim()) ?? 0,
        'branchId': _branchId,
        'branchName': _branchNameOf(),
        'poIds': _poIds.join(','),
        'auditIds': _auditIds.join(','),
        'totalAmount': num0(d['totalAmount']),
      };
      if (_planId == null) {
        final r = await Api.post('/stock/budget-plans', body);
        var x = r;
        if (x is Map && x['data'] is Map) x = x['data'];
        if (x is Map && x['id'] != null) _planId = x['id'];
      } else {
        await Api.put('/stock/budget-plans/$_planId', body);
      }
      if (mounted) {
        setState(() => _planName = name);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ບັນທຶກແລ້ວ')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ບັນທຶກບໍ່ສຳເລັດ: $e')));
      }
    }
    if (mounted) setState(() => _saving = false);
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
      await exportBudgetXlsx(d,
          branchName: bn, poText: _poLabel(), auditText: _auditLabel());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ສົ່ງອອກບໍ່ສຳເລັດ: $e')));
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
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_settingsLine(), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: _pct,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
                labelText: '% ຕ້ອງຊື້ ເພີມ', suffixText: '%'),
            onChanged: (_) {
              _deb?.cancel();
              _deb = Timer(const Duration(milliseconds: 700), _run);
            },
            onSubmitted: (_) {
              _deb?.cancel();
              _run();
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickPos,
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(
                _poIds.isEmpty
                    ? 'ເລືອກ PO'
                    : 'PO ${_poIds.length} ໃບ: ${_poLabel()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickAudits,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(
                _auditIds.isEmpty
                    ? 'ເລືອກໃບນັບສະຕັອກ'
                    : 'ໃບນັບ ${_auditIds.length} ໃບ: ${_auditLabel()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
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
                child:
                    Text('ລວມ', style: TextStyle(fontWeight: FontWeight.bold))),
            Text(_money(num0(d['totalAmount'])),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          const Text(
              'ລາຄາຕາມ COST_PRICE ຂອງສິນຄ້າ • ຄິດຈາກການໃຊ້ 12 ເດືອນຜ່ານມາ',
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
            'ສະຕັອກ ${_n(num0(it['stock']))} $unit${it['counted'] != null ? ' (ນັບຕົວຈິງ ${_n(num0(it['counted']))})' : ''}  •  ໃຊ້/ປີ ${_n(num0(it['ratePerYear']))}\n'
            'ຕ້ອງຊື້ ${_n(num0(it['totalBuy']))} $unit'
            '${num0(it['ordered']) > 0 ? '  •  PO ຄ້າງຮັບ ${_n(num0(it['ordered']))}' : ''}'),
        trailing: Text(_money(num0(it['totalAmount'])),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Align(
              alignment: Alignment.centerLeft,
              child: Text('ລາຄາຕໍ່ໜ່ວຍ ${_money(num0(it['unitCost']))}',
                  style: const TextStyle(fontSize: 11))),
          const SizedBox(height: 6),
          _table([
            'ປີທີ່ຜ່ານມາ',
            'ຊື້ແລ້ວ',
            'ໃຊ້ໄປ'
          ], [
            for (var i = 0; i < past.length; i++)
              [
                '${past[i]['label']}',
                i < bought.length ? _n(num0(bought[i])) : '0',
                i < used.length ? _n(num0(used[i])) : '0',
              ]
          ]),
          const SizedBox(height: 10),
          _table([
            'ປີຕໍ່ໄປ',
            'ຕ້ອງໃຊ້',
            'ຕ້ອງຊື້',
            'ເງິນ'
          ], [
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
    final busy = _last == null || _exporting || _saving;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('ບັນທຶກ'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : _export,
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.table_view_outlined),
                label: const Text('ສົ່ງອອກ Excel'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text(_planName.isEmpty ? 'ງົບປະມານອາໄຫຼ່' : _planName)),
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
                  FilledButton(onPressed: _run, child: const Text('ລອງໃໝ່')),
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
