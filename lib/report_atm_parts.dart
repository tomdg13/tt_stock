import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';
import 'product_images.dart';

class _PoGroup {
  _PoGroup(this.po);
  final String po;
  final List<dynamic> grns = <dynamic>[];
  final List<dynamic> items = <dynamic>[];
  final List<dynamic> used = <dynamic>[];
}

class _SpRow {
  _SpRow(this.productId, this.name);
  final String productId;
  String name;
  int recv = 0;
  int usedQty = 0;
  double usedAmt = 0;
  final List<dynamic> atms = <dynamic>[];
}

class ReportAtmPartsPage extends StatefulWidget {
  const ReportAtmPartsPage({super.key});
  @override
  State<ReportAtmPartsPage> createState() => _ReportAtmPartsPageState();
}

class _ReportAtmPartsPageState extends State<ReportAtmPartsPage> {
  List<dynamic> _pos = [];
  List<dynamic> _items = [];
  List<dynamic> _used = [];
  Map<String, String> _imgById = {};
  Map<String, String> _imgByName = {};
  String? _sel;
  String _mode = 'month';
  DateTime _anchor = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTimeRange _range = DateTimeRange(
      start: DateTime(DateTime.now().year, DateTime.now().month, 1),
      end: DateTime(DateTime.now().year, DateTime.now().month + 1, 0));
  Future<int>? _f;

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _v(dynamic v) => double.tryParse('$v') ?? 0;
  int _n(dynamic v) => _v(v).round();
  String _date(dynamic v) => v == null ? '' : '$v'.split('T').first;

  String get _label => _mode == 'year'
      ? '${_anchor.year}'
      : '${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}';

  String _poName(String po) => po.isEmpty ? 'ບໍ່ມີ PO' : 'PO $po';

  @override
  void initState() {
    super.initState();
    _loadImgs();
    _load();
  }

  Future<void> _loadImgs() async {
    try {
      final d = await Api.get('/products?limit=200');
      final byId = <String, String>{};
      final byName = <String, String>{};
      for (final m in asList(d)) {
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

  Future<int> _fetch() async {
    final d = await Api.get(
        '/repair/price-report-branch?from=${_d(_range.start)}&to=${_d(_range.end)}');
    final m = d is Map ? d : {};
    _pos = asList(m['pos']);
    _items = asList(m['items']);
    _used = asList(m['usedItems']);
    return _pos.length;
  }

  void _load() {
    setState(() {
      _f = _fetch();
    });
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
    if (d < 0 && out.length > 1) return '-$out';
    if (d < 0 && out.codeUnitAt(0) > 48) return '-$out';
    return out;
  }

  String _imgFor(String productId, String name) {
    final v = _imgById[productId] ?? _imgByName[name.toLowerCase()] ?? '';
    return productImageUrl(v);
  }

  Widget _thumb(String url) {
    const box = 40.0;
    if (url.isEmpty) {
      return const SizedBox(
          width: box, height: box, child: Icon(Icons.build_outlined));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(url,
          width: box,
          height: box,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => const SizedBox(
              width: box, height: box, child: Icon(Icons.build_outlined))),
    );
  }

  List<_PoGroup> _groups() {
    final map = <String, _PoGroup>{};
    _PoGroup g(String po) => map.putIfAbsent(po, () => _PoGroup(po));
    final grnPo = <String, String>{};
    for (final x in _pos) {
      final po = pick(x, ['poNo']);
      grnPo['${x['id']}'] = po;
      g(po).grns.add(x);
    }
    for (final it in _items) {
      final po = grnPo['${it['grnId']}'];
      if (po == null) continue;
      g(po).items.add(it);
    }
    for (final u in _used) {
      g(pick(u, ['poNo'])).used.add(u);
    }
    final list = map.values.toList();
    list.sort((a, b) {
      if (a.po.isEmpty) return 1;
      if (b.po.isEmpty) return -1;
      return b.po.compareTo(a.po);
    });
    return list;
  }

  List<_SpRow> _sps(_PoGroup g) {
    final map = <String, _SpRow>{};
    _SpRow row(String id, String name) =>
        map.putIfAbsent(id, () => _SpRow(id, name));
    for (final it in g.items) {
      final r = row(pick(it, ['productId']), pick(it, ['name']));
      r.recv += _n(it['qty']);
    }
    for (final u in g.used) {
      final r = row(pick(u, ['productId']), pick(u, ['productName']));
      if (r.name.isEmpty) r.name = pick(u, ['productName']);
      r.usedQty += _n(u['qty']);
      r.usedAmt += _v(u['amount']);
      r.atms.add(u);
    }
    final list = map.values.toList();
    list.sort((a, b) => b.usedQty.compareTo(a.usedQty));
    return list;
  }

  Widget _spTile(_PoGroup g, _SpRow r) {
    final p = pal(context);
    final hasRecv = g.grns.isNotEmpty;
    final left = r.recv - r.usedQty;
    final sub = hasRecv
        ? 'ຮັບ ${r.recv} · ໃຊ້ ${r.usedQty} · ເຫຼືອ $left'
        : 'ໃຊ້ ${r.usedQty}';
    final trailing = Text('${_k(r.usedAmt)} LAK',
        style: const TextStyle(fontWeight: FontWeight.w600));
    final lead = _thumb(_imgFor(r.productId, r.name));
    if (r.atms.isEmpty) {
      return ListTile(
          dense: true,
          leading: lead,
          title: Text(r.name),
          subtitle: Text(sub, style: TextStyle(color: p.mut)),
          trailing: Text('ຍັງບໍ່ໄດ້ໃຊ້', style: TextStyle(color: p.mut)));
    }
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      leading: lead,
      title: Text(r.name),
      subtitle: Text(sub, style: TextStyle(color: p.mut)),
      trailing: trailing,
      children: [
        for (final u in r.atms)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: Text(pick(u, ['atmId']).isEmpty
                ? 'ບໍ່ມີ ATM ID'
                : 'ATM ${pick(u, ['atmId'])}'),
            subtitle: Text(_date(u['createdAt'])),
            trailing: Text('-${_n(u['qty'])}'),
          ),
      ],
    );
  }

  Widget _poCard(_PoGroup g, bool open) {
    final p = pal(context);
    final sps = _sps(g);
    var usedQty = 0;
    var usedAmt = 0.0;
    for (final u in g.used) {
      usedQty += _n(u['qty']);
      usedAmt += _v(u['amount']);
    }
    var total = 0.0;
    for (final x in g.grns) {
      total += _v(x['total']);
    }
    final grnNos = g.grns.map((x) => pick(x, ['grnNo'])).join(', ');
    final date = g.grns.isEmpty ? '' : _date(g.grns.first['receiptDate']);
    final sub = g.grns.isEmpty
        ? 'ຮັບກ່ອນໄລຍະນີ້ · ໃຊ້ $usedQty ອາໄຫຼ່'
        : '$grnNos · $date · ໃຊ້ $usedQty ອາໄຫຼ່';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: PageStorageKey('po-${g.po}-$open'),
        initiallyExpanded: open,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(_poName(g.po),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(sub, style: TextStyle(color: p.mut, fontSize: 12)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${_k(total)} LAK',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('ໃຊ້ ${_k(usedAmt)}',
                style: TextStyle(color: p.mut, fontSize: 12)),
          ],
        ),
        children: [
          if (sps.isEmpty)
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text('ບໍ່ມີອາໄຫຼ່', style: TextStyle(color: p.mut))),
          for (final r in sps) _spTile(g, r),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ຕູ້ ATM ທີ່ປ່ຽນອາໄຫຼ່'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
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
        FutureBuilder<int>(
          future: _f,
          builder: (c, s) {
            if (s.connectionState == ConnectionState.waiting ||
                s.connectionState == ConnectionState.none) {
              return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()));
            }
            if (s.hasError) return ErrorView(s.error as Object, _load);
            final groups = _groups();
            if (groups.isEmpty) {
              return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                      child:
                          Text('ບໍ່ມີຂໍ້ມູນ', style: TextStyle(color: p.mut))));
            }
            final sel = groups.any((g) => g.po == _sel) ? _sel : null;
            final shown = sel == null
                ? groups
                : groups.where((g) => g.po == sel).toList();
            var usedQty = 0;
            for (final g in shown) {
              for (final u in g.used) {
                usedQty += _n(u['qty']);
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<dynamic>(
                  key: ValueKey('po-${groups.length}-$sel'),
                  initialValue: sel,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'PO'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('ທຸກ PO')),
                    for (final g in groups)
                      DropdownMenuItem(
                          value: g.po, child: Text(_poName(g.po))),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _sel = v == null ? null : '$v';
                    });
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${shown.length} PO · ໃຊ້ $usedQty ອາໄຫຼ່',
                      style: TextStyle(color: p.mut)),
                ),
                for (final g in shown) _poCard(g, sel == null ? false : true),
              ],
            );
          },
        ),
      ]),
    );
  }
}
