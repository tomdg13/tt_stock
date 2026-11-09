import "po_actual_ui.dart";
import "po_excel.dart";
import 'product_images.dart';
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

  Map<String, dynamic> _actual = {};

  @override
  void initState() {
    super.initState();
    _loadActual();
  }

  Future<void> _loadActual() async {
    try {
      final d = await Api.get('/po-payments/actual');
      if (!mounted) return;
      setState(() => _actual = d is Map ? Map<String, dynamic>.from(d) : {});
    } catch (_) {}
  }

  void _reload() {
    setState(() {
      _recent = Api.get('/stock/movements');
    });
    _loadActual();
  }

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
    final inv = <String, Map<String, double>>{};
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
      final invTot = num0(pick(m, ['totalAmount'])).toDouble();
      final invGrn = pick(m, ['grnId']);
      if (invTot > 0 && invGrn.isNotEmpty) {
        (inv[key] ??= <String, double>{})[invGrn] = invTot;
      }
      final q = num0(pick(m, _qtyKeys));
      final a = pick(m, ['amount']);
      g.total += q;
      g.amount += a.isNotEmpty ? num0(a) : q * num0(pick(m, ['unitCost']));
      if (g.currency.isEmpty) g.currency = pick(m, ['currency']);
    }
    inv.forEach((k, v) {
      final s = v.values.fold<double>(0, (a, b) => a + b);
      if (s > 0 && map[k] != null) map[k]!.amount = s;
    });
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
  } // ---- PO detail: full page with its own bottom nav bar ----

  void _openPo(_PoGroup g) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PoPage(group: g, onItem: _openDetail),
      ),
    ).then((_) => _loadActual());
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
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (g.amount > 0)
              Text('${_money(g.amount)} ${g.currency}',
                  style: TextStyle(color: p.mut, fontSize: 12.5)),
            if (g.po.isNotEmpty && _actual[g.po] is List)
              for (final a in (_actual[g.po] as List))
                Text('ຈ່າຍຕົວຈິງ ${_money(num0(a['total']))} ${a['currency']}',
                    style: TextStyle(
                        color: p.ok,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
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
  Map<String, String> _imgById = {};
  Map<String, String> _imgByName = {};
  Map<String, double> _actualLak = {};
  String _actualInfo = '';

  @override
  void initState() {
    super.initState();
    _loadImgs();
    _loadActualLak();
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
      debugPrint('[PO] product images loaded: ${byId.length}');
      if (mounted) {
        setState(() {
          _imgById = byId;
          _imgByName = byName;
        });
      }
    } catch (e) {
      debugPrint('[PO] load product images failed: $e');
    }
  }

  Widget _thumb(Map<String, dynamic> m, String name) {
    final p = pal(context);
    final v = _imgById[pick(m, ['productId'])] ??
        _imgByName[name.toLowerCase()] ??
        '';
    final ph = Container(
      width: 48,
      height: 48,
      decoration:
          BoxDecoration(color: p.bd, borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.image_outlined, color: p.mut),
    );
    final url = productImageUrl(v);
    if (url.isEmpty) return ph;
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (c) => Dialog(
          child: InteractiveViewer(
            child: Image.network(url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Icon(Icons.broken_image_outlined))),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ph),
      ),
    );
  }

  Future<void> _loadActualLak() async {
    try {
      final d = await Api.get(
          '/po-actual?poNo=${Uri.encodeQueryComponent(widget.group.po)}');
      final list = asList(d);
      if (list.isEmpty) return;
      final last = Map<String, dynamic>.from(list.first as Map);
      final it = await Api.get('/po-actual/${last['id']}');
      final m = <String, double>{};
      for (final r in asList(it)) {
        if (r is Map) {
          final k = num0('${r['itemId']}').toInt();
          m['$k'] = num0('${r['actualLak']}').toDouble();
        }
      }
      final info =
          'ມູນຄ່ານຳໃຊ້ v${last['versionNo']}: ${_lakFmt(last['totalLak'])} LAK · ${last['uploadedByName'] ?? ''}';
      if (mounted == false) return;
      setState(() {
        _actualLak = m;
        _actualInfo = info;
      });
    } catch (e) {
      debugPrint('[PO] load actual lak failed: $e');
    }
  }

  Future<void> _addProduct() async {
    final grnId = pick(widget.group.items.first, ['grnId']);
    if (grnId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ບໍ່ພົບລະຫັດ GRN')));
      return;
    }
    final prod = await pickProduct(context);
    if (prod == null || !mounted) return;
    final qty = TextEditingController(text: '1');
    final cost = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(pick(prod, ['name', 'productName', 'id'])),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: qty,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'ຈຳນວນ'),
          ),
          TextField(
            controller: cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'ລາຄາຕໍ່ໜ່ວຍ'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('ບັນທຶກ')),
        ],
      ),
    );
    final q = double.tryParse(qty.text.replaceAll(',', '')) ?? 0;
    final c = double.tryParse(cost.text.replaceAll(',', '')) ?? 0;
    qty.dispose();
    cost.dispose();
    if (ok != true || !mounted) return;
    if (q <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ຈຳນວນຕ້ອງຫຼາຍກວ່າ 0')));
      return;
    }
    try {
      await Api.post('/imports/receipts/$grnId/items',
          {'productId': prod['id'], 'qty': q, 'unitCost': c});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ບັນທຶກແລ້ວ')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _editFreight() async {
    final g = widget.group;
    final first = g.items.first;
    final grnId = pick(first, ['grnId']);
    void toast(String t) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    if (grnId.isEmpty) {
      toast('ບໍ່ພົບລະຫັດ GRN');
      return;
    }
    final ctl = TextEditingController(text: pick(first, ['freightCost']));
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ແກ້ໄຂຄ່າຂົນສົ່ງ'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ລວມລາຍການ: ${_money(g.amount)} ${g.currency}'),
              const SizedBox(height: 8),
              TextField(
                controller: ctl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: 'ຄ່າຂົນສົ່ງ (${g.currency})'),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctl.text),
              child: const Text('ບັນທຶກ')),
        ],
      ),
    );
    if (text == null || !mounted) return;
    final fr = double.tryParse(text.replaceAll(',', '').trim());
    if (fr == null || fr < 0) {
      toast('ຕົວເລກບໍ່ຖືກຕ້ອງ');
      return;
    }
    final total = g.amount + fr;
    try {
      final inv = pick(first, ['invoiceDate']);
      await Api.put('/imports/receipts/$grnId', {
        'poNo': pick(first, ['poNo']),
        'invoiceNo': pick(first, ['invoiceNo']),
        'invoiceDate': inv.length >= 10 ? inv.substring(0, 10) : inv,
        'currency': pick(first, ['currency']),
        'freightCost': fr.toString(),
        'totalAmount': total.toStringAsFixed(2),
      });
      for (final it in g.items) {
        it['freightCost'] = fr;
        it['totalAmount'] = total;
      }
      if (mounted) setState(() {});
      toast('ບັນທຶກແລ້ວ');
    } catch (e) {
      debugPrint('[PO] edit freight failed: $e');
      toast('ບັນທຶກບໍ່ສຳເລັດ: $e');
    }
  }

  Widget _itemRow(Map<String, dynamic> m) {
    final p = pal(context);
    final qty = num0(pick(m, ['qtyChange', 'qty', 'quantity', 'delta']));
    final cost = num0(pick(m, ['unitCost']));
    final aStr = pick(m, ['amount']);
    final amt = aStr.isNotEmpty ? num0(aStr) : qty * cost;
    final cur = pick(m, ['currency']);
    final name = pick(m, ['productName', 'name', 'productId']);
    final lakV = _actualLak['${num0(pick(m, ['itemId'])).toInt()}'];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _thumb(m, name),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                  cost > 0
                      ? '${_money(cost)} × ${fmtNum(qty)}'
                      : 'ຍັງບໍ່ມີລາຄາ',
                  style: TextStyle(color: p.mut, fontSize: 12.5)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(amt > 0 ? '${_money(amt)} $cur' : '-',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (lakV != null)
              Text('${_lakFmt(lakV)} LAK',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.primary)),
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
      appBar: _tab == 1
          ? null
          : AppBar(
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
                Row(children: [
                  Expanded(
                      child: Text(
                          'ຄ່າຂົນສົ່ງ: ${_money(num0(pick(g.items.first, [
                                'freightCost'
                              ])))} ${g.currency}',
                          style: TextStyle(color: p.mut, fontSize: 13))),
                  IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'ແກ້ໄຂຄ່າຂົນສົ່ງ',
                      visualDensity: VisualDensity.compact,
                      onPressed: _editFreight),
                ]),
                if (pick(g.items.first, ['totalAmount']).isNotEmpty)
                  Text(
                      'ມູນຄ່າ Invoice: ${_money(num0(pick(g.items.first, [
                            'totalAmount'
                          ])))} ${g.currency}',
                      style: TextStyle(color: p.mut, fontSize: 13)),
                if (_actualInfo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_actualInfo,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.primary)),
                  ),
                const Divider(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addProduct,
                    icon: const Icon(Icons.add),
                    label: const Text('ເພີ່ມສິນຄ້າ'),
                  ),
                ),
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
        onDestinationSelected: (i) {
          if (i == 4) {
            poActualMenu(context, widget.group.po).then((_) {
              if (mounted) _loadActualLak();
            });
            return;
          }
          if (i == 3) {
            _exportPoExcel(context, widget.group);
            return;
          }
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.list_alt_outlined), label: 'ລາຍການ'),
          NavigationDestination(
              icon: Icon(Icons.info_outline), label: 'ຂໍ້ມູນ PO'),
          NavigationDestination(
              icon: Icon(Icons.payments_outlined), label: 'ຊຳລະເງິນ'),
          NavigationDestination(
              icon: Icon(Icons.download_outlined), label: "Excel"),
          NavigationDestination(
              icon: Icon(Icons.upload_file_outlined), label: "Upload"),
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
                              _row('ວັນທີ',
                                  d.length >= 10 ? d.substring(0, 10) : d),
                              _row('ຜູ້ບັນທຶກ',
                                  pick(m, ['userName', 'createdBy'])),
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
  Map<String, dynamic> _fx = {};
  String _fxDate = '';

  @override
  void initState() {
    super.initState();
    _loadFx();
  }

  Future<void> _loadFx() async {
    try {
      final d = await Api.get('/po-payments/fx');
      if (!mounted || d is! Map) return;
      setState(() {
        _fx = d['rates'] is Map
            ? Map<String, dynamic>.from(d['rates'] as Map)
            : {};
        _fxDate = '${d['rateDate'] ?? ''}';
      });
    } catch (_) {}
  }

  // 1 [poCur] = ? [pc] from the latest BOL table (sell side of poCur, buy side of pc)
  double _fxRate(String poCur, String pc) {
    double lak(String c, String side) {
      if (c == 'LAK') return 1;
      final m = _fx[c];
      return m is Map ? num0(m[side]).toDouble() : 0;
    }

    final a = lak(poCur, 'sell');
    final b = lak(pc, 'buy');
    return (a > 0 && b > 0) ? a / b : 0;
  }

  Widget _fxHint(String poCur, String pc, void Function(String) use) {
    final r = _fxRate(poCur, pc);
    if (r <= 0 || poCur == pc) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextButton(
          onPressed: () => use(r.toStringAsFixed(2)),
          child: Text(
              'ອັດຕາ BOL $_fxDate: 1 $poCur = ${_money(r)} $pc (ແຕະເພື່ອໃຊ້)'),
        ),
        Text('ແຫຼ່ງ: Bank of the Lao PDR · allratestoday.com',
            style: TextStyle(color: pal(context).mut, fontSize: 11)),
      ]),
    );
  }

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
    final poCur = cur;
    final fx = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('ເພີ່ມການຊຳລະ'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final c in <String>{'USD', 'THB', 'LAK', cur})
                    ButtonSegment(value: c, label: Text(c)),
                ],
                selected: {cur},
                onSelectionChanged: (x) => setS(() => cur = x.first),
              ),
              if (cur != poCur) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: fx,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(labelText: '1 $poCur = ? $cur'),
                ),
                _fxHint(poCur, cur, (v) => setS(() => fx.text = v)),
                Builder(builder: (_) {
                  final a =
                      double.tryParse(amt.text.replaceAll(',', '').trim()) ?? 0;
                  final r =
                      double.tryParse(fx.text.replaceAll(',', '').trim()) ?? 0;
                  if (a <= 0 || r <= 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('≈ ${_money(a / r)} $poCur',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  );
                }),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: amt,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setS(() {}),
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
                    child:
                        Text(err!, style: const TextStyle(color: Colors.red))),
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
                if (cur != poCur &&
                    !((double.tryParse(fx.text.replaceAll(',', '').trim()) ??
                            0) >
                        0)) {
                  setS(() => err = 'ໃສ່ອັດຕາແລກປ່ຽນ');
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
    final amtV = double.parse(amt.text.replaceAll(',', '').trim());
    final fxV = double.tryParse(fx.text.replaceAll(',', '').trim()) ?? 0;
    final poAmt = cur == poCur ? amtV : amtV / fxV;
    final rem = num0(s['remaining']).toDouble();
    var allowOver = false;
    if (poAmt > rem + 0.005) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('ຈຳນວນເກີນຍອດຄ້າງຈ່າຍ'),
          content: Text(
              'ຄ້າງຈ່າຍ ${_money(rem)} $poCur\nຈະຊຳລະ ${_money(poAmt)} $poCur\n\nຢືນຢັນການຈ່າຍເກີນບໍ?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('ຍົກເລີກ')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('ຢືນຢັນ')),
          ],
        ),
      );
      if (go != true) return;
      allowOver = true;
    }
    try {
      await Api.post('/po-payments', {
        'poNo': widget.poNo,
        'payDate': _ymd2(date),
        'amount': amtV,
        'currency': cur,
        if (cur != poCur) 'fxRate': fxV,
        if (allowOver) 'allowOver': true,
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
        content: Text('${_money(num0(m['amount']))} ${pick(m, [
              'currency'
            ])} · ${pick(m, ['payDate'])}'),
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

  String _pctTxt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _addExtra(Map<String, dynamic> s) async {
    final p = pal(context);
    final base = num0(s['baseTotal']).toDouble();
    var cur = pick(s, ['currency']);
    if (cur.isEmpty) cur = widget.currency.isEmpty ? 'USD' : widget.currency;
    final label = TextEditingController(text: 'ພາສີ');
    final val = TextEditingController();
    final fx = TextEditingController();
    var isPct = true;
    var xcur = cur;
    var isDisc = false;
    String? err;
    final presets = <List<Object>>[
      ['ພາສີ (VAT)', true, false],
      ['ຄ່າຂົນສົ່ງ', false, false],
      ['ຄ່າທຳນຽມ', false, false],
      ['ສ່ວນຫຼຸດ', true, true],
      ['ອື່ນໆ', false, false],
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (ctx, setS) {
          final v = double.tryParse(val.text.replaceAll(',', '').trim()) ?? 0;
          final diff = !isPct && xcur != cur;
          final rate = double.tryParse(fx.text.replaceAll(',', '').trim()) ?? 0;
          final raw =
              isPct ? base * v / 100 : (diff ? (rate > 0 ? v / rate : 0.0) : v);
          final delta = ((isDisc ? -raw : raw) * 100).round() / 100;
          return AlertDialog(
            title: const Text('ເພີ່ມຄ່າໃຊ້ຈ່າຍອື່ນ'),
            content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 6, children: [
                      for (final pr in presets)
                        ActionChip(
                          label: Text(pr[0] as String),
                          onPressed: () => setS(() {
                            label.text = pr[0] as String;
                            isPct = pr[1] as bool;
                            isDisc = pr[2] as bool;
                          }),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    TextField(
                        controller: label,
                        decoration:
                            const InputDecoration(labelText: 'ຊື່ລາຍການ')),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: [
                        const ButtonSegment(value: true, label: Text('%')),
                        const ButtonSegment(
                            value: false, label: Text('ຈຳນວນເງິນ')),
                      ],
                      selected: {isPct},
                      onSelectionChanged: (x) => setS(() => isPct = x.first),
                    ),
                    if (!isPct) ...[
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          for (final c in <String>{'USD', 'THB', 'LAK', cur})
                            ButtonSegment(value: c, label: Text(c)),
                        ],
                        selected: {xcur},
                        onSelectionChanged: (x) => setS(() => xcur = x.first),
                      ),
                      if (xcur != cur) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: fx,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setS(() {}),
                          decoration:
                              InputDecoration(labelText: '1 $cur = ? $xcur'),
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: val,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setS(() {}),
                      decoration: InputDecoration(
                          labelText: isPct ? 'ອັດຕາ (%)' : 'ຈຳນວນເງິນ ($xcur)'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('ເປັນສ່ວນຫຼຸດ (ຫັກອອກ)'),
                      value: isDisc,
                      onChanged: (x) => setS(() => isDisc = x),
                    ),
                    if (base > 0 && v > 0)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: p.soft,
                            borderRadius: BorderRadius.circular(8)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ລາຄາ PO: ${_money(base)} $cur'),
                              Text(
                                  '${delta < 0 ? '-' : '+'}${_money(delta.abs())} $cur'),
                              Text(
                                  'ຕົ້ນທຶນລວມຕົວຈິງ: ${_money(base + delta)} $cur',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ]),
                      ),
                    if (err != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(err!,
                              style: const TextStyle(color: Colors.red))),
                  ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('ຍົກເລີກ')),
              FilledButton(
                onPressed: () {
                  final x =
                      double.tryParse(val.text.replaceAll(',', '').trim());
                  if (label.text.trim().isEmpty) {
                    setS(() => err = 'ໃສ່ຊື່ລາຍການ');
                    return;
                  }
                  if (x == null || x <= 0) {
                    setS(() => err = 'ໃສ່ຈຳນວນໃຫ້ຖືກ');
                    return;
                  }
                  if (!isPct &&
                      xcur != cur &&
                      !((double.tryParse(fx.text.replaceAll(',', '').trim()) ??
                              0) >
                          0)) {
                    setS(() => err = 'ໃສ່ອັດຕາແລກປ່ຽນ');
                    return;
                  }
                  if (isPct && x > 100) {
                    setS(() => err = 'ເປີເຊັນຕ້ອງບໍ່ເກີນ 100');
                    return;
                  }
                  Navigator.pop(d, true);
                },
                child: const Text('ບັນທຶກ'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/po-payments/extras', {
        'poNo': widget.poNo,
        'label': label.text.trim(),
        'isPercent': isPct,
        'value': double.parse(val.text.replaceAll(',', '').trim()),
        'isDiscount': isDisc,
        'currency': isPct ? cur : xcur,
        if (!isPct && xcur != cur)
          'fxRate': double.parse(fx.text.replaceAll(',', '').trim()),
      });
      if (!mounted) return;
      _snack('ເພີ່ມຄ່າໃຊ້ຈ່າຍແລ້ວ');
      _reload();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _deleteExtra(Map<String, dynamic> m) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ລຶບລາຍການນີ້?'),
        content: Text(pick(m, ['label'])),
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
      await Api.delete('/po-payments/extras/${pick(m, ['id'])}');
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Widget _extraRow(Map<String, dynamic> x, String cur) {
    final p = pal(context);
    final a = num0(x['amount']).toDouble();
    final isPct = x['isPercent'] == true;
    final name = pick(x, ['label']) +
        (isPct
            ? ' (${_pctTxt(num0(x['value']).toDouble())}%)'
            : (pick(x, ['currency']).isNotEmpty && pick(x, ['currency']) != cur
                ? ' (${_money(num0(x['value']))} ${pick(x, ['currency'])})'
                : ''));
    return Row(children: [
      Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
      Text('${a < 0 ? '-' : '+'}${_money(a.abs())} $cur',
          style: TextStyle(fontSize: 13, color: a < 0 ? p.ok : null)),
      InkWell(
          onTap: () => _deleteExtra(x),
          child: const Padding(
              padding: EdgeInsets.all(6), child: Icon(Icons.close, size: 16))),
    ]);
  }

  Future<void> _setRate(Map<String, dynamic> m, String poCur) async {
    final c = pick(m, ['currency']);
    final a = num0(m['amount']).toDouble();
    final fx = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (ctx, setS) {
          final r = double.tryParse(fx.text.replaceAll(',', '').trim()) ?? 0;
          return AlertDialog(
            title: const Text('ໃສ່ອັດຕາແລກປ່ຽນ'),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_money(a)} $c · ${pick(m, ['payDate'])}'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: fx,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setS(() {}),
                    decoration: InputDecoration(labelText: '1 $poCur = ? $c'),
                  ),
                  if (r > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('≈ ${_money(a / r)} $poCur',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('ຍົກເລີກ')),
              FilledButton(
                  onPressed: r > 0 ? () => Navigator.pop(d, true) : null,
                  child: const Text('ບັນທຶກ')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final r = double.tryParse(fx.text.replaceAll(',', '').trim()) ?? 0;
    if (r <= 0) return;
    try {
      await Api.put('/po-payments/${pick(m, ['id'])}/rate', {'fxRate': r});
      if (!mounted) return;
      _snack('ບັນທຶກອັດຕາແລ້ວ');
      _reload();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Widget _paySummary(List<dynamic> pays, String cur, num paid) {
    final p = pal(context);
    final byCur = <String, double>{};
    var unconv = 0;
    for (final x in pays) {
      final c = pick(x, ['currency']);
      byCur[c] = (byCur[c] ?? 0) + num0(x['amount']).toDouble();
      if (cur.isNotEmpty &&
          c.isNotEmpty &&
          c != cur &&
          !(num0(x['poAmount']) > 0)) {
        unconv++;
      }
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration:
          BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ລວມທີ່ຈ່າຍທັງໝົດ',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        for (final e in byCur.entries) Text('${_money(e.value)} ${e.key}'),
        const Divider(height: 14),
        Text('≈ ${_money(paid)} $cur (ລວມໃນຍອດ)',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        if (unconv > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('$unconv ລາຍການຍັງບໍ່ມີອັດຕາ - ແຕະລາຍການເພື່ອໃສ່',
                style: TextStyle(color: p.warn, fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _actualCard(List<dynamic> pays, List<dynamic> extras, String poCur) {
    final p = pal(context);
    final paidBy = <String, double>{};
    for (final x in pays) {
      final c = pick(x, ['currency']);
      if (c.isEmpty) continue;
      paidBy[c] = (paidBy[c] ?? 0) + num0(x['amount']).toDouble();
    }
    if (paidBy.isEmpty) return const SizedBox.shrink();

    Widget line(String l, String r, {bool bold = false, Color? col}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(
                child: Text(l,
                    style: TextStyle(
                        fontSize: 13,
                        color: col,
                        fontWeight: bold ? FontWeight.w700 : null))),
            Text(r,
                style: TextStyle(
                    fontSize: bold ? 15 : 13,
                    color: col,
                    fontWeight: bold ? FontWeight.w700 : null)),
          ]),
        );
    String sg(double v, String c) =>
        '${v < 0 ? '-' : '+'}${_money(v.abs())} $c';

    final shown = <dynamic>{};
    final blocks = <Widget>[];
    paidBy.forEach((c, paid) {
      var total = paid;
      final rows = <Widget>[];
      for (final x in extras) {
        final isPct = x['isPercent'] == true;
        final v = num0(x['value']).toDouble();
        var xc = pick(x, ['currency']);
        if (xc.isEmpty) xc = poCur;
        if (!isPct && xc != c) continue;
        var a = isPct ? paid * v / 100 : v;
        if (x['isDiscount'] == true) a = -a;
        a = (a * 100).roundToDouble() / 100;
        total += a;
        if (!isPct) shown.add(x['id']);
        final nm = pick(x, ['label']) + (isPct ? ' (${_pctTxt(v)}%)' : '');
        rows.add(line(nm, sg(a, c)));
      }
      blocks
          .add(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        line('ຈ່າຍແລ້ວ', '${_money(paid)} $c'),
        ...rows,
        const Divider(height: 12),
        line('ລວມຈ່າຍຕົວຈິງ', '${_money(total)} $c', bold: true),
      ]));
      blocks.add(const SizedBox(height: 8));
    });

    final others = <Widget>[];
    for (final x in extras) {
      if (x['isPercent'] == true || shown.contains(x['id'])) continue;
      var xc = pick(x, ['currency']);
      if (xc.isEmpty) xc = poCur;
      var v = num0(x['value']).toDouble();
      if (x['isDiscount'] == true) v = -v;
      others.add(line(pick(x, ['label']), sg(v, xc)));
    }
    if (others.isNotEmpty) {
      blocks.add(Text('ຄ່າໃຊ້ຈ່າຍສະກຸນອື່ນ',
          style: TextStyle(color: p.mut, fontSize: 12)));
      blocks.addAll(others);
    }
    blocks.add(Text('ເປີເຊັນຄິດຈາກຍອດທີ່ຈ່າຍຕົວຈິງຂອງແຕ່ລະສະກຸນ',
        style: TextStyle(color: p.mut, fontSize: 11.5)));

    return AppCard(
      title: 'ຈ່າຍຕົວຈິງ',
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: blocks),
    );
  }

  Future<void> _makePlan(Map<String, dynamic> s) async {
    var cur = pick(s, ['currency']);
    if (cur.isEmpty) cur = widget.currency.isEmpty ? 'USD' : widget.currency;
    final rem = num0(s['remaining']).toDouble();
    final base = rem > 0 ? rem : num0(s['total']).toDouble();
    final tot = TextEditingController(text: base.toStringAsFixed(2));
    final cnt = TextEditingController(text: '3');
    DateTime? first;
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (ctx, setS) {
          final t = double.tryParse(tot.text.replaceAll(',', '').trim()) ?? 0;
          final n = int.tryParse(cnt.text.trim()) ?? 0;
          final cents = (t * 100).round();
          final eachC = n > 0 ? cents ~/ n : 0;
          final lastC = n > 0 ? cents - eachC * (n - 1) : 0;
          return AlertDialog(
            title: const Text('ສ້າງແຜນຈ່າຍເປັນງວດ'),
            content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: tot,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setS(() {}),
                      decoration:
                          InputDecoration(labelText: 'ຍອດທີ່ຈະແບ່ງຈ່າຍ ($cur)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cnt,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setS(() {}),
                      decoration: const InputDecoration(labelText: 'ຈຳນວນງວດ'),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final x = await showDatePicker(
                            context: ctx,
                            initialDate: first ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100));
                        if (x != null) setS(() => first = x);
                      },
                      child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'ວັນທີງວດທຳອິດ (ບໍ່ບັງຄັບ)'),
                          child: Text(first == null ? '-' : _ymd2(first!))),
                    ),
                    if (n > 0 && t > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                            lastC != eachC
                                ? '$n ງວດ: ${_money(eachC / 100)} × ${n - 1} + ${_money(lastC / 100)} $cur'
                                : '$n ງວດ × ${_money(eachC / 100)} $cur',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    if (err != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(err!,
                              style: const TextStyle(color: Colors.red))),
                  ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('ຍົກເລີກ')),
              FilledButton(
                onPressed: () {
                  if (t <= 0) {
                    setS(() => err = 'ໃສ່ຍອດເງິນໃຫ້ຖືກ');
                    return;
                  }
                  if (n < 1 || n > 60) {
                    setS(() => err = 'ຈຳນວນງວດ 1-60');
                    return;
                  }
                  Navigator.pop(d, true);
                },
                child: const Text('ສ້າງແຜນ'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final t = double.parse(tot.text.replaceAll(',', '').trim());
    final n = int.parse(cnt.text.trim());
    try {
      await Api.post('/po-payments/plan', {
        'poNo': widget.poNo,
        'total': t,
        'count': n,
        if (first != null) 'firstDate': _ymd2(first!),
      });
      if (!mounted) return;
      _snack('ສ້າງແຜນແລ້ວ');
      _reload();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _payInst(
      Map<String, dynamic> x, String poCur, double rem) async {
    final instAmt = num0(x['amount']).toDouble();
    final amt = TextEditingController();
    final note = TextEditingController();
    var date = DateTime.now();
    var pc = 'LAK';
    final est = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (ctx, setS) {
          final a = double.tryParse(amt.text.replaceAll(',', '').trim()) ?? 0;
          final diff = pc != poCur;
          final er = double.tryParse(est.text.replaceAll(',', '').trim()) ?? 0;
          final expect = er > 0 ? instAmt * er : 0.0;
          return AlertDialog(
            title: Text('ຈ່າຍງວດທີ ${pick(x, ['seqNo'])}'),
            content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ຍອດງວດ: ${_money(instAmt)} $poCur',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        for (final c in <String>{'LAK', 'THB', 'USD', poCur})
                          ButtonSegment(value: c, label: Text(c)),
                      ],
                      selected: {pc},
                      onSelectionChanged: (v) => setS(() => pc = v.first),
                    ),
                    if (diff) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            border: Border.all(color: pal(ctx).bd),
                            borderRadius: BorderRadius.circular(8)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ຄຳນວນຍອດທີ່ຕ້ອງຈ່າຍ',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: est,
                                autofocus: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                onChanged: (_) => setS(() {}),
                                decoration: InputDecoration(
                                    labelText:
                                        'ອັດຕາແລກປ່ຽນ: 1 $poCur = ? $pc'),
                              ),
                              _fxHint(
                                  poCur, pc, (v) => setS(() => est.text = v)),
                              if (er > 0) ...[
                                const SizedBox(height: 8),
                                Text(
                                    '${_money(instAmt)} $poCur × ${_money(er)} = ${_money(expect)} $pc',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => setS(() =>
                                        amt.text = expect.toStringAsFixed(2)),
                                    child: const Text('ໃຊ້ຍອດນີ້'),
                                  ),
                                ),
                              ],
                            ]),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          border: Border.all(color: pal(ctx).bd),
                          borderRadius: BorderRadius.circular(8)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ຈ່າຍຕົວຈິງ',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: amt,
                              autofocus: !diff,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => setS(() {}),
                              decoration: InputDecoration(
                                  labelText: 'ຈຳນວນເງິນທີ່ຈ່າຍ ($pc)'),
                            ),
                            if (diff && a > 0 && instAmt > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                  'ອັດຕາຕົວຈິງ: 1 $poCur = ${_money(a / instAmt)} $pc',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              if (expect > 0)
                                Text(
                                    'ຕ່າງຈາກຄຳນວນ: ${a - expect < 0 ? '-' : '+'}${_money((a - expect).abs())} $pc',
                                    style: TextStyle(
                                        color: pal(ctx).mut, fontSize: 12.5)),
                            ],
                          ]),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final v = await showDatePicker(
                            context: ctx,
                            initialDate: date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100));
                        if (v != null) setS(() => date = v);
                      },
                      child: InputDecorator(
                          decoration:
                              const InputDecoration(labelText: 'ວັນທີຊຳລະ'),
                          child: Text(_ymd2(date))),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                        controller: note,
                        decoration: const InputDecoration(
                            labelText: 'ໝາຍເຫດ (ບໍ່ບັງຄັບ)')),
                    if (err != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(err!,
                              style: const TextStyle(color: Colors.red))),
                  ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('ຍົກເລີກ')),
              FilledButton(
                onPressed: () {
                  if (a <= 0) {
                    setS(() => err = 'ໃສ່ຈຳນວນເງິນໃຫ້ຖືກ');
                    return;
                  }
                  Navigator.pop(d, true);
                },
                child: const Text('ບັນທຶກ'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final a = double.parse(amt.text.replaceAll(',', '').trim());
    final poAmt = pc == poCur ? a : instAmt;
    var allowOver = false;
    if (poAmt > rem + 0.005) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('ຈຳນວນເກີນຍອດຄ້າງຈ່າຍ'),
          content: Text(
              'ຄ້າງຈ່າຍ ${_money(rem)} $poCur\nຈະຊຳລະ ${_money(poAmt)} $poCur\n\nຢືນຢັນການຈ່າຍເກີນບໍ?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('ຍົກເລີກ')),
            FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('ຢືນຢັນ')),
          ],
        ),
      );
      if (go != true) return;
      allowOver = true;
    }
    try {
      await Api.post('/po-payments/installments/${pick(x, ['id'])}/pay', {
        'amount': a,
        'currency': pc,
        'payDate': _ymd2(date),
        'note': note.text.trim(),
        if (allowOver) 'allowOver': true,
      });
      if (!mounted) return;
      _snack('ບັນທຶກການຈ່າຍງວດແລ້ວ');
      _reload();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _clearPlan() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ລຶບແຜນທີ່ຍັງບໍ່ຈ່າຍ?'),
        content: const Text('ງວດທີ່ຈ່າຍແລ້ວຈະບໍ່ຖືກລຶບ'),
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
      await Api.delete(
          '/po-payments/plan?poNo=${Uri.encodeQueryComponent(widget.poNo)}');
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Widget _planCard(Map<String, dynamic> s, String cur) {
    final p = pal(context);
    final plan = asList(s['plan']);
    final rem = num0(s['remaining']).toDouble();
    if (plan.isEmpty) {
      return AppCard(
        title: 'ແຜນຈ່າຍເປັນງວດ',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ຍັງບໍ່ມີແຜນ', style: TextStyle(color: p.mut)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _makePlan(s),
            icon: const Icon(Icons.event_note_outlined),
            label: const Text('ສ້າງແຜນຈ່າຍເປັນງວດ'),
          ),
        ]),
      );
    }
    final paidN = plan.where((x) => x['paid'] == true).length;
    final paidBy = <String, double>{};
    for (final x in plan) {
      if (x['paid'] != true) continue;
      final c = pick(x, ['paidCurrency']);
      paidBy[c] = (paidBy[c] ?? 0) + num0(x['paidAmount']).toDouble();
    }
    return AppCard(
      title: 'ແຜນຈ່າຍເປັນງວດ ($paidN/${plan.length})',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final x in plan)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: x['paid'] == true ? p.okbg : null,
              child: x['paid'] == true
                  ? Icon(Icons.check, size: 16, color: p.ok)
                  : Text('${pick(x, ['seqNo'])}'),
            ),
            title: Text(
                'ງວດ ${pick(x, ['seqNo'])} · ${_money(num0(x['amount']))} $cur',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                (x['paid'] == true
                        ? [
                            '${_money(num0(x['paidAmount']))} ${pick(x, [
                                  'paidCurrency'
                                ])}',
                            if (num0(x['fxRate']) > 0)
                              '1 $cur = ${_money(num0(x['fxRate']))} ${pick(x, [
                                    'paidCurrency'
                                  ])}',
                            pick(x, ['payDate']),
                          ]
                        : [
                            if (pick(x, ['dueDate']).isNotEmpty)
                              'ກຳນົດ ${pick(x, ['dueDate'])}',
                            'ຍັງບໍ່ຈ່າຍ',
                          ])
                    .where((e) => e.isNotEmpty)
                    .join(' · '),
                style: TextStyle(color: p.mut, fontSize: 12)),
            trailing: x['paid'] == true
                ? null
                : FilledButton.tonal(
                    onPressed: () => _payInst(x, cur, rem),
                    child: const Text('ຈ່າຍ')),
          ),
        if (paidBy.isNotEmpty) ...[
          const Divider(height: 14),
          for (final e in paidBy.entries)
            Text('ຈ່າຍແລ້ວລວມ ${_money(e.value)} ${e.key}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 4),
        Row(children: [
          TextButton(
              onPressed: () => _makePlan(s), child: const Text('ແຜນໃໝ່')),
          TextButton(
              onPressed: _clearPlan, child: const Text('ລຶບແຜນທີ່ຍັງບໍ່ຈ່າຍ')),
        ]),
      ]),
    );
  }

  Widget _kv(String k, String v, Color? c) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(color: pal(context).mut, fontSize: 12.5)),
        Text(v,
            style:
                TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: c)),
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
        final extras = asList(s['extras']);
        final baseTotal = num0(s['baseTotal']).toDouble();
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
                          child: Text(
                              remaining < -0.004
                                  ? 'ຈ່າຍເກີນ ${_money(-remaining)} $cur'
                                  : 'ຊຳລະຄົບແລ້ວ',
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
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () => _addExtra(s),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('ເພີ່ມຄ່າໃຊ້ຈ່າຍອື່ນ (ພາສີ, ຄ່າຂົນສົ່ງ...)'),
              ),
            ),
            const SizedBox(height: 12),
            _planCard(s, cur),
            if (extras.isNotEmpty) ...[
              const SizedBox(height: 12),
              AppCard(
                title: 'ຄ່າໃຊ້ຈ່າຍອື່ນ (ຕົວຈິງ)',
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final x in extras) _extraRow(x, cur),
                      const Divider(height: 18),
                      Row(children: [
                        const Expanded(
                            child: Text('ລວມຄ່າໃຊ້ຈ່າຍອື່ນ',
                                style: TextStyle(fontWeight: FontWeight.w700))),
                        Text('${_money(num0(s['extraTotal']).toDouble())} $cur',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 28),
                      ]),
                    ]),
              ),
            ],
            const SizedBox(height: 12),
            _actualCard(pays, extras, cur),
            const SizedBox(height: 12),
            AppCard(
              title: 'ປະຫວັດການຊຳລະ (${pays.length} ຄັ້ງ)',
              child: pays.isEmpty
                  ? Text('ຍັງບໍ່ມີການຊຳລະ', style: TextStyle(color: p.mut))
                  : Column(children: [
                      _paySummary(pays, cur, paid),
                      for (var i = 0; i < pays.length; i++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading:
                              CircleAvatar(radius: 14, child: Text('${i + 1}')),
                          onTap: (cur.isNotEmpty &&
                                  pick(pays[i], ['currency']).isNotEmpty &&
                                  pick(pays[i], ['currency']) != cur)
                              ? () => _setRate(pays[i], cur)
                              : null,
                          title: Text(
                              '${_money(num0(pays[i]['amount']))} ${pick(pays[i], [
                                    'currency'
                                  ])}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              [
                                pick(pays[i], ['payDate']),
                                pick(pays[i], ['note']),
                                pick(pays[i], ['userName']),
                                if (cur.isNotEmpty &&
                                    pick(pays[i], ['currency']).isNotEmpty &&
                                    pick(pays[i], ['currency']) != cur)
                                  (num0(pays[i]['poAmount']) > 0
                                      ? '≈ ${_money(num0(pays[i]['poAmount']))} $cur'
                                      : 'ບໍ່ລວມໃນຍອດ · ແຕະເພື່ອໃສ່ອັດຕາ'),
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

Future<void> _exportPoExcel(BuildContext context, _PoGroup g) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final first = g.items.first;
    if (pick(first, ['itemId']).isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('ບໍ່ພົບ itemId ຂອງລາຍການ')));
      return;
    }
    final cur = g.currency.isEmpty ? pick(first, ['currency']) : g.currency;
    double rate = cur == 'LAK' ? 1.0 : 0.0;
    String rateDate = '';
    if (rate == 0) {
      try {
        final d = await Api.get('/po-payments/fx');
        if (d is Map) {
          rateDate = '${d['rateDate'] ?? ''}';
          final rs = d['rates'];
          if (rs is Map) {
            final m = rs[cur];
            if (m is Map) rate = num0(m['sell']).toDouble();
          }
        }
      } catch (_) {}
    }
    var date = g.date;
    if (date.isEmpty) {
      date = pick(
          first, ['receiptDate', 'movementDate', 'createdAt', 'invoiceDate']);
      if (date.length >= 10) date = date.substring(0, 10);
    }
    final freight = num0(pick(first, ['freightCost'])).toDouble();
    final invoice = num0(pick(first, ['totalAmount'])).toDouble();
    final rows = <List<Object>>[
      <Object>['PO', g.po],
      <Object>['GRN', g.grn],
      <Object>['Branch', g.branch],
      <Object>['Date', date],
      <Object>['ຄ່າຂົນສົ່ງ', freight],
      <Object>['ມູນຄ່າ Invoice', invoice],
      <Object>['Currency', cur],
      <Object>[
        rate > 0 ? '1 $cur = LAK' : 'ບໍ່ພົບອັດຕາ LAK',
        rate > 0 ? rate : '',
        rateDate.isEmpty ? '' : 'BOL $rateDate'
      ],
      <Object>[
        'ມູນຄ່າ Invoice (LAK)',
        rate > 0 ? (invoice * rate).roundToDouble() : ''
      ],
      <Object>['ວິທີໃຊ້', 'ແກ້ສະເພາະຖັນ F (ລາຄາຕໍ່ໜ່ວຍ LAK) · ຖັນ G ຄິດໄລ່ເອງ'],
      <Object>[],
      <Object>[
        'ລຳດັບ',
        'ລາຍການ',
        'ຈຳນວນ',
        'ລາຄາ',
        'ລວມ',
        'ລາຄາ/ໜ່ວຍ (LAK)',
        'ລວມ (LAK)',
        'ID'
      ],
    ];
    final hdrRow = rows.length;
    final bold = <int>{rows.length - 1};
    var n = 0;
    double sum = 0;
    double sumLak = 0;
    for (final m in g.items) {
      n++;
      final qty = num0(pick(m, ['qtyChange', 'qty', 'quantity', 'delta']));
      final cost = num0(pick(m, ['unitCost']));
      final aStr = pick(m, ['amount']);
      final amt = aStr.isNotEmpty ? num0(aStr) : qty * cost;
      final name = pick(m, ['productName', 'name', 'productId']);
      final iid = num0(pick(m, ['itemId'])).toInt();
      final unit = rate > 0 ? (cost.toDouble() * rate).roundToDouble() : 0.0;
      final lak = unit * qty.toDouble();
      final r = hdrRow + n;
      sum += amt.toDouble();
      sumLak += lak;
      final Object q = qty == qty.roundToDouble() ? qty.toInt() : qty;
      rows.add(<Object>[
        n,
        name,
        q,
        cost,
        amt,
        rate > 0 ? unit : '',
        XlFormula('C$r*F$r', lak),
        iid
      ]);
    }
    rows.add(<Object>[
      '',
      'ລວມ',
      '',
      '',
      sum,
      '',
      XlFormula('SUM(G${hdrRow + 1}:G${hdrRow + n})', sumLak)
    ]);
    bold.add(rows.length - 1);
    final safe = g.po.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final tn = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${two(tn.month)}${two(tn.day)}_${two(tn.hour)}${two(tn.minute)}';
    await sharePoXlsx(
      fileName: 'PO_${safe}_$stamp.xlsx',
      rows: rows,
      boldRows: bold,
      widths: [22, 46, 10, 14, 14, 20, 20, 8],
      hiddenCols: {7},
    );
  } catch (e) {
    debugPrint('[PO] export excel failed: $e');
    messenger.showSnackBar(SnackBar(content: Text('ດາວໂຫຼດບໍ່ສຳເລັດ: $e')));
  }
}

String _lakFmt(Object? v) {
  final n = (v is num) ? v.round() : (num.tryParse('$v') ?? 0).round();
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}
