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
import 'pages.dart';
import 'po_info.dart';

/// ຮັບເຂົ້າ tab: recent receipts grouped by PO -> tap a PO to see its items.
class ReceiveHome extends StatefulWidget {
  const ReceiveHome({super.key});
  @override
  State<ReceiveHome> createState() => _ReceiveHomeState();
}

class _ReceiveHomeState extends State<ReceiveHome> {
  bool _adding = false;
  late Future<dynamic> _recent = Api.get('/stock/movements');

  // key names tried in order (adjust if your API uses other names)
  static const _poKeys = ['poNo', 'poNumber', 'po', 'poCode', 'refNo'];
  static const _grnKeys = ['grnNo', 'grn', 'docNo', 'refNo'];
  static const _qtyKeys = [
    'qty',
    'quantity',
    'qtyChange',
    'delta',
    'change',
    'qtyIn',
    'received',
    'amount'
  ];
  static const _dateKeys = ['receiptDate', 'createdAt', 'date'];

  void _reload() => setState(() {
        _recent = Api.get('/stock/movements');
      });

  void _backToList() {
    setState(() => _adding = false);
    _reload();
  }

  static const _labels = {
    'type': 'ປະເພດ',
    'movementType': 'ປະເພດ',
    'productName': 'ສິນຄ້າ',
    'name': 'ສິນຄ້າ',
    'branchName': 'ສາຂາ',
    'qty': 'ຈຳນວນ',
    'quantity': 'ຈຳນວນ',
    'grnNo': 'ເລກ GRN',
    'refNo': 'ເລກອ້າງອີງ',
    'poNo': 'PO',
    'note': 'ໝາຍເຫດ',
    'createdAt': 'ວັນທີ',
    'receiptDate': 'ວັນທີຮັບເຂົ້າ',
    'createdBy': 'ຜູ້ບັນທຶກ',
    'userName': 'ຜູ້ບັນທຶກ',
  };

  String _day(Map<String, dynamic> m) {
    final d = pick(m, _dateKeys);
    return d.length >= 10 ? d.substring(0, 10) : d;
  }

  /// Group movements by PO (falls back to GRN when a row has no PO).
  List<_PoGroup> _group(List<Map<String, dynamic>> rows) {
    final map = <String, _PoGroup>{};
    for (final m in rows) {
      final po = pick(m, _poKeys);
      final grn = pick(m, _grnKeys);
      final key =
          po.isNotEmpty ? 'PO:$po' : (grn.isNotEmpty ? 'GRN:$grn' : 'NONE');
      final g = map.putIfAbsent(
          key,
          () => _PoGroup(
                label: po.isNotEmpty
                    ? 'PO $po'
                    : (grn.isNotEmpty ? 'GRN $grn' : 'ບໍ່ມີ PO'),
                po: po,
                grn: grn,
                branch: pick(m, ['branchName', 'branchId']),
                date: _day(m),
              ));
      g.items.add(m);
      final q = num0(pick(m, _qtyKeys));
      final a = pick(m, ['amount']);
      g.total += q;
      g.amount += a.isNotEmpty ? num0(a) : q * num0(pick(m, ['unitCost']));
      if (g.currency.isEmpty) g.currency = pick(m, ['currency']);
    }
    return map.values.toList();
  }

  // ---- item detail: full page with bottom nav bar ----
  Future<bool?> _openDetail(Map<String, dynamic> m) async {
    final r = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _ItemPage(item: m)),
    );
    if (r == true && mounted) _reload();
    return r;
  }  // ---- PO detail: full page with its own bottom nav bar ----
  void _openPo(_PoGroup g) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PoPage(group: g, onItem: _openDetail),
      ),
    );
  }

  Widget _poRow(_PoGroup g) {
    final p = pal(context);
    return InkWell(
      onTap: () => _openPo(g),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                  [g.branch, g.grn, g.date]
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                  style: TextStyle(color: p.mut, fontSize: 12.5)),
              Text('${g.items.length} ລາຍການ',
                  style: TextStyle(color: p.mut, fontSize: 12.5)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('+${fmtNum(g.total)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            if (g.amount > 0)
              Text('${_money(g.amount)} ${g.currency}',
                  style: TextStyle(color: p.mut, fontSize: 12.5)),
          ]),
          const Icon(Icons.chevron_right),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);

    if (_adding) {
      return Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _backToList,
            icon: const Icon(Icons.arrow_back),
            label: const Text('ກັບໄປລາຍການຮັບເຂົ້າ'),
          ),
        ),
        const Expanded(child: StockFormPage(issue: false)),
      ]);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _adding = true),
        icon: const Icon(Icons.add),
        label: const Text('ເພີ່ມ'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            AppCard(
              title: 'ຮັບເຂົ້າລ່າສຸດ (ຕາມ PO)',
              child: futureBlock(_recent, _reload, (d) {
                final all = asList(d);
                var rows = all.where((m) {
                  final t = pick(m, ['type', 'movementType']);
                  return t.contains('purchase') || t.contains('receive');
                }).toList();
                if (rows.isEmpty) rows = all;
                if (rows.isEmpty) {
                  return Text('ຍັງບໍ່ມີລາຍການ', style: TextStyle(color: p.mut));
                }
                final groups = _group(rows);
                return Column(children: [
                  for (var i = 0; i < groups.length && i < 30; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _poRow(groups[i]),
                  ],
                ]);
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _PoGroup {
  final String label, po, grn, branch, date;
  final List<Map<String, dynamic>> items = [];
  double total = 0;
  double amount = 0;
  String currency = '';
  _PoGroup(
      {required this.label,
      required this.po,
      required this.grn,
      required this.branch,
      required this.date});
}

class _PoPage extends StatefulWidget {
  final _PoGroup group;
  final Future<bool?> Function(Map<String, dynamic>) onItem;
  const _PoPage({required this.group, required this.onItem});
  @override
  State<_PoPage> createState() => _PoPageState();
}

class _PoPageState extends State<_PoPage> {
  int _tab = 0;

  Widget _itemRow(Map<String, dynamic> m) {
    final p = pal(context);
    final qty = num0(pick(m, ['qtyChange', 'qty', 'quantity', 'delta']));
    final cost = num0(pick(m, ['unitCost']));
    final aStr = pick(m, ['amount']);
    final amt = aStr.isNotEmpty ? num0(aStr) : qty * cost;
    final cur = pick(m, ['currency']);
    final name = pick(m, ['productName', 'name', 'productId']);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(cost > 0 ? '${_money(cost)} × ${fmtNum(qty)}' : 'ຍັງບໍ່ມີລາຄາ',
                  style: TextStyle(color: p.mut, fontSize: 12.5)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(amt > 0 ? '${_money(amt)} $cur' : '-',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('+${fmtNum(qty)}',
                style: TextStyle(color: p.mut, fontSize: 12.5)),
          ]),
        ]),
      ),
      const Divider(height: 1),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final p = pal(context);
    return Scaffold(
      appBar: _tab == 1 ? null : AppBar(
        title: Text(g.label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _tab == 0
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                Text(
                    [g.branch, g.grn, g.date]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    style: TextStyle(color: p.mut, fontSize: 13)),
                const SizedBox(height: 4),
                Text('${g.items.length} ລາຍການ · ລວມ +${fmtNum(g.total)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                if (g.amount > 0)
                  Text('ລວມເງິນຊື້: ${_money(g.amount)} ${g.currency}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                if (pick(g.items.first, ['totalAmount']).isNotEmpty)
                  Text(
                      'ມູນຄ່າ Invoice: ${_money(num0(pick(g.items.first, ['totalAmount'])))} ${g.currency}',
                      style: TextStyle(color: p.mut, fontSize: 13)),                const Divider(height: 24),
                for (final m in g.items)
                  InkWell(
                    onTap: () async {
                      final r = await widget.onItem(m);
                      if (r == true && mounted) Navigator.pop(context);
                    },
                    child: _itemRow(m),
                  ),
              ],
            )
          : _tab == 1
              ? _PoFormTab(poNo: g.po)
              : _PoPayTab(poNo: g.po, currency: g.currency),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.list_alt_outlined), label: 'ລາຍການ'),
          NavigationDestination(
              icon: Icon(Icons.info_outline), label: 'ຂໍ້ມູນ PO'),
          NavigationDestination(
              icon: Icon(Icons.payments_outlined), label: 'ຊຳລະເງິນ'),
        ],
      ),
    );
  }
}

/// PO tab: loads the PO by number and shows the normal PO form page.
class _PoFormTab extends StatefulWidget {
  final String poNo;
  const _PoFormTab({required this.poNo});
  @override
  State<_PoFormTab> createState() => _PoFormTabState();
}

class _PoFormTabState extends State<_PoFormTab> {
  late final Future<Map<String, dynamic>> _f = _load();

  Future<Map<String, dynamic>> _load() async {
    if (widget.poNo.isEmpty) throw 'ບໍ່ມີເລກ PO';
    final list = asList(await Api.get(
        '/purchase-orders?q=${Uri.encodeQueryComponent(widget.poNo)}'));
    return list.firstWhere((m) => pick(m, ['poNo']) == widget.poNo,
        orElse: () => throw 'ບໍ່ພົບ PO ${widget.poNo}');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (_, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) return Center(child: Text('${s.error}'));
        return PoFormPage(row: s.data!);
      },
    );
  }
}

/// Item page (one received line): ລາຍລະອຽດ / ໃບແຈ້ງໜີ້ tabs.
class _ItemPage extends StatefulWidget {
  final Map<String, dynamic> item;
  const _ItemPage({required this.item});
  @override
  State<_ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<_ItemPage> {
  int _tab = 0;

  Widget _row(String k, String v) {
    final p = pal(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(k, style: TextStyle(color: p.mut))),
        Expanded(child: Text(v.isEmpty ? '-' : v)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.item;
    final name = pick(m, ['productName', 'name', 'productId']);
    final qty = pick(m, ['qtyChange', 'qty', 'quantity', 'delta']);
    final d = pick(m, ['movementDate', 'receiptDate', 'createdAt', 'date']);
    return Scaffold(
      appBar: AppBar(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _tab == 2
          ? _ItemEditForm(item: m)
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: _tab == 0
            ? [
                AppCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('ສິນຄ້າ', name),
                        _row('ຈຳນວນ', qty.isEmpty ? '' : '+$qty'),
                        _row('ສາຂາ', pick(m, ['branchName', 'branchId'])),
                        _row('PO', pick(m, ['poNo'])),
                        _row('ເລກ GRN', pick(m, ['refNo', 'grnNo'])),
                        _row('ປະເພດ', pick(m, ['movementType', 'type'])),
                        _row('ວັນທີ', d.length >= 10 ? d.substring(0, 10) : d),
                        _row('ຜູ້ບັນທຶກ', pick(m, ['userName', 'createdBy'])),
                      ]),
                ),
              ]
            : [
                AppCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('ເລກ Invoice', pick(m, ['invoiceNo'])),
                        _row('ວັນທີ Invoice', pick(m, ['invoiceDate'])),
                        _row('P/N', pick(m, ['partNo'])),
                        _row('ລາຍລະອຽດ', pick(m, ['description'])),
                        _row('ແຫຼ່ງກຳເນີດ', pick(m, ['origin'])),
                        _row('ວັດສະດຸ', pick(m, ['material'])),
                        _row('ລາຄາຕໍ່ໜ່ວຍ', pick(m, ['unitCost'])),
                        _row('ຈຳນວນເງິນ', pick(m, ['amount'])),
                        _row('ສະກຸນເງິນ', pick(m, ['currency'])),
                        _row('ຄ່າຂົນສົ່ງ', pick(m, ['freightCost'])),
                      ]),
                ),
              ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.info_outline), label: 'ລາຍລະອຽດ'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: 'ໃບແຈ້ງໜີ້'),
          NavigationDestination(
              icon: Icon(Icons.edit_outlined), label: 'ແກ້ໄຂ'),
        ],
      ),
    );
  }
}

/// Edit tab: one received line + the invoice info of its GRN.
class _ItemEditForm extends StatefulWidget {
  final Map<String, dynamic> item;
  const _ItemEditForm({required this.item});
  @override
  State<_ItemEditForm> createState() => _ItemEditFormState();
}

class _ItemEditFormState extends State<_ItemEditForm> {
  static const _itemKeys = [
    'partNo',
    'description',
    'origin',
    'material',
    'unitCost',
    'amount'
  ];
  static const _headKeys = [
    'poNo',
    'invoiceNo',
    'invoiceDate',
    'currency',
    'freightCost',
    'totalAmount'
  ];
  static const _num = {'unitCost', 'amount', 'freightCost', 'totalAmount'};
  static const _labels = {
    'partNo': 'P/N',
    'description': 'ລາຍລະອຽດ',
    'origin': 'ແຫຼ່ງກຳເນີດ',
    'material': 'ວັດສະດຸ',
    'unitCost': 'ລາຄາຕໍ່ໜ່ວຍ',
    'amount': 'ຈຳນວນເງິນ',
    'poNo': 'ເລກ PO',
    'invoiceNo': 'ເລກ Invoice',
    'invoiceDate': 'ວັນທີ Invoice (YYYY-MM-DD)',
    'currency': 'ສະກຸນເງິນ',
    'freightCost': 'ຄ່າຂົນສົ່ງ',
    'totalAmount': 'ມູນຄ່າລວມ Invoice',
  };

  late final Map<String, TextEditingController> _c = {
    for (final k in [..._itemKeys, ..._headKeys])
      k: TextEditingController(text: _init(k))
  };
  bool _busy = false;
  String? _error;

  String _init(String k) {
    final v = pick(widget.item, [k]);
    return k == 'invoiceDate' && v.length >= 10 ? v.substring(0, 10) : v;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String k) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _c[k],
          keyboardType: _num.contains(k)
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(labelText: _labels[k]),
        ),
      );

  Future<void> _save() async {
    final itemId = pick(widget.item, ['itemId']);
    final grnId = pick(widget.item, ['grnId']);
    if (itemId.isEmpty || grnId.isEmpty) {
      setState(() => _error = 'ບໍ່ພົບລະຫັດລາຍການ (ຕ້ອງ restart server ກ່ອນ)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.put('/imports/items/$itemId',
          {for (final k in _itemKeys) k: _c[k]!.text.trim()});
      await Api.put('/imports/receipts/$grnId',
          {for (final k in _headKeys) k: _c[k]!.text.trim()});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ບັນທຶກແລ້ວ')));
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        AppCard(
          title: 'ລາຍການນີ້',
          child: Column(children: [for (final k in _itemKeys) _field(k)]),
        ),
        AppCard(
          title: 'ໃບແຈ້ງໜີ້ (ມີຜົນກັບທຸກລາຍການໃນ GRN ນີ້)',
          child: Column(children: [for (final k in _headKeys) _field(k)]),
        ),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: p.bad))),
        const SizedBox(height: 12),
        saveButton('ບັນທຶກ', _busy, _save),
      ],
    );
  }
}

String _money(num v) {
  final parts = v.toStringAsFixed(2).split('.');
  final neg = parts[0].startsWith('-');
  final i = neg ? parts[0].substring(1) : parts[0];
  final b = StringBuffer();
  for (var k = 0; k < i.length; k++) {
    if (k > 0 && (i.length - k) % 3 == 0) b.write(',');
    b.write(i[k]);
  }
  return '${neg ? '-' : ''}$b.${parts[1]}';
}

String _ymd2(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Payments tab of a PO: total / paid / remaining + every installment, and an add button.
class _PoPayTab extends StatefulWidget {
  final String poNo;
  final String currency;
  const _PoPayTab({required this.poNo, required this.currency});
  @override
  State<_PoPayTab> createState() => _PoPayTabState();
}

class _PoPayTabState extends State<_PoPayTab> {
  late Future<dynamic> _f = _load();

  Future<dynamic> _load() {
    if (widget.poNo.isEmpty) return Future<dynamic>.error('ບໍ່ມີເລກ PO');
    return Api.get(
        '/po-payments?poNo=${Uri.encodeQueryComponent(widget.poNo)}');
  }

  void _reload() => setState(() {
        _f = _load();
      });

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _add(Map<String, dynamic> s) async {
    final amt = TextEditingController();
    final note = TextEditingController();
    var date = DateTime.now();
    var cur = pick(s, ['currency']);
    if (cur.isEmpty) cur = widget.currency.isEmpty ? 'USD' : widget.currency;
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('ເພີ່ມການຊຳລະ'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: amt,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'ຈຳນວນເງິນ ($cur)'),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final x = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100));
                  if (x != null) setS(() => date = x);
                },
                child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'ວັນທີຊຳລະ'),
                    child: Text(_ymd2(date))),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: note,
                  decoration:
                      const InputDecoration(labelText: 'ໝາຍເຫດ (ບໍ່ບັງຄັບ)')),
              if (err != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(err!, style: const TextStyle(color: Colors.red))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('ຍົກເລີກ')),
            FilledButton(
              onPressed: () {
                final a = double.tryParse(amt.text.replaceAll(',', '').trim());
                if (a == null || a <= 0) {
                  setS(() => err = 'ໃສ່ຈຳນວນເງິນໃຫ້ຖືກ');
                  return;
                }
                Navigator.pop(d, true);
              },
              child: const Text('ບັນທຶກ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/po-payments', {
        'poNo': widget.poNo,
        'payDate': _ymd2(date),
        'amount': double.parse(amt.text.replaceAll(',', '').trim()),
        'currency': cur,
        'note': note.text.trim(),
      });
      if (!mounted) return;
      _snack('ບັນທຶກການຊຳລະແລ້ວ');
      _reload();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ລຶບການຊຳລະນີ້?'),
        content: Text(
            '${_money(num0(m['amount']))} ${pick(m, ['currency'])} · ${pick(m, ['payDate'])}'),
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
    if (go != true) return;
    try {
      await Api.delete('/po-payments/${pick(m, ['id'])}');
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Widget _kv(String k, String v, Color? c) => Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(color: pal(context).mut, fontSize: 12.5)),
        Text(v,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16, color: c)),
      ]);

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return FutureBuilder<dynamic>(
      future: _f,
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('${snap.error}')));
        }
        final s = snap.data is Map
            ? Map<String, dynamic>.from(snap.data as Map)
            : <String, dynamic>{};
        final cur = pick(s, ['currency']);
        final total = num0(s['total']);
        final paid = num0(s['paid']);
        final remaining = num0(s['remaining']);
        final pays = asList(s['payments']);
        final frac = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
        final done = total > 0 && remaining <= 0.004;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ລວມທີ່ຕ້ອງຈ່າຍ',
                        style: TextStyle(color: p.mut, fontSize: 12.5)),
                    Text('${_money(total)} $cur',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 22)),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                        value: frac.toDouble(), minHeight: 6),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _kv('ຊຳລະແລ້ວ', '${_money(paid)} $cur', p.ok)),
                      Expanded(
                          child: _kv('ຄ້າງຈ່າຍ', '${_money(remaining)} $cur',
                              done ? p.ok : p.bad)),
                    ]),
                    if (done)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('ຊຳລະຄົບແລ້ວ',
                              style: TextStyle(
                                  color: p.ok, fontWeight: FontWeight.w700))),
                  ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => _add(s),
                icon: const Icon(Icons.add),
                label: const Text('ເພີ່ມການຊຳລະ'),
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              title: 'ປະຫວັດການຊຳລະ (${pays.length} ຄັ້ງ)',
              child: pays.isEmpty
                  ? Text('ຍັງບໍ່ມີການຊຳລະ', style: TextStyle(color: p.mut))
                  : Column(children: [
                      for (var i = 0; i < pays.length; i++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: CircleAvatar(
                              radius: 14, child: Text('${i + 1}')),
                          title: Text(
                              '${_money(num0(pays[i]['amount']))} ${pick(pays[i], ['currency'])}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              [
                                pick(pays[i], ['payDate']),
                                pick(pays[i], ['note']),
                                pick(pays[i], ['userName']),
                                if (cur.isNotEmpty &&
                                    pick(pays[i], ['currency']).isNotEmpty &&
                                    pick(pays[i], ['currency']) != cur)
                                  'ບໍ່ລວມໃນຍອດ',
                              ].where((e) => e.isNotEmpty).join(' · '),
                              style: TextStyle(color: p.mut, fontSize: 12)),
                          trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: p.bad),
                              onPressed: () => _delete(pays[i])),
                        ),
                    ]),
            ),
          ],
        );
      },
    );
  }
}
