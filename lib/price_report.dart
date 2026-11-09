import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'widgets.dart';
import 'product_images.dart';
import 'branch_price_table.dart';
import 'report_docs_page.dart';
import 'price_report_export.dart';

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
    _used = asList(m['usedItems']);
    final miss = _v(m['lakMissing']);
    if (miss > 0 && mounted) {
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
            amount: '${_k(x['total'])} ${pick(x, ['currency'])}',
            lines: [
              for (final e in _items.where((e) => '${e['grnId']}' == '${x['id']}'))
                BranchLineItem(
                    name: pick(e, ['name']),
                    sub: '${_k(e['unitCost'])} × ${pick(e, ['qty'])}',
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
                sub:
                    '${pick(x, ['createdAt']).split('T').first} · ${_po(x)}',
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
            sub:
                '${pick(x, ['productName'])} · ${pick(x, ['createdAt']).split('T').first} · ${_po(x)}',
            amount: '${_k(x['amount'])} ${pick(x, ['currency'])}',
            qty: '-${pick(x, ['qty'])}',
            imageUrl: _imgFor(x, 'productName')),
    ];
  }

  void _openDocs() {
    var name = 'ທຸກສາຂາ';
    for (final b in _branches) {
      if ('${b['id']}' == '$_branchId') {
        name = pick(b, ['name', 'branchName', 'id']);
      }
    }
    debugPrint('[DOCS] open page branch=$_branchId from=${_d(_range.start)} to=${_d(_range.end)}');
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
      appBar: AppBar(title: const Text('ລາຍງານລາຄາອາໄຫຼ່')),
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
            return BranchPriceTable(
                key: ValueKey('t-${_range.start}-${_range.end}-$_branchId'),
                rows: rows,
                children: _posFor,
                used: _usedFor, usedGroups: _usedGroupsFor);
          },
        ),
      ]),
    );
  }
}
