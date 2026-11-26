import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';
import 'product_images.dart';
import 'type_image.dart';
import 'branch_price_table.dart';
import 'report_docs_page.dart';
import 'price_report_export.dart';

class ReportAtmPartsPage extends StatefulWidget {
  const ReportAtmPartsPage({super.key});
  @override
  State<ReportAtmPartsPage> createState() => _ReportAtmPartsPageState();
}

class _ReportAtmPartsPageState extends State<ReportAtmPartsPage> {
  List<Map<String, dynamic>> _branches = [];
  dynamic _branchId;
  Set<String> _selPos = <String>{};
  String _ptype = '';
  String _cur = 'USD';
  Map<String, String> _ptById = {};
  Map<String, List<String>> _pinfo = {};
  Map<String, List<String>> _pfull = {};
  Map<String, List<String>> _tinfo = {};
  List<String> _poOpts = [];
  List<dynamic> _pos = [];
  List<dynamic> _items = [];
  List<dynamic> _used = [];
  Map<String, String> _imgById = {};
  Map<String, String> _imgByName = {};
  String _mode = 'month';
  DateTime _anchor = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTimeRange _range = DateTimeRange(
      start: DateTime(DateTime.now().year, DateTime.now().month, 1),
      end: DateTime(DateTime.now().year, DateTime.now().month + 1, 0));
  Future<List<BranchPriceRow>>? _f;

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _v(dynamic v) => double.tryParse('$v') ?? 0;
  String _n(dynamic v) => _v(v).toStringAsFixed(2);
  String _po(dynamic x) =>
      pick(x, ['poNo']).isEmpty ? 'ບໍ່ມີ PO' : pick(x, ['poNo']);

  String get _label => _mode == 'year'
      ? '${_anchor.year}'
      : '${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    loadBranches().then((b) {
      if (mounted) setState(() => _branches = b);
    }).catchError((_) {});
    _loadImgs();
    _loadTerms();
    _load();
  }

  Future<void> _loadTerms() async {
    try {
      final d = await Api.get('/terminals?limit=1000');
      final m = <String, List<String>>{};
      for (final t in asList(d)) {
        m[pick(t, ['barcode'])] = <String>[
          pick(t, ['typeName']),
          pick(t, ['typeImage', 'imageFile']),
        ];
      }
      if (mounted) {
        setState(() {
          _tinfo = m;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadImgs() async {
    try {
      final d = await Api.get('/products?limit=500');
      final byId = <String, String>{};
      final byName = <String, String>{};
      for (final m in asList(d)) {
        _pfull[pick(m, ['id', 'productId'])] = <String>[
          pick(m, ['name', 'productName']),
          pick(m, ['partType']).toUpperCase(),
          pick(m, ['parentProductId']),
          pick(m, ['barcode']),
        ];
        _pinfo[pick(m, ['id', 'productId'])] = <String>[
          pick(m, ['brandName']),
          m['modelNames'] is List ? (m['modelNames'] as List).join('/') : '',
          pick(m, ['typeName']),
          pick(m, ['partNo']),
        ];
        _ptById[pick(m, ['id', 'productId'])] = pick(m, ['partType']).isEmpty ? 'FULL' : pick(m, ['partType']).toUpperCase();
        final img = pick(m, ['imageUrl', 'image', 'photo']);
        if (img.isEmpty) continue;
        final id = pick(m, ['id', 'productId']);
        if (id.isNotEmpty) byId[id] = img;
        final nm = pick(m, ['name', 'productName']).toLowerCase();
        if (nm.isNotEmpty) byName[nm] = img;
      }
      if (mounted) {
        setState(() {
          _imgById = byId;
          _imgByName = byName;
        });
      }
    } catch (_) {}
  }

  void _apply() {
    if (_mode == 'month') {
      _range = DateTimeRange(
          start: DateTime(_anchor.year, _anchor.month, 1),
          end: DateTime(_anchor.year, _anchor.month + 1, 0));
    } else if (_mode == 'year') {
      _range = DateTimeRange(
          start: DateTime(_anchor.year, 1, 1),
          end: DateTime(_anchor.year, 12, 31));
    }
  }

  void _setMode(String m) {
    _mode = m;
    _apply();
    _load();
  }

  void _shift(int dir) {
    if (_mode == 'year') {
      _anchor = DateTime(_anchor.year + dir, 1, 1);
    } else {
      _anchor = DateTime(_anchor.year, _anchor.month + dir, 1);
    }
    _apply();
    _load();
  }

  Future<void> _jump() async {
    final r = await showDatePicker(
        context: context,
        initialDate: _anchor,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDatePickerMode:
            _mode == 'year' ? DatePickerMode.year : DatePickerMode.day);
    if (r == null) return;
    _anchor = DateTime(r.year, r.month, 1);
    _apply();
    _load();
  }

  String _url() =>
      '/repair/price-report-branch?from=${_d(_range.start)}&to=${_d(_range.end)}${_branchId == null ? '' : '&branchId=$_branchId'}';

  Future<List<BranchPriceRow>> _loadAll() async {
    final bl = _branches.isEmpty ? await loadBranches() : _branches;
    final d = await Api.get(_url());
    final m = d is Map ? d : {};
    List<dynamic> pur = asList(m[_cur == 'USD' ? 'purchasesUsd' : 'purchases']);
    List<dynamic> usd = asList(m[_cur == 'USD' ? 'usedUsd' : 'used']);
    _pos = asList(m[_cur == 'USD' ? 'posUsd' : 'pos']);
    _items = asList(m[_cur == 'USD' ? 'itemsUsd' : 'items']);
    _used = asList(m[_cur == 'USD' ? 'usedItemsUsd' : 'usedItems']);
    final poSet = <String>{};
    for (final x in _pos) {
      poSet.add(pick(x, ['poNo']));
    }
    for (final x in _used) {
      poSet.add(pick(x, ['poNo']));
    }
    _poOpts = poSet.toList();
    _poOpts.sort((a, b) => b.compareTo(a));
    _selPos.removeWhere((o) => _poOpts.contains(o) == false);
    if (mounted) {
      setState(() {});
    }
    final sp = _selPos;
    if (sp.isNotEmpty) {
      final pb = <String, double>{};
      final ub = <String, double>{};
      for (final x in _pos) {
        if (sp.contains(pick(x, ['poNo']))) {
          final k = '${x['branchId']}';
          pb[k] = (pb[k] ?? 0) + _v(x['total']);
        }
      }
      for (final x in _used) {
        if (sp.contains(pick(x, ['poNo']))) {
          final k = '${x['branchId']}';
          ub[k] = (ub[k] ?? 0) + _v(x['amount']);
        }
      }
      pur = <dynamic>[
        for (final e in pb.entries)
          {'branchId': e.key, 'currency': _cur, 'total': e.value}
      ];
      usd = <dynamic>[
        for (final e in ub.entries)
          {'branchId': e.key, 'currency': _cur, 'used': e.value}
      ];
      _pos = _pos.where((x) => sp.contains(pick(x, ['poNo']))).toList();
      _used = _used.where((x) => sp.contains(pick(x, ['poNo']))).toList();
      final ids = _pos.map((x) => '${x['id']}').toSet();
      _items = _items.where((x) => ids.contains('${x['grnId']}')).toList();
    }
    if (_ptype.isNotEmpty && _ptById.isEmpty) {
      await _loadImgs();
    }
    if (_ptype.isNotEmpty) {
      bool keep(dynamic x) =>
          (_ptById[pick(x, ['productId'])] ?? 'FULL') == _ptype;
      final grnBr = <String, String>{};
      for (final x in _pos) {
        grnBr['${x['id']}'] = '${x['branchId']}';
      }
      _items = _items.where(keep).toList();
      _used = _used.where(keep).toList();
      final pb = <String, double>{};
      final ub = <String, double>{};
      final gt = <String, double>{};
      for (final x in _items) {
        final g = '${x['grnId']}';
        final k = grnBr[g] ?? '';
        pb[k] = (pb[k] ?? 0) + _v(x['amount']);
        gt[g] = (gt[g] ?? 0) + _v(x['amount']);
      }
      for (final x in _used) {
        final k = '${x['branchId']}';
        ub[k] = (ub[k] ?? 0) + _v(x['amount']);
      }
      pur = <dynamic>[
        for (final e in pb.entries)
          {'branchId': e.key, 'currency': _cur, 'total': e.value}
      ];
      usd = <dynamic>[
        for (final e in ub.entries)
          {'branchId': e.key, 'currency': _cur, 'used': e.value}
      ];
      _pos = [
        for (final x in _pos)
          if (gt.containsKey('${x['id']}'))
            {...Map<String, dynamic>.from(x as Map), 'total': gt['${x['id']}']}
      ];
    }
    final miss = _v(m['lakMissing']);
    if (_cur == 'LAK' && miss > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${miss.round()} GRN ຍັງບໍ່ມີມູນຄ່າ LAK ຈາກບັນຊີ'),
          duration: const Duration(seconds: 6)));
    }
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

  Future<void> _pickPos() async {
    final tmp = Set<String>.from(_selPos);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('ເລືອກ PO'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final o in _poOpts)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: tmp.contains(o),
                    title: Text(o.isEmpty ? 'ບໍ່ມີ PO' : 'PO $o'),
                    onChanged: (v) {
                      setS(() {
                        if (v == true) {
                          tmp.add(o);
                        } else {
                          tmp.remove(o);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => setS(() => tmp.clear()),
                child: const Text('ລ້າງ')),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('ຍົກເລີກ')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('ຕົກລົງ')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      _selPos = tmp;
      _load();
    }
  }

  void _setCur(String c) {
    _cur = c;
    _load();
  }

  void _setPtype(String t) {
    _ptype = t;
    _load();
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

  String _imgFor(dynamic e, [String nameKey = 'name']) {
    final v = _imgById[pick(e, ['productId'])] ??
        _imgByName[pick(e, [nameKey]).toLowerCase()] ??
        '';
    return productImageUrl(v);
  }

  String _k(dynamic v) {
    final d = (v is num) ? v.toDouble() : (double.tryParse('$v') ?? 0);
    final a = d.abs();
    String t(double x) {
      final r = x.toStringAsFixed(1);
      return r.endsWith('.0') ? r.substring(0, r.length - 2) : r;
    }

    String out;
    if (a >= 1000000000) {
      out = '${t(a / 1000000000)}B';
    } else if (a >= 1000000) {
      out = '${t(a / 1000000)}M';
    } else {
      final n = a.round().toString();
      final b = StringBuffer();
      for (var i = 0; i < n.length; i++) {
        if (i > 0 && (n.length - i) % 3 == 0) b.write(',');
        b.write(n[i]);
      }
      out = b.toString();
    }
    return d < 0 && out != '0' ? '-$out' : out;
  }

  String _pipe(dynamic x, String name, String loc, String atm, String po) {
    final info = _pinfo[pick(x, ['productId'])] ?? <String>['', '', '', ''];
    String f(String s) => s.isEmpty ? 'x' : s;
    final type = info[2].isEmpty ? name : info[2];
    final code = info[3].isEmpty ? pick(x, ['partNo']) : info[3];
    final q = _v(x['qty']).round().toString().padLeft(2, '0');
    return '${f(info[0])}|${f(info[1])}|${f(type)}|$q|${f(loc)}|${f(atm)}|${f(code)}|${f(po)}';
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
            sub: '${pick(x, [
                  'grnNo'
                ])} · ${pick(x, ['receiptDate']).split('T').first}',
            amount: '${_k(x['total'])} ${pick(x, ['currency'])}',
            lines: [
              for (final e
                  in _items.where((e) => '${e['grnId']}' == '${x['id']}'))
                BranchLineItem(
                    name: pick(e, ['name']),
                    sub: _pipe(e, pick(e, ['name']), r.branch, 'x', pick(x, ['poNo'])),
                    amount: '${_k(e['amount'])} ${pick(x, ['currency'])}',
                    qty: '+${pick(e, ['qty'])}',
                    imageUrl: _imgFor(e)),
            ]),
    ];
  }

  List<BranchPoItem> _usedGroupsFor(BranchPriceRow r) {
    final list = _used
        .where((x) =>
            '${x['branchId']}' == r.branchId &&
            (r.currency.isEmpty || pick(x, ['currency']) == r.currency))
        .toList();
    final groups = <String, List<dynamic>>{};
    for (final x in list) {
      groups.putIfAbsent(pick(x, ['atmId']), () => <dynamic>[]).add(x);
    }
    final out = <BranchPoItem>[];
    groups.forEach((id, xs) {
      double tot = 0;
      var parts = 0;
      var last = '';
      for (final x in xs) {
        tot += _v(x['amount']);
        parts += _v(x['qty']).round();
        final d = pick(x, ['createdAt']).split('T').first;
        if (d.compareTo(last) > 0) last = d;
      }
      out.add(BranchPoItem(
        id: 'atm-${r.branchId}-$id',
        po: id.isEmpty ? 'ບໍ່ມີ ATM ID' : 'ATM $id',
        sub: '$parts ອາໄຫຼ່ · $last',
        amount: '${_k(tot)} ${r.currency}',
        lines: [
          for (final x in xs)
            BranchLineItem(
                name: pick(x, ['productName']),
                sub: _pipe(x, pick(x, ['productName']), 'x', pick(x, ['atmId']), pick(x, ['poNo'])),
                amount: '${_k(x['amount'])} ${pick(x, ['currency'])}',
                qty: '-${pick(x, ['qty'])}',
                imageUrl: _imgFor(x, 'productName')),
        ],
      ));
    });
    return out;
  }

  List<BranchLineItem> _usedFor(BranchPriceRow r) {
    final list = _used
        .where((x) =>
            '${x['branchId']}' == r.branchId &&
            (r.currency.isEmpty || pick(x, ['currency']) == r.currency))
        .toList();
    return [
      for (final x in list)
        BranchLineItem(
            name: pick(x, ['atmId']).isEmpty
                ? pick(x, ['productName'])
                : 'ATM ${pick(x, ['atmId'])}',
            sub: _pipe(x, pick(x, ['productName']), 'x', pick(x, ['atmId']), pick(x, ['poNo'])),
            amount: '${_k(x['amount'])} ${pick(x, ['currency'])}',
            qty: '-${pick(x, ['qty'])}',
            imageUrl: _imgFor(x, 'productName')),
    ];
  }

  Widget _brandTable() {
    final p = pal(context);
    final cs = Theme.of(context).colorScheme;
    final grnPo = <String, String>{};
    for (final x in _pos) {
      grnPo['${x['id']}'] = pick(x, ['poNo']);
    }
    String f(String s) => s.isEmpty ? '-' : s;
    List<String> make(
        dynamic x, String atm, String po, double buy, double used) {
      final id = pick(x, ['productId']);
      final inf = _pinfo[id] ?? <String>['', '', '', ''];
      final fl = _pfull[id] ?? <String>['', 'FULL', '', ''];
      final own = fl[0].isEmpty ? pick(x, ['name', 'productName']) : fl[0];
      final partial = fl[1] == 'PARTIAL';
      final pl = partial ? _pfull[fl[2]] : null;
      final parent = (pl == null || pl.isEmpty) ? '' : pl[0];
      final full = partial ? (parent.isEmpty ? own : parent) : own;
      final part = partial ? own : '';
      final bc = fl[3].isEmpty ? inf[3] : fl[3];
      return <String>[
        f(inf[0]),
        f(inf[1]),
        f(full),
        f(part),
        _v(x['qty']).round().toString(),
        f(atm),
        f(bc),
        f(po),
        '$buy',
        '$used',
      ];
    }

    final ents = <List<String>>[];
    for (final e in _items) {
      ents.add(make(
          e, 'Stock', grnPo['${e['grnId']}'] ?? '', _v(e['amount']), 0));
    }
    for (final u in _used) {
      ents.add(make(
          u, pick(u, ['atmId']), pick(u, ['poNo']), 0, _v(u['amount'])));
    }
    if (ents.isEmpty) {
      return Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
              child: Text('ບໍ່ມີຂໍ້ມູນ', style: TextStyle(color: p.mut))));
    }
    final tree = <String, Map<String, List<List<String>>>>{};
    for (final r in ents) {
      tree
          .putIfAbsent(r[0], () => <String, List<List<String>>>{})
          .putIfAbsent(r[1], () => <List<String>>[])
          .add(r);
    }
    double sum(Iterable<List<String>> l, int i) {
      var t = 0.0;
      for (final r in l) {
        t += double.tryParse(r[i]) ?? 0;
      }
      return t;
    }

    final allBuy = sum(ents, 8);
    final allUsed = sum(ents, 9);
    final small = TextStyle(color: p.mut, fontSize: 12);
    const bold = TextStyle(fontWeight: FontWeight.w700);

    Widget stat(String label, double v, Color bg, Color fg) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: fg, fontSize: 12)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_k(v),
                      style: TextStyle(
                          color: fg,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );

    Widget atmChip(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color:
                  t == 'Stock' ? cs.secondaryContainer : cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(10)),
          child: Text(t, style: const TextStyle(fontSize: 12)),
        );

    Widget detail(List<List<String>> l) => Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                headingRowHeight: 38,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 52,
                headingRowColor:
                    WidgetStatePropertyAll(cs.surfaceContainerHighest),
                columns: [
                  for (final h in const [
                    'Full part',
                    'Part',
                    'Amount',
                    'ATM',
                    'Barcode',
                    'PO'
                  ])
                    DataColumn(label: Text(h, style: bold))
                ],
                rows: [
                  for (final r in l)
                    DataRow(cells: [
                      DataCell(Text(r[2])),
                      DataCell(Text(r[3])),
                      DataCell(Text(r[4], style: bold)),
                      DataCell(atmChip(r[5])),
                      DataCell(Text(r[6])),
                      DataCell(Text(r[7])),
                    ])
                ],
              ),
            ),
          ),
        );

    double brandNet(String b) {
      var t = 0.0;
      for (final l in (tree[b] ?? <String, List<List<String>>>{}).values) {
        t += sum(l, 8) - sum(l, 9);
      }
      return t;
    }

    final brands = tree.keys.toList();
    brands.sort((a, b) => brandNet(b).compareTo(brandNet(a)));
    final cards = <Widget>[];
    for (final b in brands) {
      final models = tree[b] ?? <String, List<List<String>>>{};
      final all = <List<String>>[
        for (final l in models.values) ...l,
      ];
      final mkeys = models.keys.toList()..sort();
      cards.add(Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant)),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
              child: Text(b.isEmpty ? '-' : b.substring(0, 1).toUpperCase())),
          title: Row(children: [
            Expanded(child: Text(b, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            Text(_k(sum(all, 8) - sum(all, 9)), style: bold),
          ]),
          subtitle: Text(
              '${mkeys.length} model · ${all.length} ແຖວ · Buy ${_k(sum(all, 8))} · Used ${_k(sum(all, 9))}',
              style: small),
          children: [
            for (final m in mkeys)
              ExpansionTile(
                tilePadding: const EdgeInsets.only(left: 20, right: 12),
                shape: const Border(),
                collapsedShape: const Border(),
                leading: Icon(Icons.memory_outlined, color: cs.primary),
                title: Row(children: [
                  Expanded(
                      child: Text(m == '-' ? 'ບໍ່ມີ Model' : m,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(
                      _k(sum(models[m] ?? <List<String>>[], 8) -
                          sum(models[m] ?? <List<String>>[], 9)),
                      style: bold),
                ]),
                subtitle: Text(
                    'Buy ${_k(sum(models[m] ?? <List<String>>[], 8))} · Used ${_k(sum(models[m] ?? <List<String>>[], 9))}',
                    style: small),
                children: [detail(models[m] ?? <List<String>>[])],
              ),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        stat('Price buy · $_cur', allBuy, cs.primaryContainer,
            cs.onPrimaryContainer),
        const SizedBox(width: 8),
        stat('Used', allUsed, cs.tertiaryContainer, cs.onTertiaryContainer),
        const SizedBox(width: 8),
        stat('Total', allBuy - allUsed, cs.secondaryContainer,
            cs.onSecondaryContainer),
      ]),
      const SizedBox(height: 12),
      ...cards,
    ]);
  }

  Widget _fullTable() {
    final p = pal(context);
    final cs = Theme.of(context).colorScheme;
    final grnPo = <String, String>{};
    for (final x in _pos) {
      grnPo['${x['id']}'] = pick(x, ['poNo']);
    }
    String f(String s) => s.isEmpty ? '-' : s;
    List<String> make(dynamic x, String atm, String po, double buy,
        double used, String term) {
      final id = pick(x, ['productId']);
      final inf = _pinfo[id] ?? <String>['', '', '', ''];
      final fl = _pfull[id] ?? <String>['', 'FULL', '', ''];
      final own = fl[0].isEmpty ? pick(x, ['name', 'productName']) : fl[0];
      final partial = fl[1] == 'PARTIAL';
      final pl = partial ? _pfull[fl[2]] : null;
      final parent = (pl == null || pl.isEmpty) ? '' : pl[0];
      final full = partial ? (parent.isEmpty ? own : parent) : own;
      final part = partial ? own : '';
      final bc = fl[3].isEmpty ? inf[3] : fl[3];
      final img = _imgFor(x, x['productName'] == null ? 'name' : 'productName');
      return <String>[
        f(inf[0]),
        f(inf[1]),
        f(full),
        f(part),
        _v(x['qty']).round().toString(),
        f(atm),
        f(bc),
        f(po),
        '$buy',
        '$used',
        img,
        f(term),
      ];
    }

    final ents = <List<String>>[];
    for (final e in _items) {
      ents.add(make(e, 'Stock', grnPo['${e['grnId']}'] ?? '',
          _v(e['amount']), 0, ''));
    }
    for (final u in _used) {
      ents.add(make(u, pick(u, ['atmId']), pick(u, ['poNo']), 0,
          _v(u['amount']), pick(u, ['terminalBarcode'])));
    }
    if (ents.isEmpty) {
      return Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
              child: Text('ບໍ່ມີຂໍ້ມູນ', style: TextStyle(color: p.mut))));
    }
    ents.sort((a, b) {
      for (final i in const [0, 1, 2, 3]) {
        final c = a[i].compareTo(b[i]);
        if (c == 0) continue;
        return c;
      }
      return 0;
    });
    double sum(int i) {
      var t = 0.0;
      for (final r in ents) {
        t += double.tryParse(r[i]) ?? 0;
      }
      return t;
    }

    final allBuy = sum(8);
    final allUsed = sum(9);
    final allQty = sum(4).round();
    const bold = TextStyle(fontWeight: FontWeight.w700);

    Widget stat(String label, double v, Color bg, Color fg) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: fg, fontSize: 12)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_k(v),
                      style: TextStyle(
                          color: fg,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );

    DataCell cell(String t, {double w = 170, TextStyle? st}) => DataCell(
        ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w),
            child: Text(t,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: st)));

    DataCell atmCell(String t) => DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color:
                  t == 'Stock' ? cs.secondaryContainer : cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(10)),
          child: Text(t, style: const TextStyle(fontSize: 12)),
        ));

    DataCell termCell(String bc) {
      if (bc == '-') return const DataCell(Text('-'));
      final ti = _tinfo[bc] ?? <String>['', ''];
      return DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        typeThumb(context, ti[1], size: 36),
        const SizedBox(width: 8),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(bc, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (ti[0].isNotEmpty)
              Text(ti[0], style: TextStyle(color: p.mut, fontSize: 12)),
          ],
        ),
      ]));
    }

    DataCell imgCell(String url) {
      const s = 44.0;
      const ic = SizedBox(
          width: s, height: s, child: Icon(Icons.build_outlined));
      if (url.isEmpty) return const DataCell(ic);
      return DataCell(ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url,
            width: s,
            height: s,
            fit: BoxFit.cover,
            errorBuilder: (c, e, st) => ic),
      ));
    }

    final table = Container(
      decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 18,
            headingRowHeight: 40,
            dataRowMinHeight: 52,
            dataRowMaxHeight: 60,
            headingRowColor:
                WidgetStatePropertyAll(cs.surfaceContainerHighest),
            columns: [
              for (final h in const [
                'Image',
                'Brand',
                'Model',
                'Full part',
                'Part',
                'Amount',
                'ATM',
                'Terminal',
                'Barcode',
                'PO'
              ])
                DataColumn(label: Text(h, style: bold))
            ],
            rows: [
              for (final r in ents)
                DataRow(cells: [
                  imgCell(r[10]),
                  cell(r[0], w: 80),
                  cell(r[1], w: 150),
                  cell(r[2], w: 220),
                  cell(r[3], w: 160),
                  cell(r[4], w: 60, st: bold),
                  atmCell(r[5]),
                  termCell(r[11]),
                  cell(r[6], w: 130),
                  cell(r[7], w: 90),
                ]),
              DataRow(
                  color: WidgetStatePropertyAll(cs.surfaceContainerHighest),
                  cells: [
                    cell(''),
                    cell('Total', w: 80, st: bold),
                    cell(''),
                    cell(''),
                    cell(''),
                    cell('$allQty', w: 60, st: bold),
                    cell(''),
                    cell(''),
                    cell(''),
                    cell(''),
                  ]),
            ],
          ),
        ),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        stat('Price buy · $_cur', allBuy, cs.primaryContainer,
            cs.onPrimaryContainer),
        const SizedBox(width: 8),
        stat('Used', allUsed, cs.tertiaryContainer, cs.onTertiaryContainer),
        const SizedBox(width: 8),
        stat('Total', allBuy - allUsed, cs.secondaryContainer,
            cs.onSecondaryContainer),
      ]),
      const SizedBox(height: 12),
      Text('ລາຍລະອຽດອາໄຫຼ່ · ${ents.length} ແຖວ', style: bold),
      const SizedBox(height: 8),
      table,
    ]);
  }

  void _openDocs() {
    var name = 'ທຸກສາຂາ';
    for (final b in _branches) {
      if ('${b['id']}' == '$_branchId') {
        name = pick(b, ['name', 'branchName', 'id']);
      }
    }
    debugPrint(
        '[DOCS] open page branch=$_branchId from=${_d(_range.start)} to=${_d(_range.end)}');
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReportDocsPage(
            branchId: _branchId == null ? 0 : (int.tryParse('$_branchId') ?? 0),
            branchName: name,
            from: _d(_range.start),
            to: _d(_range.end))));
  }

  Future<void> _export(String kind) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final f = _f;
      final rows = f == null ? <BranchPriceRow>[] : await f;
      if (rows.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('ບໍ່ມີຂໍ້ມູນ')));
        return;
      }
      messenger.showSnackBar(const SnackBar(
          content: Text('ກຳລັງສ້າງໄຟລ໌...'), duration: Duration(seconds: 15)));
      var branchName = 'ທຸກສາຂາ';
      for (final b in _branches) {
        if ('${b['id']}' == '$_branchId') {
          branchName = pick(b, ['name', 'branchName', 'id']);
        }
      }
      final data = PriceReportData(
          range: '${_d(_range.start)} - ${_d(_range.end)}',
          branch: branchName,
          rows: rows,
          pos: _pos,
          items: _items,
          used: _used,
          imgFor: (x, k) => _imgFor(x, k));
      if (kind == 'pdf') {
        await sharePriceReportPdf(data);
      } else {
        await sharePriceReportXlsx(data);
      }
    } catch (e) {
      debugPrint('[REPORT] export $kind failed: $e');
      messenger.showSnackBar(SnackBar(content: Text('ດາວໂຫຼດບໍ່ສຳເລັດ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ຕູ້ ATM ທີ່ປ່ຽນອາໄຫຼ່')),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        indicatorColor: Colors.transparent,
        onDestinationSelected: (i) {
          if (i == 0) _export('xlsx');
          if (i == 1) _export('pdf');
          if (i == 2) _openDocs();
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.table_view_outlined), label: 'Excel'),
          NavigationDestination(
              icon: Icon(Icons.picture_as_pdf_outlined), label: 'PDF'),
          NavigationDestination(
              icon: Icon(Icons.upload_file_outlined), label: 'ອັບໂຫຼດ'),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.checklist),
          label: Text(_selPos.isEmpty
              ? 'PO: ທຸກ PO'
              : 'PO: ເລືອກ ${_selPos.length}'),
          onPressed: _pickPos,
        ),
        if (_selPos.isNotEmpty)
          Wrap(spacing: 6, children: [
            for (final o in _selPos)
              InputChip(
                  label: Text(o.isEmpty ? 'ບໍ່ມີ PO' : o),
                  onDeleted: () {
                    _selPos.remove(o);
                    _load();
                  }),
          ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ChoiceChip(
              label: const Text('LAK'),
              selected: _cur == 'LAK',
              onSelected: (_) => _setCur('LAK')),
          ChoiceChip(
              label: const Text('USD'),
              selected: _cur == 'USD',
              onSelected: (_) => _setCur('USD')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ChoiceChip(
              label: const Text('ທັງໝົດ'),
              selected: _ptype.isEmpty,
              onSelected: (_) => _setPtype('')),
          ChoiceChip(
              label: const Text('ອາໄຫຼ່ເຕັມ'),
              selected: _ptype == 'FULL',
              onSelected: (_) => _setPtype('FULL')),
          ChoiceChip(
              label: const Text('ອາໄຫຼ່ຍ່ອຍ'),
              selected: _ptype == 'PARTIAL',
              onSelected: (_) => _setPtype('PARTIAL')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ChoiceChip(
              label: const Text('ເດືອນ'),
              selected: _mode == 'month',
              onSelected: (_) => _setMode('month')),
          ChoiceChip(
              label: const Text('ປີ'),
              selected: _mode == 'year',
              onSelected: (_) => _setMode('year')),
          ChoiceChip(
              label: const Text('ກຳນົດເອງ'),
              selected: _mode == 'custom',
              onSelected: (_) => _setMode('custom')),
        ]),
        const SizedBox(height: 8),
        if (_mode == 'custom')
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text('${_d(_range.start)}  →  ${_d(_range.end)}'),
            onPressed: _pickRange,
          )
        else ...[
          Row(children: [
            IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1)),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: Text(_label),
                onPressed: _jump,
              ),
            ),
            IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shift(1)),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: Text('${_d(_range.start)}  →  ${_d(_range.end)}',
                  style: TextStyle(color: p.mut, fontSize: 12)),
            ),
          ),
        ],
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
            return _fullTable();
          },
        ),
      ]),
    );
  }
}
