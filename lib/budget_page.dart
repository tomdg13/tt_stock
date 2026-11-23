// Budget: bought and used per fiscal year, stock now, need until a target year, amount to buy.
// Server: GET /stock/budget?fm=10&toYear=2028&pct=0&branchId=
// Saved budgets: POST /stock/budget-plans, PUT /stock/budget-plans/:id
import 'image_search.dart' show SearchTools;
import 'plan_product_pick.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'budget_excel.dart';
import 'product_images.dart' show productImageUrl;
import 'widgets.dart';
import 'crud.dart' show openEdit;
import 'specs.dart' show crudSpec;
import 'plan_excel.dart';
import 'plan_checked.dart';
import 'plan_bar.dart';
import 'plan_pdf_menu.dart';

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
  bool _asTable = true; // true = table, false = old cards
  int _yearFrom = 0, _yearTo = 0, _pctShown = 0;
  int _yearsFull = 1;
  int _sortCol = -1;
  bool _sortAsc = true;
  final _pct = TextEditingController(text: '0');
  int _fm = 10;
  int _toYear = DateTime.now().year + 2;
  dynamic _branchId;
  List<Map<String, dynamic>> _branches = [];
  Future<dynamic>? _f;
  Map<String, dynamic>? _last;
  bool _exporting = false;
  Map<String, Map<String, dynamic>> _prodById = {};
  Map<String, Map<String, dynamic>> _prodByName = {};
  Map<String, String> _prodNameById = {};
  final Map<String, num> _actualBuy = {};
  String _fBrand = '';
  String _fPart = '';
  final _bq = TextEditingController();
  String _bs = '';
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
    _loadProducts();
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
    final res = await Navigator.of(context).push<Set<int>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PoPickPage(pos: _pos, initial: _poIds),
      ),
    );
    if (res != null) {
      _poIds = res;
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
    _bq.dispose();
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
      await exportBudgetXlsx(d, extra: _extraCols, actual: _actualOf,
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

  Object? _itemSortKey(Map<String, dynamic> it) {
    switch (_sortCol) {
      case 1:
        return pick(it, ['productName']).toLowerCase();
      case 2:
        return _binOf(it).toLowerCase();
      case 3:
        return _parentOf(it).toLowerCase();
      case 4:
        return _ptOf(it);
      case 5:
        return _branchNameOf();
      case 6:
        return _typeOf(it).toLowerCase();
      case 7:
        return _brandOf(it).toLowerCase();
      case 8:
        return num0(it['stock']);
      case 9:
        return it['counted'] == null ? null : num0(it['counted']);
      case 10:
      return _usedJ(it);
      case 11:
      return _pctShown;
      case 12:
      return _mustBuy(it);
      case 13:
        return pick(it, ['unit']).toLowerCase();
      case 14:
        return _actualOf(it);
    }
    return null;
  }

  void _showItemDetail(
      Map<String, dynamic> it, List<Map<String, dynamic>> past) {
    final bought = (it['bought'] as List?) ?? const [];
    final used = (it['used'] as List?) ?? const [];
    final plan = asList(it['plan']);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(pick(it, ['productName']),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text('ລາຄາຕໍ່ໜ່ວຍ ${_money(num0(it['unitCost']))}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 10),
                _formulaText(it),
                const SizedBox(height: 10),
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
              ]),
        ),
      ),
    );
  }

  // ໃຊ້ = ສະຕັອກ - ນັບຕົວຈິງ (ບໍ່ມີນັບ = 0)
  num _usedJ(Map<String, dynamic> it) =>
      it['counted'] == null ? 0 : num0(it['stock']) - num0(it['counted']);

  // ຕ້ອງຊື້ = J + ROUNDUP(J * % / 100)  (ROUNDUP ຄືກັບ Excel: ປັດອອກຈາກ 0)
  num _mustBuy(Map<String, dynamic> it) {
    final j = _usedJ(it);
    final x = j * _pctShown / 100;
    return j + (x < 0 ? -((-x).ceil()) : x.ceil());
  }

  Future<void> _loadProducts() async {
    try {
      final d = await Api.get('/products?limit=2000');
      final src = d is Map ? (d['items'] ?? d['data'] ?? d['rows']) : d;
      final byId = <String, Map<String, dynamic>>{};
      final byName = <String, Map<String, dynamic>>{};
      final names = <String, String>{};
      for (final m in asList(src)) {
        final id = pick(m, ['id', 'productId']);
        final nm = pick(m, ['name', 'productName']);
        if (id.isNotEmpty) {
          byId[id] = m;
          names[id] = nm;
        }
        if (nm.isNotEmpty) byName[nm.toLowerCase()] = m;
      }
      if (mounted) {
        setState(() {
          _prodById = byId;
          _prodByName = byName;
          _prodNameById = names;
        });
      }
    } catch (_) {}
  }

  Map<String, dynamic> _prodOf(Map<String, dynamic> it) {
    final byId = _prodById[pick(it, ['productId', 'id'])];
    if (byId != null) return byId;
    return _prodByName[pick(it, ['productName']).toLowerCase()] ??
        const <String, dynamic>{};
  }

  String _binOf(Map<String, dynamic> it) {
    final b = pick(_prodOf(it), ['binCodes', 'binCode']);
    return b.isNotEmpty ? b : pick(it, ['binCodes', 'binCode']);
  }

  String _parentOf(Map<String, dynamic> it) =>
      _prodNameById[pick(_prodOf(it), ['parentProductId'])] ?? '';

  String _ptOf(Map<String, dynamic> it) {
    final t = pick(_prodOf(it), ['partType']);
    if (t == 'PARTIAL') return 'ອາໄຫຼ່ຍ່ອຍ';
    if (t == 'FULL') return 'ອາໄຫຼ່ເຕັມ';
    return '';
  }

  String _typeOf(Map<String, dynamic> it) {
    final t = pick(it, ['typeName']);
    return t.isNotEmpty ? t : pick(_prodOf(it), ['typeName']);
  }

  String _brandOf(Map<String, dynamic> it) {
    final b = pick(it, ['brandName']);
    return b.isNotEmpty ? b : pick(_prodOf(it), ['brandName']);
  }

  List<String> _extraCols(Map<String, dynamic> it) => [
        _binOf(it),
        _parentOf(it),
        _ptOf(it),
        _branchNameOf(),
        _typeOf(it),
        _brandOf(it),
      ];

  String _keyOf(Map<String, dynamic> it) {
    final id = pick(it, ['productId', 'id']);
    return id.isNotEmpty ? id : pick(it, ['productName']);
  }

  num _actualOf(Map<String, dynamic> it) {
    final k = _keyOf(it);
    if (_actualBuy.containsKey(k)) return _actualBuy[k]!;
    return num0(it['poTotal']);
  }

  bool get _canEditProd {
    final sp = crudSpec('prod');
    return sp != null && sp.canEdit;
  }

  Future<void> _editProd(Map<String, dynamic> it) async {
    final sp = crudSpec('prod');
    final p = _prodOf(it);
    if (sp == null || p.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ບໍ່ພົບສິນຄ້ານີ້')));
      return;
    }
    final changed = await openEdit(context, sp, {...p});
    if (changed == true) {
      _loadProducts();
      _run();
    }
  }

  Future<void> _askActual(Map<String, dynamic> it) async {
    final k = _keyOf(it);
    final cur = _actualBuy[k];
    final c = TextEditingController(
        text: cur == null ? '' : cur.toStringAsFixed(cur % 1 == 0 ? 0 : 2));
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(pick(it, ['productName'])),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _thumb(pick(it, ['imageUrl']))),
              const SizedBox(height: 12),
              Text('ຕ້ອງຊື້: ${_n(_mustBuy(it))} ${pick(it, ['unit'])}'),
              Text('PO: ${_n(num0(it['poTotal']))}'),
              const SizedBox(height: 8),
              TextField(
                controller: c,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'ຈຳນວນທີ່ຈະຊື້ຕົວຈິງ'),
                onSubmitted: (t) => Navigator.pop(d, t),
              ),
            ]),
        actions: [
          if (cur != null)
            TextButton(
                onPressed: () => Navigator.pop(d, '__clear__'),
                child: const Text('ລຶບ')),
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(d, c.text),
              child: const Text('ຕົກລົງ')),
        ],
      ),
    );
    if (v == null) return;
    if (v == '__clear__') {
      setState(() => _actualBuy.remove(k));
      return;
    }
    final n = num.tryParse(v.trim());
    if (n != null && n >= 0) setState(() => _actualBuy[k] = n);
  }

  void _onBq(String v) => setState(() => _bs = v.trim().toLowerCase());

  Widget _noMatch() {
    final t = _bq.text.trim();
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 24),
      const Icon(Icons.search_off, size: 40),
      const SizedBox(height: 12),
      Text('ບໍ່ພົບ "$t" ໃນງົບ',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('ສິນຄ້ານີ້ອາດຈະບໍ່ເຄີຍຊື້', textAlign: TextAlign.center),
      const SizedBox(height: 16),
      Center(
        child: FilledButton.icon(
          onPressed: _searchAllProducts,
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('ຄົ້ນຫາໃນສິນຄ້າທັງໝົດ'),
        ),
      ),
    ]);
  }

  Future<List<Map<String, dynamic>>?> _fetchPlanItems(
      Map<String, dynamic> p) async {
    final items = <Map<String, dynamic>>[];
    try {
      var d = await Api.get('/stock/buy-plans/${p['id']}');
      if (d is Map && d['data'] is Map) d = d['data'];
      if (d is Map && d['items'] is List) {
        for (final x in (d['items'] as List)) {
          if (x is Map) {
            items.add({
              'key': '${x['itemKey'] ?? x['productId'] ?? x['productName']}',
              'productId': x['productId'],
              'name': x['productName'],
              'unit': x['unit'],
              'brand': x['brand'],
              'bin': x['binCode'],
              'qty': x['qty'],
              'done': '${x['done']}' == '1',
              'buyQty': x['buyQty'],
              'isNew': '${x['isNew']}' == '1',
              'imageUrl': x['imageUrl'] ?? '',
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ເປີດແຜນບໍ່ສຳເລັດ: $e')));
      }
      return null;
    }
    return items;
  }

  Future<void> _searchAllProducts() async {
    final picked = await Navigator.of(context)
        .push<List<Map<String, dynamic>>>(MaterialPageRoute(
            builder: (_) => PlanProductPickPage(
                existing: const <String>{}, initialQuery: _bq.text.trim())));
    if (picked == null || picked.isEmpty || !mounted) return;
    final plans = await _loadBuyPlans();
    if (!mounted) return;
    if (plans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ຍັງບໍ່ມີແຜນຊື້ ກົດ ແຜນຊື້ ເພື່ອສ້າງແຜນກ່ອນ')));
      return;
    }
    final plan = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(
              title: Text('ເພີ່ມເຂົ້າແຜນໃດ',
                  style: TextStyle(fontWeight: FontWeight.w700))),
          for (final p in plans)
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: Text('${p['name']}'),
              subtitle: Text(_planSub(p)),
              onTap: () => Navigator.pop(c, p),
            ),
        ]),
      ),
    );
    if (plan == null) return;
    final items = await _fetchPlanItems(plan);
    if (items == null) return;
    final have = <String>{for (final x in items) '${x['key']}'};
    var added = 0;
    for (final x in picked) {
      if (have.add('${x['key']}')) {
        items.add(x);
        added++;
      }
    }
    await _savePlanItems(plan, items);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'ເພີ່ມ $added ລາຍການເຂົ້າ ${plan['name']} • ເປີດແຜນ ແລ້ວກົດ ລາຍການ ເພື່ອໃສ່ຈຳນວນ')));
    }
  }

  bool _matchBudgetQ(Map<String, dynamic> it) {
    if (_bs.isEmpty) return true;
    final f = <String>[
      pick(it, ['productName']),
      pick(it, ['barcodes']),
      pick(it, ['models']),
      _brandOf(it),
      _binOf(it),
      ..._extraCols(it),
    ];
    return f.any((s) => s.toLowerCase().contains(_bs));
  }

  Widget _filterBar(Set<String> brands, int shown, int total) {
    final bl = brands.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: _bq,
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'ຄົ້ນຫາອາໄຫຼ່',
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                SearchTools(onResult: (v) {
                  _bq.text = v;
                  _onBq(v);
                }),
                IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _bq.clear();
                      _onBq('');
                    }),
              ])),
          onChanged: _onBq,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final p in const ['', 'ອາໄຫຼ່ເຕັມ', 'ອາໄຫຼ່ຍ່ອຍ'])
              ChoiceChip(
                label: Text(p.isEmpty ? 'ທັງໝົດ' : p),
                selected: _fPart == p,
                onSelected: (_) => setState(() => _fPart = p),
              ),
            DropdownButton<String>(
              value: bl.contains(_fBrand) ? _fBrand : '',
              items: [
                const DropdownMenuItem(
                    value: '', child: Text('Brand: ທັງໝົດ')),
                for (final b in bl)
                  DropdownMenuItem(value: b, child: Text(b)),
              ],
              onChanged: (v) => setState(() => _fBrand = v ?? ''),
            ),
            Text('$shown/$total'),
          ],
        ),
      ),
    ]);
  }

  Widget _itemsTable(
      List<Map<String, dynamic>> items, List<Map<String, dynamic>> past) {
    final cs = Theme.of(context).colorScheme;
    const w = <double>[56, 260, 90, 140, 100, 100, 110, 100, 80, 90, 110, 110, 100, 60, 110, 110];
    final heads = <String>[
      'ຮູບ',
      'ລາຍການ',
      'ທີ່ເກັບ',
      'ອາໄຫຼ່ຫຼັກ',
      'ປະເພດອາໄຫຼ່',
      'Branch',
      'ປະເພດສິນຄ້າ',
      'brand',
      'ສະຕັອກ',
      'ນັບຕົວຈິງ',
        'ໃຊ້',
        '% ຕ້ອງຊື້ ເພີມ',
        'ຕ້ອງຊື້',
      'ໜ່ວຍ',
      'ຊື້ຕົວຈິງ (PO)', 'ຈັດການ'
    ];
    const right = <int>{8, 9, 10, 11, 12, 14};
    final total = w.fold<double>(0, (a, b) => a + b) + 16;
    Widget cell(int i, Widget child) => SizedBox(
        width: w[i],
        child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Align(
                alignment: right.contains(i)
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: child)));
    const headStyle = TextStyle(fontWeight: FontWeight.w700, fontSize: 13);
    final sorted = [...items];
    if (_sortCol > 0) {
      sorted.sort((a, b) {
        final ka = _itemSortKey(a);
        final kb = _itemSortKey(b);
        if (ka == null && kb == null) return 0;
        if (ka == null) return 1; // empty values always last
        if (kb == null) return -1;
        final c = (ka is num && kb is num)
            ? ka.compareTo(kb)
            : '$ka'.compareTo('$kb');
        return _sortAsc ? c : -c;
      });
    }
    return LayoutBuilder(builder: (ctx, cons) {
      if (cons.maxHeight < 120) return const SizedBox.shrink();
      return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: total,
        child: Column(children: [
          Container(
            height: 40,
            color: cs.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              for (final i in const [2, 3, 4, 5, 6, 7, 0, 1, 8, 9, 10, 11, 12, 13, 14, 15])
                (i == 0 || i == 15)
                    ? cell(i, Text(heads[i], style: headStyle))
                    : InkWell(
                        onTap: () => setState(() {
                          _sortAsc = _sortCol == i ? !_sortAsc : true;
                          _sortCol = i;
                        }),
                        child: SizedBox(
                          width: w[i],
                          height: 40,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Row(
                                mainAxisAlignment: right.contains(i)
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                children: [
                                  Flexible(
                                      child: Text(heads[i],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: headStyle)),
                                  if (_sortCol == i)
                                    Icon(
                                        _sortAsc
                                            ? Icons.arrow_upward
                                            : Icons.arrow_downward,
                                        size: 14),
                                ]),
                          ),
                        ),
                      ),
            ]),
          ),
          Expanded(
              child: ListView(children: [
                for (final it in sorted)
            InkWell(
              onTap: () => _showItemDetail(it, past),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: Theme.of(context).dividerColor))),
                child: Row(children: [
                    cell(2, Text(_binOf(it))),
                    cell(3, Text(_parentOf(it))),
                    cell(4, Text(_ptOf(it))),
                    cell(5, Text(_branchNameOf())),
                    cell(6, Text(_typeOf(it))),
                    cell(7, Text(_brandOf(it))),
                  cell(0, _thumb(pick(it, ['imageUrl']))),
                  cell(
                      1,
                      Text(pick(it, ['productName']),
                          maxLines: 2, overflow: TextOverflow.ellipsis)),
                  cell(8, Text(_n(num0(it['stock'])))),
                  cell(
                      9,
                      Text(it['counted'] == null
                          ? '-'
                          : _n(num0(it['counted'])))),
                    cell(10, Text(_n(_usedJ(it)))),
                    cell(11, Text('$_pctShown%')),
                    cell(
                        12,
                        Text(_n(_mustBuy(it)),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700))),
                  cell(13, Text(pick(it, ['unit']))),
                  cell(
                      14,
                      Text(_actualOf(it) > 0
                          ? _n(_actualOf(it))
                          : '-')),
                  cell(
                      15,
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton.filledTonal(
                          tooltip: 'ໃສ່ຈຳນວນຊື້ຕົວຈິງ',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _askActual(it),
                          icon: const Icon(Icons.shopping_cart_checkout,
                              size: 20),
                        ),
                        if (_canEditProd) ...[
                          const SizedBox(width: 6),
                          IconButton.outlined(
                            tooltip: 'ແກ້ໄຂສິນຄ້າ',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _editProd(it),
                            icon: const Icon(Icons.edit_outlined, size: 20),
                          ),
                        ],
                      ])),
                ]),
              ),
            ),
              ]),
            ),
        ]),
      ),
    );
    });
  }

  Widget _yearsInfo(Map<String, dynamic> d) {
    final a = num0(d['yearFrom']).toInt();
    final b = num0(d['yearTo']).toInt();
    final n = num0(d['yearsFull']).toInt();
    final pct = num0(d['pct']).toInt();
    final txt = a > 0
        ? 'PO ປີ $a–$b = $n ປີ  •  ໃຊ້/ປີ = ໃຊ້ທັງໝົດ ÷ $n ປີ  •  ໃຊ້/1 ປີ +$pct% = ໃຊ້/ປີ × (1 + $pct%)  •  ຕ້ອງຊື້ 1 ປີ = ໃຊ້/1 ປີ +$pct% − (ສະຕັອກ + PO ຄ້າງຮັບ)'
        : 'ບໍ່ໄດ້ເລືອກ PO: ໃຊ້/ປີ = ໃຊ້ 12 ເດືອນຜ່ານມາ  •  ໃຊ້/1 ປີ +$pct% = ໃຊ້/ປີ × (1 + $pct%)  •  ຕ້ອງຊື້ 1 ປີ = ໃຊ້/1 ປີ +$pct% − (ສະຕັອກ + PO ຄ້າງຮັບ)';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Text(txt, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _formulaText(Map<String, dynamic> it) {
    final rate = num0(it['ratePerYear']);
    final used = num0(it['usedTotal']);
    final need1 = num0(it['need1']);
    final buy1 = num0(it['buy1']);
    final have = (it['counted'] != null
            ? num0(it['counted'])
            : num0(it['stock'])) +
        num0(it['ordered']);
    final line1 = _yearFrom > 0
        ? 'ໃຊ້ ${_n(used)} ÷ $_yearsFull ປີ ($_yearFrom–$_yearTo) = ${_n(rate)}/ປີ'
        : 'ໃຊ້ 12 ເດືອນຜ່ານມາ ${_n(used)} = ${_n(rate)}/ປີ';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(line1, style: const TextStyle(fontSize: 12)),
      Text('ໃຊ້/1 ປີ +$_pctShown% = ${_n(need1)}',
          style: const TextStyle(fontSize: 12)),
      Text('ຕ້ອງຊື້ 1 ປີ = ${_n(need1)} − ${_n(have)} (ສະຕັອກ + PO) = ${_n(buy1)}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _result(Map<String, dynamic> d) {
    final past = asList(d['pastYears']);
    _yearFrom = num0(d['yearFrom']).toInt();
    _yearTo = num0(d['yearTo']).toInt();
    _pctShown = num0(d['pct']).toInt();
    _yearsFull = num0(d['yearsFull']).toInt();
    final items = asList(d['items']);
    final brands = <String>{for (final it in items) _brandOf(it)}..remove('');
    final shown = [
      for (final it in items)
        if ((_fBrand.isEmpty || _brandOf(it) == _fBrand) &&
            (_fPart.isEmpty || _ptOf(it) == _fPart) && _matchBudgetQ(it))
          it
    ];
    _shownRows = shown;
    return NestedScrollView(
      headerSliverBuilder: (ctx, inner) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _filters(),
                  const SizedBox(height: 12),
                  _summary(d),
                  _yearsInfo(d),
                  const SizedBox(height: 4),
                  if (items.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Row(children: [
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                              visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: true, label: Text('ຕາຕະລາງ')),
                            ButtonSegment(value: false, label: Text('ບັດ')),
                          ],
                          selected: {_asTable},
                          onSelectionChanged: (v) =>
                              setState(() => _asTable = v.first),
                        ),
                      ]),
                    ),
                    _filterBar(brands, shown.length, items.length),
                  ],
                ]),
          ),
        ),
      ],
      body: items.isEmpty
          ? const Center(child: Text('ບໍ່ມີຂໍ້ມູນ'))
          : (shown.isEmpty && _bs.isNotEmpty ? _noMatch() : _asTable
              ? _itemsTable(shown, past)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  for (final it in shown) _item(it, past),
                ])),
    );
  }

  List<Map<String, dynamic>> _shownRows = [];


  num _planQty(Map<String, dynamic> it) {
    final k = _keyOf(it);
    if (_actualBuy.containsKey(k)) return _actualBuy[k]!;
    final m = _mustBuy(it);
    return m > 0 ? m : 0;
  }



  String _planSub(Map<String, dynamic> p) {
    final n = num.tryParse('${p['itemCount']}') ?? 0;
    final dn = num.tryParse('${p['doneCount']}') ?? 0;
    final t = num.tryParse('${p['totalQty']}') ?? 0;
    final d = '${p['createdAt']}';
    final day = d.length >= 10 ? d.substring(0, 10) : d;
    final f = '${p['filter'] ?? ''}';
    final extra = f.isEmpty ? '' : ' • $f';
    return '${_n(dn)}/${_n(n)} ລາຍການ • ລວມ ${_n(t)} • $day$extra';
  }

  Future<List<Map<String, dynamic>>> _loadBuyPlans() async {
    if (_planId == null) return [];
    try {
      var d = await Api.get('/stock/budget-plans/$_planId/buy-plans');
      if (d is Map && d['data'] != null) d = d['data'];
      final out = <Map<String, dynamic>>[];
      if (d is List) {
        for (final x in d) {
          if (x is Map) {
            final m = Map<String, dynamic>.from(x);
            m['filter'] = m['filterText'];
            out.add(m);
          }
        }
      }
      return out;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ໂຫຼດແຜນຊື້ບໍ່ສຳເລັດ: $e')));
      }
    }
    return [];
  }

  Future<void> _savePlanItems(
      Map<String, dynamic> plan, List<Map<String, dynamic>> items) async {
    try {
      await Api.put('/stock/buy-plans/${plan['id']}/items', {
        'items': [
          for (final x in items)
            {
              'key': '${x['key']}',
              'productId': x['productId'] ?? int.tryParse('${x['key']}'),
              'name': x['name'],
              'unit': x['unit'],
              'brand': x['brand'],
              'bin': x['bin'],
              'qty': x['qty'],
              'done': x['done'] == true,
              'buyQty': x['buyQty'],
              'isNew': x['isNew'] == true,
              'imageUrl': x['imageUrl'],
            }
        ],
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ບັນທຶກແຜນບໍ່ສຳເລັດ: $e')));
      }
    }
  }



  Future<void> _createBuyPlan() async {
    if (_planId == null) {
      await _save();
      if (_planId == null) return;
    }
    final rows = <Map<String, dynamic>>[];
    for (final it in _shownRows) {
      final q = _planQty(it);
      if (q > 0) {
        rows.add({
          'key': _keyOf(it),
          'name': pick(it, ['productName']),
          'imageUrl': pick(it, ['imageUrl']),
          'unit': pick(it, ['unit']),
          'brand': _brandOf(it),
          'bin': _binOf(it),
          'qty': q,
        });
      }
    }
    if (!mounted) return;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ບໍ່ມີລາຍການທີ່ຕ້ອງຊື້')));
      return;
    }
    final old = await _loadBuyPlans();
    final base = _planName.isEmpty ? 'ແຜນ' : _planName;
    final nameC = TextEditingController(text: '$base - ແຜນຊື້ ${old.length + 1}');
    final noteC = TextEditingController();
    final total = rows.fold<num>(0, (a, r) => a + (r['qty'] as num));
    final flt = [if (_fBrand.isNotEmpty) _fBrand, if (_fPart.isNotEmpty) _fPart]
        .join(' • ');
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ສ້າງແຜນຊື້'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${rows.length} ລາຍການ • ລວມ ${_n(total)}'),
              if (flt.isNotEmpty) Text(flt),
              const SizedBox(height: 8),
              TextField(
                  controller: nameC,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'ຊື່ແຜນ')),
              const SizedBox(height: 8),
              TextField(
                  controller: noteC,
                  decoration: const InputDecoration(labelText: 'ໝາຍເຫດ')),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('ບັນທຶກແຜນ')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameC.text.trim();
    if (name.isEmpty) return;
    try {
      await Api.post('/stock/budget-plans/$_planId/buy-plans', {
        'name': name,
        'note': noteC.text.trim(),
        'filter': flt,
        'items': [
          for (final r in rows)
            {
              'key': '${r['key']}',
              'productId': int.tryParse('${r['key']}'),
              'name': r['name'],
              'unit': r['unit'],
              'brand': r['brand'],
              'bin': r['bin'],
              'qty': r['qty'],
              'done': false,
            }
        ],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ສ້າງແຜນແລ້ວ: $name')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ສ້າງແຜນບໍ່ສຳເລັດ: $e')));
    }
  }

  Future<void> _showBuyPlan(Map<String, dynamic> p) async {
    final items = <Map<String, dynamic>>[];
    try {
      var d = await Api.get('/stock/buy-plans/${p['id']}');
      if (d is Map && d['data'] is Map) d = d['data'];
      if (d is Map && d['items'] is List) {
        for (final x in (d['items'] as List)) {
          if (x is Map) {
            items.add({
              'key': '${x['itemKey'] ?? x['productId'] ?? x['productName']}',
              'productId': x['productId'],
              'name': x['productName'],
              'unit': x['unit'],
              'brand': x['brand'],
              'bin': x['binCode'],
              'qty': x['qty'],
              'done': '${x['done']}' == '1',
              'buyQty': x['buyQty'],
              'isNew': '${x['isNew']}' == '1',
              'imageUrl': x['imageUrl'] ?? '',
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ເປີດແຜນບໍ່ສຳເລັດ: $e')));
      }
      return;
    }
    if (!mounted) return;
    final img = <String, String>{};
    for (final b in asList(_last?['items'])) {
      final u = pick(b, ['imageUrl']);
      if (u.isNotEmpty) img[_keyOf(b)] = u;
    }
    for (final x in items) {
      x['imageUrl'] = img['${x['key']}'] ?? x['imageUrl'] ?? '';
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (c) => _PlanItemsPage(host: this, plan: p, items: items),
      ),
    );
  }

  Widget _planRow(Map<String, dynamic> x) {
    final q = num.tryParse('${x['qty']}') ?? 0;
    final unit = '${x['unit'] ?? ''}';
    final sub = ['${x['brand'] ?? ''}', '${x['bin'] ?? ''}']
        .where((e) => e.isNotEmpty)
        .join(' • ');
    return ListTile(
      leading: _thumb('${x['imageUrl'] ?? ''}'),
      title: Text('${x['name']}'),
      subtitle: sub.isEmpty ? null : Text(sub),
      trailing: Text('${_n(q)} $unit'),
    );
  }

  Future<void> _openBuyPlans() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => _BuyPlansPage(host: this)),
    );
  }

  Widget _navItem(IconData icon, String label, VoidCallback? onTap,
      {bool loading = false}) {
    final cs = Theme.of(context).colorScheme;
    final c = onTap == null ? cs.outline : cs.primary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, color: c),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c)),
          ]),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final cs = Theme.of(context).colorScheme;
    final busy = _last == null || _exporting || _saving;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          _navItem(Icons.save_outlined, 'ບັນທຶກ', busy ? null : _save,
              loading: _saving),
          _navItem(Icons.list_alt, 'ແຜນຊື້', _openBuyPlans),
          _navItem(Icons.table_view_outlined, 'Excel', busy ? null : _export,
              loading: _exporting),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text(_planName.isEmpty ? 'ງົບປະມານອາໄຫຼ່' : _planName)),
      bottomNavigationBar: _bottomBar(),
      body: FutureBuilder<dynamic>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return ListView(padding: const EdgeInsets.all(16), children: [
              _filters(),
              const SizedBox(height: 12),
              const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator())),
            ]);
          }
          if (snap.hasError) {
            return ListView(padding: const EdgeInsets.all(16), children: [
              _filters(),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text('${snap.error}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _run, child: const Text('ລອງໃໝ່')),
                ]),
              ),
            ]);
          }
          var d = snap.data;
          if (d is Map && d['data'] is Map) d = d['data'];
          if (d is! Map) {
            return ListView(
                padding: const EdgeInsets.all(16), children: [_filters()]);
          }
          return _result(Map<String, dynamic>.from(d));
        },
      ),
    );
  }
}

class _PoPickPage extends StatefulWidget {
  final List<Map<String, dynamic>> pos;
  final Set<int> initial;
  const _PoPickPage({required this.pos, required this.initial});
  @override
  State<_PoPickPage> createState() => _PoPickPageState();
}

class _PoPickPageState extends State<_PoPickPage> {
  late Set<int> sel = {...widget.initial};

  int _id(Map<String, dynamic> p) => int.tryParse('${p['id']}') ?? 0;

  String _year(Map<String, dynamic> p) {
    final m = RegExp(r'20[1-3]\d')
        .firstMatch('${pick(p, ['title'])} ${pick(p, ['poNo'])}');
    if (m != null) return m.group(0)!;
    for (final k in const ['poDate', 'orderDate', 'createdAt', 'date']) {
      final v = pick(p, [k]);
      if (RegExp(r'^20[1-3]\d').hasMatch(v)) return v.substring(0, 4);
    }
    return 'ອື່ນໆ';
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _groups() {
    final g = <String, List<Map<String, dynamic>>>{};
    for (final p in widget.pos) {
      g.putIfAbsent(_year(p), () => []).add(p);
    }
    final keys = g.keys.toList()
      ..sort((a, b) {
        if (a == 'ອື່ນໆ') return 1;
        if (b == 'ອື່ນໆ') return -1;
        return b.compareTo(a);
      });
    return [for (final k in keys) MapEntry(k, g[k]!)];
  }

  bool? _state(List<Map<String, dynamic>> list) {
    final n = list.where((p) => sel.contains(_id(p))).length;
    if (n == 0) return false;
    if (n == list.length) return true;
    return null;
  }

  void _setAll(List<Map<String, dynamic>> list, bool on) => setState(() {
        for (final p in list) {
          if (on) {
            sel.add(_id(p));
          } else {
            sel.remove(_id(p));
          }
        }
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = _groups();
    return Scaffold(
      appBar: AppBar(
        title: Text('ເລືອກ PO (${sel.length}/${widget.pos.length})'),
        actions: [
          TextButton(
              onPressed: () => setState(() => sel.clear()),
              child: const Text('ລ້າງ')),
        ],
      ),
      body: widget.pos.isEmpty
          ? const Center(child: Text('ບໍ່ມີ PO'))
          : ListView(children: [
              CheckboxListTile(
                tristate: true,
                value: _state(widget.pos),
                title: const Text('ເລືອກທັງໝົດ',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onChanged: (_) =>
                    _setAll(widget.pos, _state(widget.pos) != true),
              ),
              const Divider(height: 1),
              for (final g in groups) ...[
                Material(
                  color: cs.surfaceContainerHighest,
                  child: CheckboxListTile(
                    tristate: true,
                    value: _state(g.value),
                    title: Text(
                        'ປີ ${g.key}  (${g.value.where((p) => sel.contains(_id(p))).length}/${g.value.length})',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    onChanged: (_) => _setAll(g.value, _state(g.value) != true),
                  ),
                ),
                for (final p in g.value)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 32, right: 16),
                    value: sel.contains(_id(p)),
                    title: Text(pick(p, ['poNo'])),
                    subtitle: Text([pick(p, ['vendor']), pick(p, ['title'])]
                        .where((e) => e.isNotEmpty)
                        .join(' • ')),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        sel.add(_id(p));
                      } else {
                        sel.remove(_id(p));
                      }
                    }),
                  ),
              ],
            ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('ຍົກເລີກ'))),
            const SizedBox(width: 12),
            Expanded(
                child: FilledButton(
                    onPressed: () => Navigator.pop(context, sel),
                    child: Text('ຕົກລົງ (${sel.length})'))),
          ]),
        ),
      ),
    );
  }
}

class _PlanItemsPage extends StatefulWidget {
  final _BudgetPageState host;
  final Map<String, dynamic> plan;
  final List<Map<String, dynamic>> items;
  const _PlanItemsPage(
      {required this.host, required this.plan, required this.items});
  @override
  State<_PlanItemsPage> createState() => _PlanItemsPageState();
}

class _PlanItemsPageState extends State<_PlanItemsPage> {
  final _qc = TextEditingController();
  String _q = '';
  int _filter = 0;

  @override
  void dispose() {
    _qc.dispose();
    super.dispose();
  }

  void _onQ(String v) => setState(() => _q = v.trim().toLowerCase());

  Future<void> _persistPlan() async {
    await widget.host._savePlanItems(widget.plan, widget.items);
  }

  Widget _planBar() {
    return PlanBar(
      onSave: _persistPlan,
      onList: _openChecked,
      onExport: () => exportPlanXlsx(widget.plan, widget.items),
      onPdf: () => pickPlanPdf(context, widget.plan, widget.items),
    );
  }

  Future<void> _openChecked() async {
    final budget = <String, Map<String, dynamic>>{};
    for (final b in asList(widget.host._last?['items'])) {
      budget[widget.host._keyOf(b)] = b;
    }
    for (final x in widget.items) {
      final b = budget['${x['key']}'];
      if (b is Map<String, dynamic>) {
        x['stock'] = num0(b['stock']);
        x['counted'] = b['counted'] == null ? null : num0(b['counted']); x['used'] = b['counted'] == null ? 0 : num0(b['stock']) - num0(b['counted']);
        x['must'] = widget.host._mustBuy(b);
        x['po'] = widget.host._actualOf(b);
      }
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => PlanCheckedPage(
            plan: widget.plan,
            items: widget.items,
            onExport: () => exportPlanXlsx(widget.plan, widget.items),
            onSave: () async {
              await widget.host._savePlanItems(widget.plan, widget.items);
            })));
    if (mounted) setState(() {});
  }







  Future<void> _toggle(Map<String, dynamic> x, bool on) async {
    setState(() => x['done'] = on);
    await widget.host._savePlanItems(widget.plan, widget.items);
  }

  Future<void> _toggleGroup(List<Map<String, dynamic>> g, bool on) async {
    setState(() {
      for (final x in g) {
        x['done'] = on;
      }
    });
    await widget.host._savePlanItems(widget.plan, widget.items);
  }

  Widget _brandHeader(String b, List<Map<String, dynamic>> g) {
    final n = g.where((x) => x['done'] == true).length;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _toggleGroup(g, n != g.length),
      child: Container(
        color: cs.surfaceContainerHighest,
        child: Row(children: [
          Checkbox(
            tristate: true,
            value: n == 0 ? false : (n == g.length ? true : null),
            onChanged: (_) => _toggleGroup(g, n != g.length),
          ),
          Expanded(
              child: Text(b,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('$n / ${g.length}')),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = '${widget.plan['note'] ?? ''}';
    final doneCount = widget.items.where((x) => x['done'] == true).length;
    final shown = widget.items.where((x) {
      final d = x['done'] == true;
      if (_filter == 1 && d) return false;
      if (_filter == 2 && !d) return false;
      if (_q.isEmpty) return true;
      return ['name', 'brand', 'bin']
          .any((k) => '${x[k] ?? ''}'.toLowerCase().contains(_q));
    }).toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final x in shown) {
      final bn = '${x['brand'] ?? ''}';
      groups.putIfAbsent(bn.isEmpty ? '(ບໍ່ມີ Brand)' : bn, () => []).add(x);
    }
    final brands = groups.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text('${widget.plan['name']}')),
      bottomNavigationBar: _planBar(),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _qc,
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: 'ຄົ້ນຫາອາໄຫຼ່',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  SearchTools(onResult: (v) {
                    _qc.text = v;
                    _onQ(v);
                  }),
                  IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _qc.clear();
                        _onQ('');
                      }),
                ])),
            onChanged: _onQ,
          ),
        ),
        if (note.isNotEmpty)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                  alignment: Alignment.centerLeft, child: Text(note))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final f in const [
                    [0, 'ທັງໝົດ'],
                    [1, 'ຍັງບໍ່ຊື້'],
                    [2, 'ຊື້ແລ້ວ'],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('${f[1]}'),
                        selected: _filter == f[0],
                        onSelected: (_) =>
                            setState(() => _filter = f[0] as int),
                      ),
                    ),
                ]),
              ),
            ),
            Text('$doneCount / ${widget.items.length}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('ບໍ່ມີຂໍ້ມູນ'))
              : ListView(children: [
                  for (final bn in brands) ...[
                    _brandHeader(bn, groups[bn]!),
                    for (final x in groups[bn]!)
                      Row(children: [
                        Checkbox(
                            value: x['done'] == true,
                            onChanged: (v) => _toggle(x, v == true)),
                        Expanded(
                            child: Opacity(
                                opacity: x['done'] == true ? 0.5 : 1,
                                child: widget.host._planRow(x))),
                      ]),
                  ],
                ]),
        ),
      ]),
    );
  }
}

class _BuyPlansPage extends StatefulWidget {
  final _BudgetPageState host;
  const _BuyPlansPage({required this.host});
  @override
  State<_BuyPlansPage> createState() => _BuyPlansPageState();
}

class _BuyPlansPageState extends State<_BuyPlansPage> {
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = await widget.host._loadBuyPlans();
    if (!mounted) return;
    setState(() {
      _plans = l;
      _loading = false;
    });
  }

  Future<void> _create() async {
    await widget.host._createBuyPlan();
    await _reload();
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ລຶບແຜນນີ້?'),
        content: Text('${p['name']}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('ລຶບ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete('/stock/buy-plans/${p['id']}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ລຶບບໍ່ສຳເລັດ: $e')));
      }
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.host;
    final cs = Theme.of(context).colorScheme;
    final name = h._planName;
    return Scaffold(
      appBar: AppBar(title: Text(name.isEmpty ? 'ແຜນຊື້' : 'ແຜນຊື້ - $name')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Container(
                width: double.infinity,
                color: cs.surfaceContainerHighest,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('ແຜນຊື້ ${_plans.length} ແຜນ',
                    style: const TextStyle(fontSize: 12)),
              ),
              Expanded(
                child: _plans.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(32),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.list_alt, size: 48),
                                SizedBox(height: 12),
                                Text('ຍັງບໍ່ມີແຜນຊື້'),
                                SizedBox(height: 4),
                                Text('ກົດ ສ້າງແຜນຊື້ ດ້ານລຸ່ມ'),
                              ]),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _plans.length,
                        separatorBuilder: (c, i) => const Divider(height: 1),
                        itemBuilder: (c, i) {
                          final p = _plans[i];
                          return ListTile(
                            title: Text('${p['name']}'),
                            subtitle: Text(h._planSub(p)),
                            onTap: () async {
                              await h._showBuyPlan(p);
                              await _reload();
                            },
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(p),
                            ),
                          );
                        },
                      ),
              ),
            ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.playlist_add),
            label: const Text('ສ້າງແຜນຊື້'),
          ),
        ),
      ),
    );
  }
}
