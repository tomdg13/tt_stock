import 'terminal_actions.dart' show PickProductPage;
import 'product_images.dart';
import 'image_search.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'stock_drill.dart';
import 'purchase_orders.dart';
import 'screens.dart' show BarcodeScanPage;
import 'lao.dart';
import 'theme.dart';
import 'widgets.dart';
import 'invoice_import.dart';

// ------------------------------------------------------------- shared bits
class Line {
  final Map<String, dynamic> product;
  int qty;
  double cost = 0;
  Line(this.product, this.qty);
}

/// Product search sheet; returns the chosen product map.
Future<Map<String, dynamic>?> pickProduct(BuildContext context) =>
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ProductPicker(),
    );

class _ProductPicker extends StatefulWidget {
  const _ProductPicker();
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  Widget _pickThumb(BuildContext context, String v) {
    final p = pal(context);
    final ph = Container(
      width: 48,
      height: 48,
      decoration:
          BoxDecoration(color: p.bd, borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.image_outlined, color: p.mut),
    );
    final url = productImageUrl(v);
    if (url.isEmpty) return ph;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ph),
    );
  }

  final _q = TextEditingController();
  late Future<dynamic> _f = _load();
  Future<dynamic> _load() {
    debugPrint('[PICK] OLD bottom-sheet picker (_ProductPicker) -> GET /products?limit=30&active=1');
    return Api.get(
        '/products?limit=30&active=1&q=${Uri.encodeQueryComponent(_q.text.trim())}');
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _q,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => setState(() {
                _f = _load();
              }),
              decoration: InputDecoration(
                  hintText: 'ຄົ້ນຫາສິນຄ້າ',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: SearchTools(onResult: (v) {
                    _q.text = v;
                    setState(() {
                      _f = _load();
                    });
                  })),
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: _f,
              builder: (c, s) {
                if (s.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (s.hasError)
                  return ErrorView(
                      s.error!,
                      () => setState(() {
                            _f = _load();
                          }));
                final items = asList(s.data);
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: _pickThumb(context, pick(items[i], ['imageUrl', 'image', 'photo'])),
                    title: Text(pick(items[i], ['name', 'productName', 'id'])),
                    subtitle: Text(
                        pick(items[i], ['brandName', 'typeName', 'code']),
                        style: TextStyle(color: p.mut)),
                    onTap: () => Navigator.pop(context, items[i]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// "Items" block with add / +- / remove; the parent owns [lines].
class LineEditor extends StatefulWidget {
  final List<Line> lines;
  final bool showCost;
  final dynamic branchId;
  const LineEditor(this.lines,
      {super.key, this.showCost = false, this.branchId});
  @override
  State<LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<LineEditor> {
  final Map<int, TextEditingController> _qcs = {};
  TextEditingController _qc(Line l) => _qcs.putIfAbsent(
      identityHashCode(l), () => TextEditingController(text: '${l.qty}'));

  @override
  void dispose() {
    for (final c in _qcs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _costRow(Line l) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Row(children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('cost-${identityHashCode(l)}'),
              initialValue: l.cost > 0 ? '${l.cost}' : '',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'ລາຄາຕໍ່ໜ່ວຍ', isDense: true),
              onChanged: (v) => setState(() {
                l.cost = double.tryParse(v.replaceAll(',', '')) ?? 0;
              }),
            ),
          ),
          const SizedBox(width: 12),
          Text('= ${(l.cost * l.qty).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final lines = widget.lines;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('ສິນຄ້າ', style: TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        TextButton.icon(
          onPressed: () async {
            final prod = widget.branchId != null
                ? await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PickProductPage(
                            branchId: widget.branchId, pickerMode: true)))
                : await pickProduct(context);
            if (prod != null)
              setState(() {
                lines.add(Line(prod, 1));
              });
          },
          icon: const Icon(Icons.add),
          label: const Text('ເພີ່ມສິນຄ້າ'),
        ),
      ]),
      if (lines.isEmpty)
        Text('ຍັງບໍ່ໄດ້ເລືອກສິນຄ້າ', style: TextStyle(color: p.mut)),
      for (var i = 0; i < lines.length; i++)
        cardBox(
          context,
          margin: const EdgeInsets.only(top: 6),
          color: p.bg,
          radius: 8,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Builder(builder: (_) {
              final u = productImageUrl(pick(lines[i].product,
                  ['imageUrl', 'image', 'photo', 'imageFile']));
              final ph = Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: p.bd, borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.image_outlined, color: p.mut));
              if (u.isEmpty) return ph;
              return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(u,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ph));
            }),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(pick(lines[i].product, ['name', 'productName', 'id']),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(pick(lines[i].product, ['brandName', 'typeName']),
                          style: TextStyle(color: p.mut, fontSize: 12)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: lines[i].qty > 1
                          ? () => setState(() {
                                lines[i].qty--;
                                _qc(lines[i]).text = '${lines[i].qty}';
                              })
                          : null),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: _qc(lines[i]),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(isDense: true),
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null && n > 0) {
                          setState(() => lines[i].qty = n);
                        }
                      },
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() {
                            lines[i].qty++;
                            _qc(lines[i]).text = '${lines[i].qty}';
                          })),
                  IconButton(
                      icon: Icon(Icons.delete_outline, color: p.bad),
                      onPressed: () => setState(() {
                            lines.removeAt(i);
                          })),
                ]),
              ]),
            ),
            if (widget.showCost) _costRow(lines[i]),
          ]),
        ),
    ]);
  }
}

Widget moveRow(BuildContext c, Map<String, dynamic> m) {
  final p = pal(c);
  final t = pick(m, ['type', 'movementType']);
  final info = moveTypes[t];
  final q = num0(m['qtyChange'] ?? m['qty'] ?? m['quantity']);
  final dRaw = pick(m, ['movementDate', 'createdAt', 'time', 'ts', 'movedAt']);
  final dStr = dRaw.length >= 10 ? dRaw.substring(0, 10) : dRaw;
  final meta = [
    pick(m, ['branchName', 'branchId']),
    pick(m, ['ref', 'refNo', 'docNo']),
    dStr,
  ].where((e) => e.isNotEmpty).join(' · ');
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.bd))),
    child: Row(children: [
      Tag(info?[0] ?? t, info?[1] ?? ''),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pick(m, ['productName', 'name', 'productId'])),
          if (meta.isNotEmpty)
            Text(meta, style: TextStyle(color: p.mut, fontSize: 12)),
        ]),
      ),
      Text('${q > 0 ? '+' : ''}${fmtNum(q)}',
          style: TextStyle(
              fontWeight: FontWeight.w700, color: q > 0 ? p.ok : p.bad)),
    ]),
  );
}

Widget futureBlock(Future<dynamic> f, VoidCallback retry,
        Widget Function(dynamic) build) =>
    FutureBuilder(
      future: f,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()));
        }
        if (s.hasError) return ErrorView(s.error!, retry);
        return build(s.data);
      },
    );

Widget branchDropdown(String label, List<Map<String, dynamic>> branches,
        dynamic value, ValueChanged<dynamic> onChanged) =>
    DropdownButtonFormField<dynamic>(
      key: ValueKey('$label-${branches.length}-$value'),
      initialValue: branches.any((b) => b['id'] == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final b in branches)
          DropdownMenuItem(
              value: b['id'],
              child: Text(pick(b, ['name', 'branchName', 'id']))),
      ],
      onChanged: onChanged,
    );

Widget saveButton(String text, bool busy, VoidCallback onTap) => SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(text),
      ),
    );

// ---------------------------------------------------------------- Stock
class StockScreen extends StatelessWidget {
  const StockScreen({super.key});
  @override
  Widget build(BuildContext context) => const StockDrill();
}

// previous flat stock table (kept for reference)
class StockScreenOld extends StatefulWidget {
  const StockScreenOld({super.key});
  @override
  State<StockScreenOld> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreenOld> {
  final _q = TextEditingController();
  bool _low = false;
  late Future<dynamic> _f = _load();

  Future<dynamic> _load() {
    final parts = [
      if (_q.text.trim().isNotEmpty)
        'q=${Uri.encodeQueryComponent(_q.text.trim())}',
      if (_low) 'low=1',
    ];
    return Api.get(
        '/stock/balances${parts.isEmpty ? '' : '?${parts.join('&')}'}');
  }

  void _reload() => setState(() {
        _f = _load();
      });

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reload(),
              decoration: const InputDecoration(
                  hintText: 'ຄົ້ນຫາສິນຄ້າ', prefixIcon: Icon(Icons.search)),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('ໃກ້ໝົດ'),
            selected: _low,
            onSelected: (v) {
              _low = v;
              _reload();
            },
          ),
        ]),
      ),
      Expanded(
        child: FutureBuilder(
          future: _f,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (s.hasError) return ErrorView(s.error!, _reload);
            final rows = asList(s.data);
            final groups = <String, List<Map<String, dynamic>>>{};
            for (final r in rows) {
              groups
                  .putIfAbsent(
                      pick(r, ['productId', 'productName', 'name', 'id']),
                      () => [])
                  .add(r);
            }
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: groups.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(
                          child: Text('ຍັງບໍ່ມີລາຍການ',
                              style: TextStyle(color: p.mut))),
                    ])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                          _stockTable(context, rows),
                          Text('ຕົວເລກສີແດງ = ຕ່ຳກວ່າຈຳນວນຕ່ຳສຸດ',
                              style: TextStyle(color: p.mut, fontSize: 13)),
                        ]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _stockTable(BuildContext context, List<Map<String, dynamic>> rows) {
    final p = pal(context);
    const qk = ['qty', 'quantity', 'balance', 'onHand', 'qtyOnHand'];
    const mk = ['minQty', 'min', 'minStock', 'reorderLevel'];
    double total = 0;
    final dataRows = <DataRow>[];
    for (final r in rows) {
      final q = num0(pick(r, qk)), min = num0(pick(r, mk));
      final low = min > 0 && q < min;
      total += q;
      final sub = [
        pick(r, ['brandName']),
        pick(r, ['typeName']),
        pick(r, ['unit'])
      ].where((e) => e.isNotEmpty).join(' · ');
      dataRows.add(DataRow(cells: [
        DataCell(Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pick(r, ['productName', 'name', 'productId']),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (sub.isNotEmpty)
              Text(sub, style: TextStyle(color: p.mut, fontSize: 12)),
          ],
        )),
        DataCell(ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(
              pick(r, ['modelName']).isEmpty ? '-' : pick(r, ['modelName']),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
        )),
        DataCell(Text(pick(r, ['binCode']))),
        DataCell(Text(pick(r, ['branchName', 'branchId']),
            style: TextStyle(color: p.mut))),
        DataCell(Text(fmtNum(min), style: TextStyle(color: p.mut))),
        DataCell(Text(fmtNum(q),
            style: TextStyle(
                fontWeight: FontWeight.w700, color: low ? p.bad : p.tx))),
      ]));
    }
    dataRows.add(DataRow(cells: [
      const DataCell(
          Text('ລວມ', style: TextStyle(fontWeight: FontWeight.w700))),
      const DataCell(Text('')),
      const DataCell(Text('')),
      const DataCell(Text('')),
      const DataCell(Text('')),
      DataCell(Text(fmtNum(total),
          style: const TextStyle(fontWeight: FontWeight.w700))),
    ]));
    return AppCard(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minWidth: MediaQuery.of(context).size.width - 64),
          child: DataTable(
            columnSpacing: 20,
            horizontalMargin: 8,
            headingRowHeight: 38,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 56,
            dividerThickness: 0.6,
            headingTextStyle: TextStyle(
                color: p.mut, fontSize: 12, fontWeight: FontWeight.w600),
            columns: const [
              DataColumn(label: Text('ສິນຄ້າ')),
              DataColumn(label: Text('ຮຸ່ນ')),
              DataColumn(label: Text('ບິນ')),
              DataColumn(label: Text('ສາຂາ')),
              DataColumn(label: Text('ຕ່ຳສຸດ'), numeric: true),
              DataColumn(label: Text('ຈຳນວນ'), numeric: true),
            ],
            rows: dataRows,
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _productCard(BuildContext context, List<Map<String, dynamic>> g) {
    final p = pal(context);
    final f = g.first;
    const qk = ['qty', 'quantity', 'balance', 'onHand'];
    const mk = ['minQty', 'min', 'minStock', 'reorderLevel'];
    final total = g.fold<double>(0, (a, r) => a + num0(pick(r, qk)));
    final meta = ['typeName', 'brandName', 'modelName', 'binCode', 'unit']
        .map((k) => pick(f, [k]))
        .where((e) => e.isNotEmpty)
        .join(' / ');
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pick(f, ['productName', 'name', 'productId']),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (meta.isNotEmpty)
                Text(meta, style: TextStyle(color: p.mut, fontSize: 13)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtNum(total),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text('ລວມ', style: TextStyle(color: p.mut, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 8),
        for (final r in g) _branchRow(context, r, qk, mk),
      ]),
    );
  }

  Widget _branchRow(BuildContext context, Map<String, dynamic> r,
      List<String> qk, List<String> mk) {
    final p = pal(context);
    final q = num0(pick(r, qk)), min = num0(pick(r, mk));
    final low = min > 0 && q < min;
    final frac =
        min > 0 ? (q / (min * 4)).clamp(0.0, 1.0) : (q > 0 ? 1.0 : 0.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
            flex: 4,
            child: Text(pick(r, ['branchName', 'branchId']),
                style: const TextStyle(fontSize: 14))),
        Expanded(
          flex: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
                value: frac.toDouble(),
                minHeight: 5,
                backgroundColor: p.bd,
                color: low ? p.bad : p.bar),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(fmtNum(q),
              textAlign: TextAlign.end,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: low ? p.bad : p.tx)),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------------- History
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  dynamic _prod = 'all';
  late final Future<dynamic> _prods = Api.get('/products?limit=200');
  late Future<dynamic> _mv = _loadMv();
  Future<dynamic>? _bal;

  Future<dynamic> _loadMv() =>
      Api.get('/stock/movements${_prod == 'all' ? '' : '?productId=$_prod'}');

  void _pick(dynamic v) => setState(() {
        _prod = v ?? 'all';
        _mv = _loadMv();
        _bal =
            _prod == 'all' ? null : Api.get('/stock/balances?productId=$_prod');
      });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _pick(_prod),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          title: 'ສິນຄ້ານີ້ໄປຢູ່ໃສ? (ປະຫວັດການເຄື່ອນໄຫວ)',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FutureBuilder(
              future: _prods,
              builder: (c, s) {
                final items =
                    s.hasData ? asList(s.data) : <Map<String, dynamic>>[];
                return DropdownButtonFormField<dynamic>(
                  initialValue: _prod,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'ເລືອກສິນຄ້າ'),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('ທັງໝົດ')),
                    for (final it in items)
                      DropdownMenuItem(
                          value: it['id'],
                          child: Text(pick(it, ['name', 'productName', 'id']))),
                  ],
                  onChanged: _pick,
                );
              },
            ),
            if (_bal != null)
              futureBlock(_bal!, () => _pick(_prod), (d) {
                final rows = asList(d);
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final r in rows)
                      InfoChip(
                          pick(r, ['branchName', 'branchId']),
                          fmtNum(
                              num0(pick(r, ['qty', 'quantity', 'balance'])))),
                  ]),
                );
              }),
            const SizedBox(height: 8),
            futureBlock(_mv, () => _pick(_prod), (d) {
              final rows = asList(d);
              if (rows.isEmpty)
                return const Padding(
                    padding: EdgeInsets.all(8), child: Text('ຍັງບໍ່ມີລາຍການ'));
              return Column(children: [
                for (final m in rows.take(40)) moveRow(context, m)
              ]);
            }),
          ]),
        ),
      ]),
    );
  }
}

// ----------------------------------------------------- Receive / Issue
class StockFormPage extends StatefulWidget {
  final bool issue;
  final String? atmId;
  const StockFormPage({super.key, required this.issue, this.atmId});
  @override
  State<StockFormPage> createState() => _StockFormPageState();
}

class _StockFormPageState extends State<StockFormPage> {
  final _note = TextEditingController();
  final _ref = TextEditingController();
  final _invNo = TextEditingController();
  String _currency = 'USD';
  final _lines = <Line>[];
  double _total() => _lines.fold<double>(0, (a, l) => a + l.cost * l.qty);
  List<Map<String, dynamic>> _branches = [];
  dynamic _branchId;
  List<Map<String, dynamic>> _atms = [];
  late String? _atmId = widget.atmId;
  DateTime? _receiptDate;
  String _reason = 'sale';
  bool _busy = false;
  String? _error;
  late Future<dynamic> _recent = Api.get('/stock/movements');

  @override
  void initState() {
    super.initState();
    loadBranches().then((b) {
      if (!mounted) return;
      setState(() {
        _branches = b;
        final mine = Api.user?['branchId'];
        if (b.any((x) => x['id'] == mine)) _branchId = mine;
      });
    }).catchError((_) {});
    Api.get('/atms?limit=500').then((d) {
      if (!mounted) return;
      setState(() {
        _atms = [
          for (final m in asList(d))
            if (pick(m, ['atmStatus', 'status']).toLowerCase() == 'active') m,
        ];
      });
    }).catchError((_) {});
  }

  Future<void> _submit() async {
    if (_branchId == null)
      return setState(() {
        _error = 'ເລືອກສາຂາ';
      });
    if (_lines.isEmpty)
      return setState(() {
        _error = 'ເພີ່ມສິນຄ້າຢ່າງນ້ອຍ 1 ລາຍການ';
      });
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // NOTE: field names are inferred from the route list. Check them
      // against the DTOs of POST /stock/receive and /stock/issue.
      final body = {
        'branchId': _branchId,
        'items': [
          for (final l in _lines) {'productId': l.product['id'], 'qty': l.qty, if (!widget.issue && l.cost > 0) 'unitCost': l.cost}
        ],
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        if (_ref.text.trim().isNotEmpty) 'refNo': _ref.text.trim(),
        if (!widget.issue && _invNo.text.trim().isNotEmpty) 'invoiceNo': _invNo.text.trim(),
        if (!widget.issue) 'currency': _currency,
        if (!widget.issue && _total() > 0) 'totalAmount': _total(),
        if (widget.issue) 'reason': _reason,
        if (!widget.issue && _receiptDate != null && !_isToday(_receiptDate!))
          'receiptDate': _ymdOf(_receiptDate!),
        if (widget.issue && _atmId != null) 'atmId': _atmId,
      };
      await Api.post(widget.issue ? '/stock/issue' : '/stock/receive', body);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ບັນທຶກແລ້ວ')));
      setState(() {
        _lines.clear();
        _note.clear();
        _ref.clear();
        _invNo.clear();
        _atmId = widget.atmId;
        _receiptDate = null;
        _recent = Api.get('/stock/movements');
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
        });
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
        });
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  Future<int?> _askQty(String name) {
    final c = TextEditingController(text: '1');
    return showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'ຈຳນວນ'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('ຍົກເລີກ')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(c.text.trim());
              Navigator.pop(d, (n != null && n > 0) ? n : null);
            },
            child: const Text('ຕົກລົງ'),
          ),
        ],
      ),
    );
  }

  String _ymdOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  Future<void> _pickReceiptDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _receiptDate ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (d != null) setState(() => _receiptDate = d);
  }

  Widget _receiptDateField() {
    final back = _receiptDate != null && !_isToday(_receiptDate!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: _pickReceiptDate,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText:
                back ? 'ວັນທີຮັບເຂົ້າ (ນຳເຂົ້າຍ້ອນຫຼັງ)' : 'ວັນທີຮັບເຂົ້າ',
            suffixIcon: back
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _receiptDate = null))
                : const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(_ymdOf(_receiptDate ?? DateTime.now())),
        ),
      ),
    );
  }

  /// Scan product barcodes: scan -> enter quantity -> added to the list. Back to stop.
  Future<void> _scanProducts() async {
    while (mounted) {
      final raw = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => const BarcodeScanPage()));
      if (raw == null || raw.trim().isEmpty || !mounted) return;
      final code = raw.trim();
      try {
        final r =
            await Api.get('/products/by-barcode/${Uri.encodeComponent(code)}');
        final id = r is Map ? r['productId'] : null;
        if (id == null) {
          _snack('ບໍ່ພົບສິນຄ້າ barcode: $code');
          continue;
        }
        final name = '${r['name'] ?? id}';
        final q = await _askQty(name);
        if (q == null || !mounted) continue;
        setState(() {
          final i = _lines.indexWhere((l) => '${l.product['id']}' == '$id');
          if (i >= 0) {
            _lines[i].qty += q;
          } else {
            _lines.add(Line({'id': id, 'name': name}, q));
          }
        });
        _snack('+$q $name');
      } catch (e) {
        if (mounted)
          setState(() {
            _error = '$e';
          });
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppCard(
        title: widget.issue ? 'ເອົາສິນຄ້າອອກ' : 'ຮັບເຄື່ອງເຂົ້າ (GRN)',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          branchDropdown(
              'ສາຂາ',
              _branches,
              _branchId,
              (v) => setState(() {
                    _branchId = v;
                  })),
          if (widget.issue) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'ເຫດຜົນ'),
              items: [
                for (final e in reasons.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value))
              ],
              onChanged: (v) => setState(() {
                _reason = v ?? 'sale';
              }),
            ),
            const SizedBox(height: 12),
            if (widget.atmId != null)
              Text('ຕູ້ ATM: ${widget.atmId}',
                  style: const TextStyle(fontWeight: FontWeight.w600))
            else
              DropdownButtonFormField<String>(
                initialValue: _atmId,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'ຕູ້ ATM (ບໍ່ບັງຄັບ)'),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('— ບໍ່ລະບຸ —')),
                  for (final m in _atms)
                    DropdownMenuItem<String>(
                      value: pick(m, ['atmId']),
                      child: Text(
                        '${pick(m, ['atmId'])} · ${pick(m, [
                              'atmLocation',
                              'location'
                            ])}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _atmId = v;
                }),
              ),
          ],
          const SizedBox(height: 12),
          PoDropdown(
            value: _ref.text.isEmpty ? null : _ref.text,
            label: widget.issue ? 'ເລກ PO (ບໍ່ບັງຄັບ)' : 'ເລກ PO',
            onChanged: (v) => setState(() {
              _ref.text = v ?? '';
            }),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _note,
              decoration:
                  const InputDecoration(labelText: 'ໝາຍເຫດ (ບໍ່ບັງຄັບ)')),
          const SizedBox(height: 12),
          if (!widget.issue) _receiptDateField(),
          if (!widget.issue) ...[
            InvoiceImportButton(onDone: () {
              if (!mounted) return;
              setState(() {
                _recent = Api.get('/stock/movements');
              });
            }),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _scanProducts,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('ສະແກນ barcode ສິນຄ້າ'),
            ),
          ),
          const SizedBox(height: 8),
          LineEditor(_lines, showCost: !widget.issue),
          if (!widget.issue) ...[
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(labelText: 'ສະກຸນເງິນ'),
                  items: [
                    for (final c in const ['USD', 'LAK', 'THB', 'CNY'])
                      DropdownMenuItem(value: c, child: Text(c))
                  ],
                  onChanged: (v) => setState(() => _currency = v ?? 'USD'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                    controller: _invNo,
                    decoration: const InputDecoration(
                        labelText: 'ເລກ Invoice (ບໍ່ບັງຄັບ)')),
              ),
            ]),
            if (_lines.any((l) => l.cost > 0))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('ລວມເງິນ: ${_total().toStringAsFixed(2)} $_currency',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: p.bad))),
          const SizedBox(height: 14),
          saveButton(widget.issue ? 'ບັນທຶກເອົາອອກ' : 'ບັນທຶກຮັບເຂົ້າ', _busy,
              _submit),
          const SizedBox(height: 6),
          Text(widget.issue ? 'ຖ້າຈຳນວນຫຼາຍກວ່າສະຕັອກ ລະບົບຈະບໍ່ໃຫ້ບັນທຶກ' : '',
              style: TextStyle(color: p.mut, fontSize: 13)),
        ]),
      ),
      AppCard(
        title: widget.issue ? 'ເອົາອອກລ່າສຸດ' : 'ຮັບເຂົ້າລ່າສຸດ',
        child: futureBlock(
            _recent,
            () => setState(() {
                  _recent = Api.get('/stock/movements');
                }), (d) {
          final all = asList(d);
          var rows = <Map<String, dynamic>>[];
          if (widget.issue) {
            rows = all
                .where(
                    (m) => pick(m, ['type', 'movementType']).contains('issue'))
                .toList();
          } else {
            rows = all.where((m) {
              final t = pick(m, ['type', 'movementType']);
              return t.contains('purchase') || t.contains('receive');
            }).toList();
          }
          if (rows.isEmpty) rows = all;
          if (rows.isEmpty)
            return Text('ຍັງບໍ່ມີລາຍການ', style: TextStyle(color: p.mut));
          return Column(
              children: [for (final m in rows.take(5)) moveRow(context, m)]);
        }),
      ),
    ]);
  }
}

// -------------------------------------------------------------- Transfer
class TransferScreen extends StatefulWidget {
  final bool showForm, showList;
  final VoidCallback? onCreated;
  const TransferScreen(
      {super.key, this.showForm = true, this.showList = true, this.onCreated});
  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _lines = <Line>[];
  List<Map<String, dynamic>> _branches = [];
  dynamic _from, _to;
  bool _busy = false;
  String? _error;
  late Future<dynamic> _list = Api.get('/stock/transfers');

  @override
  void initState() {
    super.initState();
    loadBranches().then((b) {
      if (!mounted) return;
      setState(() {
        _branches = b;
        final mine = Api.user?['branchId'];
        if (b.any((x) => x['id'] == mine)) _from = mine;
      });
    }).catchError((_) {});
  }

  void _reload() => setState(() {
        _list = Api.get('/stock/transfers');
      });

  Future<void> _send() async {
    if (_from == null || _to == null)
      return setState(() {
        _error = 'ເລືອກສາຂາຕົ້ນທາງ ແລະ ປາຍທາງ';
      });
    if (_from == _to)
      return setState(() {
        _error = 'ສາຂາຕົ້ນທາງ ແລະ ປາຍທາງຕ້ອງຕ່າງກັນ';
      });
    if (_lines.isEmpty)
      return setState(() {
        _error = 'ເພີ່ມສິນຄ້າຢ່າງນ້ອຍ 1 ລາຍການ';
      });
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // NOTE: body field names are inferred; check against POST /stock/transfers.
      final bal = asList(
          await Api.get('/stock/balances?branchId=$_from&limit=2000'));
      final have = <String, num>{
        for (final b in bal)
          pick(b, ['productId']): num0(pick(b, ['qtyOnHand', 'qty']))
      };
      for (final l in _lines) {
        final h = have['${l.product['id']}'] ?? 0;
        if (l.qty > h) {
          throw 'ສະຕັອກບໍ່ພໍ: ${pick(l.product, ['name', 'productName'])} (ເຫຼືອ ${fmtNum(h.toDouble())})';
        }
      }
      await Api.post('/stock/transfers', {
        'fromBranchId': _from,
        'toBranchId': _to,
        'items': [
          for (final l in _lines) {'productId': l.product['id'], 'qty': l.qty}
        ],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ສົ່ງໂອນແລ້ວ')));
      setState(_lines.clear);
      _reload();
      widget.onCreated?.call();
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
        });
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
        });
    }
  }

  Future<void> _act(Map<String, dynamic> t, String action, String done) async {
    try {
      await Api.post('/stock/transfers/${t['id']}/$action', {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      _reload();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.showForm && Api.can('TRANSFER_SEND'))
          AppCard(
            title: 'ໂອນສິນຄ້າລະຫວ່າງສາຂາ',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              branchDropdown(
                  'ຈາກສາຂາ',
                  _branches,
                  _from,
                  (v) => setState(() {
                        _from = v;
                      })),
              const SizedBox(height: 12),
              branchDropdown(
                  'ໄປສາຂາ',
                  _branches,
                  _to,
                  (v) => setState(() {
                        _to = v;
                      })),
              const SizedBox(height: 12),
              LineEditor(_lines, branchId: _from),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: TextStyle(color: p.bad))),
              const SizedBox(height: 14),
              saveButton('ສົ່ງໂອນ', _busy, _send),
            ]),
          ),
        if (widget.showList)
        AppCard(
          title: 'ໃບໂອນ',
          child: futureBlock(_list, _reload, (d) {
            final rows = asList(d);
            if (rows.isEmpty)
              return Text('ຍັງບໍ່ມີລາຍການ', style: TextStyle(color: p.mut));
            return Column(
                children: [for (final t in rows) _transferRow(context, t)]);
          }),
        ),
      ]),
    );
  }

  Future<void> _addMore(Map<String, dynamic> t) async {
    final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => _TrfAddPage(
                trfId: pick(t, ['id']),
                fromBranchId: pick(t, ['fromBranchId']),
                ref: pick(t, ['transferNo', 'ref', 'id']))));
    if (ok == true) _reload();
  }

  Widget _transferRow(BuildContext context, Map<String, dynamic> t) {
    final p = pal(context);
    final st = pick(t, ['status', 'state']);
    final info = transferStatus[st];
    final items =
        t['items'] is List ? asList(t['items']) : <Map<String, dynamic>>[];
    final lines = items.isEmpty
        ? pick(t, ['productName'])
        : items
            .map((i) => '${pick(i, [
                      'productName',
                      'name',
                      'productId'
                    ])} × ${fmtNum(num0(i['qty'] ?? i['quantity']))}')
            .join('\n');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: p.bd))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(pick(t, ['ref', 'docNo', 'id']),
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Tag(info?[0] ?? st, info?[1] ?? kindOf(st)),
        ]),
        Text(
            '${pick(t, ['fromBranchName', 'fromBranchId'])} → ${pick(t, [
                  'toBranchName',
                  'toBranchId'
                ])}',
            style: TextStyle(color: p.mut, fontSize: 13)),
        if (lines.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(lines)),
        if (st == 'in_transit')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, children: [
              if (Api.can('TRANSFER_RECEIVE'))
                FilledButton(
                    onPressed: () => _act(t, 'receive', 'ຮັບເຄື່ອງແລ້ວ'),
                    child: const Text('ຮັບເຄື່ອງ')),
              if (Api.can('TRANSFER_SEND'))
                OutlinedButton(
                    onPressed: () => _act(t, 'cancel', 'ຍົກເລີກແລ້ວ'),
                    child: const Text('ຍົກເລີກ')),
              if (Api.can('TRANSFER_SEND'))
                OutlinedButton.icon(
                    onPressed: () => _addMore(t),
                    icon: const Icon(Icons.add),
                    label: const Text('ເພີ່ມສິນຄ້າ')),
            ]),
          ),
      ]),
    );
  }
}


/// Add products to a transfer that is still in transit.
class _TrfAddPage extends StatefulWidget {
  final String trfId, fromBranchId, ref;
  const _TrfAddPage(
      {required this.trfId, required this.fromBranchId, required this.ref});
  @override
  State<_TrfAddPage> createState() => _TrfAddPageState();
}

class _TrfAddPageState extends State<_TrfAddPage> {
  final List<Line> _lines = [];
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_lines.isEmpty) {
      setState(() => _error = 'ເພີ່ມສິນຄ້າຢ່າງນ້ອຍ 1 ລາຍການ');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.post('/stock/transfers/${widget.trfId}/items', {
        'items': [
          for (final l in _lines)
            {
              'productId': l.product['id'],
              'qty': l.qty,
              if (l.cost > 0) 'unitCost': l.cost
            }
        ]
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ເພີ່ມແລ້ວ')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: Text('ເພີ່ມສິນຄ້າ · ${widget.ref}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        LineEditor(_lines, showCost: true, branchId: widget.fromBranchId),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: p.bad))),
        const SizedBox(height: 12),
        saveButton('ບັນທຶກ', _busy, _save),
      ]),
    );
  }
}
