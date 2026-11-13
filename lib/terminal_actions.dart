import 'product_images.dart';
// Terminal info page with "Fix" and "Change terminal" actions.
// New file: nothing existing is overwritten. Needs mobile_scanner (already in pubspec).
import 'terminal_parts_page.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'api.dart';
import 'crud.dart';
import 'specs.dart';
import 'terminal_history.dart';
import 'theme.dart';
import 'type_image.dart';
import 'widgets.dart';

const kMA = 'MA', kReady = 'Ready', kInUse = 'In Use';

/// The only place that decides what POST /activities looks like.
/// If the server rejects a field name, fix it here.
Map<String, dynamic> activityBody(String barcode, String status,
        {String? atmId, String? note}) =>
    {
      'barcode': barcode,
      'status': status,
      if (atmId != null && atmId.isNotEmpty) 'atmId': atmId,
      if (note != null && note.isNotEmpty) 'note': note,
    };

/// Open the info page of a terminal (row from GET /terminals).
Future<void> openTerminalInfo(
        BuildContext context, Map<String, dynamic> terminal,
        {VoidCallback? onChanged}) =>
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => TerminalInfoPage(terminal, onChanged: onChanged)));

// ------------------------------------------------------------ info page
class TerminalInfoPage extends StatefulWidget {
  final Map<String, dynamic> terminal;
  final VoidCallback? onChanged;
  const TerminalInfoPage(this.terminal, {super.key, this.onChanged});
  @override
  State<TerminalInfoPage> createState() => _TerminalInfoPageState();
}

class _TerminalInfoPageState extends State<TerminalInfoPage> {
  String get _barcode => pick(widget.terminal, ['barcode']);
  late Future<dynamic> _f = _load();
  bool _busy = false;

  Map<String, dynamic> _atmInfo =
      {}; // ATM that holds the terminal: brand + model (ATM_VERSION)

  Future<dynamic> _load() async {
    final d = await Api.get('/terminals/${Uri.encodeComponent(_barcode)}');
    final atm = pick(d is Map ? d : widget.terminal, ['atmId']);
    var info = <String, dynamic>{};
    if (atm.isNotEmpty) {
      try {
        final x = await Api.get('/atms/${Uri.encodeComponent(atm)}');
        if (x is Map) info = Map<String, dynamic>.from(x);
      } catch (_) {}
    }
    _atmInfo = info;
    return d;
  }

  void _reload() => setState(() {
        _f = _load();
      });

  Map<String, dynamic> _merged(dynamic d) =>
      {...widget.terminal, if (d is Map) ...Map<String, dynamic>.from(d)};

  // ---------------------------------------------------------- change
  Future<void> _change(Map<String, dynamic> m) async {
    final old = _barcode;
    final atm = pick(m, ['atmId']);
    final typeId = pick(m, ['typeId']);

    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text('ເລືອກ Terminal ໃໝ່ມາແທນ $old',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Terminal ເກົ່າຈະປ່ຽນເປັນ MA'),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('ສະແກນ Barcode'),
            onTap: () => Navigator.pop(c, 'scan'),
          ),
          ListTile(
            leading: const Icon(Icons.list_alt),
            title: const Text('ເລືອກເອງຈາກລາຍການ'),
            onTap: () => Navigator.pop(c, 'pick'),
          ),
        ]),
      ),
    );
    if (method == null || !mounted) return;

    String? nb;
    if (method == 'scan') {
      nb = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => const ScanBarcodePage()));
    } else {
      // ATM brand / model decide which MODEL chips are ticked by default
      var atmInfo = <String, dynamic>{};
      if (atm.isNotEmpty) {
        try {
          final d = await Api.get('/atms/${Uri.encodeComponent(atm)}');
          if (d is Map) atmInfo = Map<String, dynamic>.from(d);
        } catch (_) {}
      }
      if (!mounted) return;
      final row = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
            builder: (_) => PickReadyTerminalPage(
                typeId: typeId, exclude: old, atm: atmInfo)),
      );
      nb = row == null ? null : pick(row, ['barcode']);
    }
    if (nb == null || nb.trim().isEmpty || !mounted) return;
    nb = nb.trim();
    if (nb == old) {
      toastMsg(context, 'ເປັນ Terminal ໂຕດຽວກັນ');
      return;
    }

    setState(() => _busy = true);
    try {
      // check the new terminal before touching anything
      final nd = await Api.get('/terminals/${Uri.encodeComponent(nb)}');
      final nm =
          nd is Map ? Map<String, dynamic>.from(nd) : <String, dynamic>{};
      final st = pick(nm, ['state', 'status']);
      if (st.toLowerCase() != kReady.toLowerCase()) {
        if (mounted) {
          toastMsg(context, 'Terminal $nb ສະຖານະ "$st" ບໍ່ແມ່ນ Ready');
        }
        return;
      }
      final nt = pick(nm, ['typeId']);
      if (typeId.isNotEmpty && nt.isNotEmpty && nt != typeId) {
        if (mounted) toastMsg(context, 'Terminal $nb ເປັນຄົນລະປະເພດກັບ $old');
        return;
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('ຢືນຢັນການປ່ຽນ Terminal'),
          content: Text('ຕູ້ $atm\n\n$old  →  $kMA\n$nb  →  $kInUse'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('ຍົກເລີກ')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('ຢືນຢັນ')),
          ],
        ),
      );
      if (ok != true) return;

      await Api.post('/activities', activityBody(old, kMA));
      try {
        await Api.post('/activities', activityBody(nb, kInUse, atmId: atm));
      } catch (e) {
        // put the old terminal back so the ATM is not left without one
        try {
          await Api.post('/activities', activityBody(old, kInUse, atmId: atm));
        } catch (_) {}
        rethrow;
      }
      widget.onChanged?.call();
      if (!mounted) return;
      toastMsg(context, 'ປ່ຽນ Terminal ແລ້ວ');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toastMsg(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _kv(BuildContext c, String k, String v) {
    if (v.isEmpty) return const SizedBox();
    final p = pal(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(k, style: TextStyle(color: p.mut))),
        Expanded(
            child:
                Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_barcode)),
      body: FutureBuilder(
        future: _f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) return ErrorView(s.error!, _reload);
          final m = _merged(s.data);
          final state = pick(m, ['state', 'status']);
          final atm = pick(m, ['atmId']);
          final canManage = Api.can('ATM_MANAGE');
          final inUse =
              state.toLowerCase() == kInUse.toLowerCase() && atm.isNotEmpty;
          Widget act(IconData icon, String label, VoidCallback? onTap) =>
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Opacity(
                      opacity: onTap == null ? 0.35 : 1,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon),
                        const SizedBox(height: 2),
                        Text(label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  ),
                ),
              );
          return Column(children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            typeThumb(c, pick(m, ['typeImage', 'imageFile']),
                                size: 40),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(_barcode,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700))),
                            if (state.isNotEmpty) Tag(state, kindOf(state)),
                          ]),
                          const SizedBox(height: 8),
                          _kv(c, 'ປະເພດ', pick(m, ['typeName', 'typeId'])),
                          _kv(
                              c,
                              'Brand',
                              pick(_atmInfo, [
                                'atmType',
                                'atmBrand',
                                'brandName',
                                'brand'
                              ])),
                          _kv(
                              c,
                              'Model',
                              pick(_atmInfo, [
                                'atmVersion',
                                'atm_version',
                                'version',
                                'atmModel',
                                'modelName',
                                'model'
                              ])),
                          _kv(c, 'Serial',
                              pick(m, ['serial', 'serialNo', 'serialNumber'])),
                          _kv(c, 'ຕູ້ ATM', atm),
                          _kv(c, 'ສະຖານທີ່',
                              pick(m, ['atmLocation', 'location'])),
                        ]),
                  ),
                  const SizedBox(height: 12),
                  AppCard(title: 'ລາຍລະອຽດທັງໝົດ', child: DataView(m)),
                ]),
              ),
            ),
            Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                child: Row(children: [
                  act(
                      Icons.memory,
                      'ອາໄຫຼ່',
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => TerminalPartsPage(_barcode)))),
                  act(
                      Icons.history,
                      'ປະຫວັດ',
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => HistoryPage(barcode: _barcode)))),
                  act(
                      Icons.build_circle_outlined,
                      'ສ້ອມ/ປ່ຽນ',
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => HistoryPage(
                                  barcode: _barcode,
                                  initialFilter: 'status')))),
                  if (canManage) ...[
                    act(
                        Icons.build_outlined,
                        'ສ້ອມ',
                        _busy
                            ? null
                            : () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            FixTerminalPage(m, onChanged: () {
                                              widget.onChanged?.call();
                                              _reload();
                                            })));
                              }),
                    act(Icons.swap_horiz, 'ປ່ຽນ',
                        (_busy || inUse == false) ? null : () => _change(m)),
                  ],
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ------------------------------------------------------- pick / scan
/// Manual pick: only Terminals that are Ready (same type when known).
/// MODEL chips (like the product form): only terminals of the ticked models are listed.
/// Default ticks = the ATM's own model; untick everything to see all.
class PickReadyTerminalPage extends StatefulWidget {
  final String typeId, exclude;
  final Map<String, dynamic> atm;
  const PickReadyTerminalPage(
      {super.key, this.typeId = '', this.exclude = '', this.atm = const {}});
  @override
  State<PickReadyTerminalPage> createState() => _PickReadyTerminalPageState();
}

class _PickReadyTerminalPageState extends State<PickReadyTerminalPage> {
  static String _n(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ກ-ໝ]'), '');

  late final String _brand =
      pick(widget.atm, ['atmType', 'atmBrand', 'brandName', 'brand']);
  late final String _model = pick(widget.atm, [
    'atmVersion',
    'atm_version',
    'version',
    'atmModel',
    'modelName',
    'model'
  ]);
  List<Map<String, dynamic>> _models = [];
  final _sel = <String>{}; // normalised names of ticked models

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      final rows = asList(await Api.get('/models'));
      var list = rows;
      final bn = _n(_brand);
      if (bn.isNotEmpty) {
        final f = rows.where((r) {
          final b = _n(pick(r, ['brandName']));
          return b.isNotEmpty && (b == bn || bn.contains(b));
        }).toList();
        if (f.isNotEmpty) list = f; // models of the ATM's brand only
      }
      final hay = _n(_model);
      if (!mounted) return;
      setState(() {
        _models = list;
        if (hay.isNotEmpty) {
          for (final r in list) {
            final nm = _n(pick(r, ['name']));
            if (nm.isNotEmpty && hay.contains(nm)) _sel.add(nm);
          }
        }
      });
    } catch (_) {}
  }

  bool _ok(Map<String, dynamic> m) {
    if (pick(m, ['state', 'status']).toLowerCase() != kReady.toLowerCase()) {
      return false;
    }
    if (pick(m, ['barcode']) == widget.exclude) return false;
    if (_sel.isEmpty) return true;
    final t = _n([
      pick(m, ['modelName', 'model']),
      pick(m, ['serial'])
    ].join(' '));
    return _sel.any((x) => t.contains(x));
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final extra =
        'limit=500&state=Ready${widget.typeId.isEmpty ? '' : '&typeId=${Uri.encodeQueryComponent(widget.typeId)}'}';
    return Scaffold(
      appBar: AppBar(title: const Text('ເລືອກ Terminal ໃໝ່ (Ready)')),
      body: Column(children: [
        if (_models.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                      'MODEL ທີ່ສະແດງ${_brand.isEmpty ? '' : ' ($_brand)'}',
                      style: TextStyle(color: p.mut, fontSize: 14)),
                ),
                TextButton(
                  onPressed: _sel.isEmpty ? null : () => setState(_sel.clear),
                  child: const Text('ສະແດງທັງໝົດ'),
                ),
              ]),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in _models)
                  FilterChip(
                    label: Text(pick(r, ['name'])),
                    selected: _sel.contains(_n(pick(r, ['name']))),
                    onSelected: (on) => setState(() {
                      final k = _n(pick(r, ['name']));
                      if (on) {
                        _sel.add(k);
                      } else {
                        _sel.remove(k);
                      }
                    }),
                  ),
              ]),
            ]),
          ),
        Expanded(
          child: ListPage(
            title: 'Terminal',
            path: '/terminals',
            extraQuery: extra,
            titleKeys: const ['barcode'],
            subKeys: const ['typeName', 'modelName', 'model', 'serial'],
            tagKeys: const ['state'],
            rowFilter: _ok,
            onTapItem: (c, m) => Navigator.pop(c, m),
          ),
        ),
      ]),
    );
  }
}

class ScanBarcodePage extends StatefulWidget {
  const ScanBarcodePage({super.key});
  @override
  State<ScanBarcodePage> createState() => _ScanBarcodePageState();
}

class _ScanBarcodePageState extends State<ScanBarcodePage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ສະແກນ Barcode Terminal ໃໝ່')),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null && v.trim().isNotEmpty) {
                _done = true;
                Navigator.pop(context, v.trim());
                return;
              }
            }
          },
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(20)),
            child: const Text('ເລັງກ້ອງໃສ່ Barcode',
                style: TextStyle(color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ fix
/// Repair: POST /repair = MA + parts used (stock goes down) [+ Ready + In Use if reinstall].
/// Parts are picked straight from the product list.
class FixTerminalPage extends StatefulWidget {
  final Map<String, dynamic> terminal;
  final VoidCallback? onChanged;
  const FixTerminalPage(this.terminal, {super.key, this.onChanged});
  @override
  State<FixTerminalPage> createState() => _FixTerminalPageState();
}

class _FixTerminalPageState extends State<FixTerminalPage> {
  final _note = TextEditingController();
  final _parts = <String, Map<String, dynamic>>{}; // productId -> product row
  final _qty = <String, int>{};
  final _cost = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> _branches = [];
  dynamic _branchId = Api.user?['branchId'];
  bool _reinstall = true, _busy = false;
  String? _error;
  Map<String, dynamic> _atmInfo = {};
  Future<void>? _atmLoad;

  String get _barcode => pick(widget.terminal, ['barcode']);
  String get _atm => pick(widget.terminal, ['atmId']);

  // ATM brand / model are used to filter the part picker
  Future<void> _loadAtm() async {
    if (_atm.isEmpty) return;
    try {
      final d = await Api.get('/atms/${Uri.encodeComponent(_atm)}');
      if (d is Map) _atmInfo = Map<String, dynamic>.from(d);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _atmLoad = _loadAtm();
    Api.get('/repair/branches').then((d) {
      final b = asList(d);
      if (!mounted) return;
      setState(() {
        _branches = b;
        if (_branchId == null && b.length == 1) _branchId = b.first['id'];
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// FIFO PO cost preview (server: GET /repair/cost)
  Future<void> _loadCost(String id) async {
    final q = _qty[id] ?? 1;
    try {
      final r = await Api.get(
          '/repair/cost?productId=${Uri.encodeQueryComponent(id)}&qty=$q');
      if (r is Map && mounted) {
        setState(() => _cost[id] = Map<String, dynamic>.from(r));
      }
    } catch (_) {}
  }

  List<Widget> _costLines(String id, dynamic p) {
    final c = _cost[id];
    if (c == null) return const [];
    final lines = c['lines'] is List ? c['lines'] as List : const [];
    final out = <Widget>[];
    for (final l in lines) {
      if (l is! Map) continue;
      final po = '${l['poNo'] ?? ''}';
      final cur = '${l['currency'] ?? ''}';
      final txt = po.isEmpty
          ? '${l['qty']} ຊິ້ນ · ບໍ່ມີ PO'
          : 'PO $po · ${l['qty']} × ${l['unitCost']} $cur';
      out.add(Text(txt, style: TextStyle(color: p.mut, fontSize: 12)));
    }
    final tot = c['total'];
    if (tot is Map && tot.isNotEmpty) {
      out.add(Text(
          'ລວມ ${tot.entries.map((e) => '${e.value is num ? (e.value as num).toStringAsFixed(2) : e.value} ${e.key}').join(' + ')}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)));
    }
    return out;
  }

  Future<void> _addPart() async {
    await _atmLoad;
    if (!mounted) return;
    final row = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
            builder: (_) => PickProductPage(
                branchId: _branchId,
                terminalType: pick(widget.terminal, ['typeName']),
                terminalTypeId: pick(widget.terminal, ['typeId']),
                terminal: widget.terminal,
                atm: _atmInfo)));
    if (row == null || !mounted) return;
    final id = pick(row, ['id', 'productId']);
    if (id.isEmpty) return;
    setState(() {
      _parts[id] = row;
      _qty[id] = (_qty[id] ?? 0) + 1;
    });
    _loadCost(id);
  }

  /// Scan product barcodes: +1 per scan, only for parts that fit this terminal + ATM model
  /// and have stock in the chosen branch (keeps scanning until back is pressed). // check this terminal
  Future<void> _scanPart() async {
    if (_branchId == null) {
      setState(() => _error = 'ເລືອກສາຂາທີ່ຈະຕັດສະຕັອກກ່ອນ');
      return;
    }
    while (mounted) {
      final raw = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => const ScanBarcodePage()));
      if (raw == null || raw.trim().isEmpty || !mounted) return;
      final code = raw.trim();
      try {
        final r =
            await Api.get('/products/by-barcode/${Uri.encodeComponent(code)}');
        final id =
            r is Map && r['productId'] != null ? '${r['productId']}' : '';
        if (id.isEmpty) {
          if (mounted) toastMsg(context, 'ບໍ່ພົບສິນຄ້າ barcode: $code');
          continue;
        }
        final name = '${r['name'] ?? id}';
        final cp = await Api.get(
            '/repair/parts?barcode=${Uri.encodeQueryComponent(_barcode)}&atmId=${Uri.encodeQueryComponent(_atm)}&branchId=${Uri.encodeQueryComponent('$_branchId')}');
        final fit = (cp is Map ? asList(cp['parts']) : <Map<String, dynamic>>[])
            .where((e) => '${e['id']}' == id)
            .toList();
        if (!mounted) return;
        if (fit.isEmpty) {
          toastMsg(context, '$name ບໍ່ກົງກັບ Terminal / ຮຸ່ນຕູ້ນີ້');
          continue;
        }
        final stock = num.tryParse('${fit.first['stock']}') ?? 0;
        final next = (_qty[id] ?? 0) + 1;
        if (next > stock) {
          toastMsg(context, 'ສະຕັອກບໍ່ພໍ: $name (ມີ $stock)');
          continue;
        }
        setState(() {
          _parts[id] = Map<String, dynamic>.from(fit.first);
          _qty[id] = next;
        });
        _loadCost(id);
        toastMsg(context, '+1 $name');
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
        return;
      }
    }
  }

  Future<void> _save() async {
    final used = _qty.entries.where((e) => e.value > 0).toList();
    if (used.isNotEmpty && _branchId == null) {
      setState(() => _error = 'ເລືອກສາຂາທີ່ຈະຕັດສະຕັອກກ່ອນ');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // NOTE: body field names are inferred from the route list; adjust here if the server complains.
      await Api.post('/repair', {
        'barcode': _barcode,
        if (_atm.isNotEmpty) 'atmId': _atm,
        if (_branchId != null) 'branchId': _branchId,
        'parts': [
          for (final e in used) {'productId': e.key, 'qty': e.value}
        ],
        'reinstall': _reinstall,
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      widget.onChanged?.call();
      if (!mounted) return;
      toastMsg(context, 'ບັນທຶກການສ້ອມແລ້ວ');
      Navigator.pop(context);
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
      appBar: AppBar(title: Text('ສ້ອມ · $_barcode')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          title: 'ອາໄຫຼ່ທີ່ໃຊ້',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<dynamic>(
              key: ValueKey('br-${_branches.length}-$_branchId'),
              initialValue:
                  _branches.any((b) => b['id'] == _branchId) ? _branchId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ຕັດສະຕັອກຈາກສາຂາ'),
              items: [
                for (final b in _branches)
                  DropdownMenuItem(
                      value: b['id'],
                      child: Text(pick(b, ['name', 'branchName', 'id']))),
              ],
              onChanged: (v) => setState(() => _branchId = v),
            ),
            const SizedBox(height: 8),
            if (_parts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('ຍັງບໍ່ໄດ້ເລືອກອາໄຫຼ່',
                    style: TextStyle(color: p.mut),
                    textAlign: TextAlign.center),
              )
            else
              for (final id in _parts.keys) _partRow(id),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('ສະແກນ'),
                  onPressed: _busy ? null : _scanPart,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('ເລືອກຈາກສິນຄ້າ'),
                  onPressed: _busy ? null : _addPart,
                ),
              ),
            ]),
          ]),
        ),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
                controller: _note,
                decoration:
                    const InputDecoration(labelText: 'ໝາຍເຫດ (ບໍ່ບັງຄັບ)')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ຕິດຕັ້ງຄືນເຂົ້າຕູ້ຫຼັງສ້ອມ'),
              subtitle:
                  const Text('ເປີດ = Ready ແລ້ວ In Use  ·  ປິດ = ປະໄວ້ MA'),
              value: _reinstall,
              onChanged: (v) => setState(() => _reinstall = v),
            ),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: TextStyle(color: p.bad))),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ບັນທຶກການສ້ອມ'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  final Map<String, String> _imgCache = {};
  final Set<String> _imgAsked = {};

  /// Photo for a part line that came without one (for example a scanned part).
  Future<void> _fetchImg(String id) async {
    if (!_imgAsked.add(id)) return;
    try {
      final d = await Api.get('/products/${Uri.encodeComponent(id)}');
      if (d is! Map) return;
      final imgs = d['images'];
      if (imgs is! List || imgs.isEmpty || imgs.first is! Map) return;
      final u = pick(imgs.first as Map, ['url', 'path']);
      if (u.isNotEmpty && mounted) setState(() => _imgCache[id] = u);
    } catch (_) {}
  }

  /// Small photo of a part line. Tap it to see it bigger.
  Widget _partThumb(String id, Map r, Pal p) {
    var raw = pick(r, ['imageUrl', 'image', 'photo']);
    if (raw.isEmpty) {
      raw = _imgCache[id] ?? '';
      if (raw.isEmpty) _fetchImg(id);
    }
    final url = raw.isEmpty ? '' : productImageUrl(raw);
    final ph = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.mut.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.image_outlined, size: 22, color: p.mut),
    );
    if (url.isEmpty) return ph;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Icon(Icons.broken_image_outlined, size: 48),
              ),
            ),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ph,
        ),
      ),
    );
  }

  Widget _partRow(String id) {
    final p = pal(context);
    final r = _parts[id]!;
    final stock = pick(r, ['stock', 'qty', 'balance', 'available']);
    final q = _qty[id] ?? 1;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: p.bd))),
      child: Row(children: [
        _partThumb(id, r, p),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pick(r, ['name', 'productName', 'id'])),
            Text(
                [
                  pick(r, ['typeName', 'categoryName']),
                  if (stock.isNotEmpty) 'ສະຕັອກ $stock'
                ].where((e) => e.isNotEmpty).join('  ·  '),
                style: TextStyle(color: p.mut, fontSize: 12)),
            ..._costLines(id, p),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: q > 1
              ? () {
                  setState(() => _qty[id] = q - 1);
                  _loadCost(id);
                }
              : null,
        ),
        Text('$q', style: const TextStyle(fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () {
            setState(() => _qty[id] = q + 1);
            _loadCost(id);
          },
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: p.bad),
          onPressed: () => setState(() {
            _parts.remove(id);
            _qty.remove(id);
          }),
        ),
      ]),
    );
  }
}

/// Product list filtered by  terminal type > ATM brand > ATM model.
/// Tap a row to pick it. Add / edit / delete use the normal product form.
class PickProductPage extends StatefulWidget {
  final String terminalType, terminalTypeId;
  final Map<String, dynamic> atm, terminal;
  final dynamic branchId;
  final bool pickerMode;
  const PickProductPage(
      {super.key,
      this.branchId,
      this.pickerMode = false,
      this.terminalType = '',
      this.terminalTypeId = '',
      this.atm = const {},
      this.terminal = const {}});
  @override
  State<PickProductPage> createState() => _PickProductPageState();
}

class _PickProductPageState extends State<PickProductPage> {
  // 0 = all, 1 = terminal type, 2 = + ATM brand, 3 = + ATM model
  late int _level = _modelLabel.isNotEmpty
      ? 3
      : _brandLabel.isNotEmpty
          ? 2
          : widget.terminalType.isNotEmpty
              ? 1
              : 0;
  final _q = TextEditingController();
  late Future<dynamic> _f = _load();

  final Map<String, num> _branchStock = {};
  bool get _hasBranch => widget.branchId != null;

  Future<dynamic> _load() async {
    debugPrint(
        '[PICK] NEW PickProductPage branchId=${widget.branchId} -> GET /products?limit=500 + stock call below');
    if (_hasBranch && widget.pickerMode) {
      try {
        final bal = asList(await Api.get(
            '/stock/balances?branchId=${Uri.encodeQueryComponent('${widget.branchId}')}&limit=2000'));
        _branchStock.clear();
        for (final b in bal) {
          _branchStock[pick(b, ['productId'])] =
              num0(pick(b, ['qtyOnHand', 'qty']));
        }
      } catch (_) {}
    } else if (_hasBranch) {
      try {
        final cp = await Api.get(
            '/repair/parts?barcode=${Uri.encodeQueryComponent(pick(widget.terminal, [
              'barcode'
            ]))}&atmId=${Uri.encodeQueryComponent(pick(widget.atm, [
              'atmId'
            ]))}&branchId=${Uri.encodeQueryComponent('${widget.branchId}')}');
        _branchStock.clear();
        for (final e
            in (cp is Map ? asList(cp['parts']) : <Map<String, dynamic>>[])) {
          _branchStock['${e['id']}'] = num0(e['stock']);
        }
      } catch (_) {}
    }
    return Api.get('/products?limit=500');
  }

  void _reload() => setState(() {
        _f = _load();
      });

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  static String _n(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ກ-ໝ]'), '');

  late final String _type = _n(widget.terminalType);
  late final String _brandLabel =
      pick(widget.atm, ['atmType', 'atmBrand', 'brandName', 'brand']);
  // ATM model = ATM_VERSION column (atmVersion in the API)
  static const _atmModelKeys = [
    'atmVersion',
    'atm_version',
    'ATM_VERSION',
    'version',
    'atmModel',
    'atmModelName',
    'modelName',
    'model'
  ];
  late final String _modelLabel = pick(widget.atm, _atmModelKeys).isNotEmpty
      ? pick(widget.atm, _atmModelKeys)
      : pick(widget.terminal, ['atmVersion', 'atmModel', 'modelName', 'model']);
  // everything we know about the ATM's brand/model, normalised
  late final String _hay = _n([_brandLabel, _modelLabel].join(' '));

  bool _anyIn(String raw) {
    final toks =
        raw.split(RegExp(r'[,/;|]')).map(_n).where((e) => e.isNotEmpty);
    return toks.any((t) => _hay.contains(t));
  }

  /// model names of a product: models[] / modelNames[] / modelName / model
  String _models(Map<String, dynamic> m) {
    final out = <String>[];
    for (final k in ['models', 'modelNames']) {
      final v = m[k];
      if (v is List) {
        for (final e in v) {
          final t = e is Map ? pick(e, ['name', 'modelName']) : '$e';
          if (t.isNotEmpty && !out.contains(t)) out.add(t);
        }
      } else if (v is String && v.isNotEmpty) {
        out.add(v);
      }
    }
    final one = pick(m, ['modelName', 'model']);
    if (one.isNotEmpty && !out.contains(one)) out.add(one);
    return out.join(', ');
  }

  bool _ok(Map<String, dynamic> m) {
    if (_level >= 1 && _type.isNotEmpty) {
      final t = _n(pick(m, ['typeName']));
      if (t.isEmpty || !(t.contains(_type) || _type.contains(t))) return false;
    }
    // products with no brand / model set count as generic and always pass
    if (_level >= 2 && _brandLabel.isNotEmpty) {
      final b = pick(m, ['brandName']);
      if (b.trim().isNotEmpty && !_anyIn(b)) return false;
    }
    if (_level >= 3 && _modelLabel.isNotEmpty) {
      final md = _models(m);
      if (md.trim().isNotEmpty && !_anyIn(md)) return false;
    }
    final q = _q.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final text = [
        pick(m, ['name', 'productName']),
        pick(m, ['typeName']),
        pick(m, ['brandName']),
        _models(m),
        pick(m, ['code']),
      ].join(' ').toLowerCase();
      if (!text.contains(q)) return false;
    }
    return true;
  }

  /// Pre-fill the "add product" form from the terminal + ATM (all values can still be changed).
  /// Ids are resolved with loadOptions(), the same way the form builds its dropdowns.
  Future<Map<String, dynamic>> _autoFill() async {
    final init = <String, dynamic>{};
    dynamic find(List<Opt> opts, String name) {
      final nn = _n(name);
      if (nn.isEmpty) return null;
      for (final o in opts) {
        if (_n(o.value) == nn) return o.key;
      }
      return null;
    }

    // TYPE
    try {
      final types =
          await loadOptions('/terminal-types', 'typeId', const ['name']);
      dynamic t;
      if (widget.terminalTypeId.isNotEmpty) {
        for (final o in types) {
          if ('${o.key}' == widget.terminalTypeId) t = o.key;
        }
      }
      t ??= find(types, widget.terminalType) ??
          find(types, pick(widget.terminal, ['typeName']));
      if (t != null) init['typeId'] = t;
    } catch (_) {}

    // BRAND
    dynamic brandId;
    try {
      final brands = await loadOptions('/brands', 'id', const ['name']);
      brandId = find(brands, _brandLabel);
      if (brandId == null && _brandLabel.isNotEmpty) {
        final bn = _n(_brandLabel);
        for (final o in brands) {
          final nm = _n(o.value);
          if (nm.isNotEmpty && bn.contains(nm)) {
            brandId = o.key;
            break;
          }
        }
      }
      if (brandId != null) init['brandId'] = brandId;
    } catch (_) {}

    // MODEL(s): every model whose name appears in the ATM brand/model text
    try {
      if (_hay.isNotEmpty) {
        final models = await loadOptions('/models', 'id', const ['name']);
        final rows = asList(await Api.get('/models'));
        final brandOf = {
          for (final r in rows) _n(pick(r, ['name'])): pick(r, ['brandId'])
        };
        final ids = <dynamic>[];
        for (final o in models) {
          final nm = _n(o.value);
          if (nm.isEmpty) continue;
          final exact = _modelLabel.isNotEmpty && _n(_modelLabel) == nm;
          if (!exact && !(_modelLabel.isNotEmpty && _hay.contains(nm))) {
            continue;
          }
          final rb = brandOf[nm] ?? '';
          if (brandId != null && rb.isNotEmpty && rb != '$brandId') continue;
          ids.add(o.key);
        }
        if (ids.isNotEmpty) init['modelIds'] = ids;
      }
    } catch (_) {}
    return init;
  }

  Future<void> _add(CrudSpec spec) async {
    final init = await _autoFill();
    if (!mounted) return;
    final ok = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => CrudForm(spec, initial: init)));
    if (ok == true) _reload();
  }

  String _imageUrl(Map<String, dynamic> m) {
    final v = pick(m, ['imageUrl', 'image', 'photo', 'img', 'picture']);
    if (v.isEmpty || v.startsWith('data:') || v.startsWith('http')) return v;
    final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base${v.startsWith('/') ? '' : '/'}$v';
  }

  Widget _thumb(BuildContext context, String url) {
    final p = pal(context);
    final fallback = Container(
      width: 48,
      height: 48,
      decoration:
          BoxDecoration(color: p.bd, borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.settings_input_component_outlined, color: p.mut),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback),
    );
  }

  Widget _info(BuildContext context, String k, String v) {
    final p = pal(context);
    return Text('$k: ${v.isEmpty ? '-' : v}',
        style: TextStyle(color: p.mut, fontSize: 13));
  }

  Widget _chip(int lv, String label) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _level == lv,
          onSelected: (_) => setState(() => _level = lv),
        ),
      );

  Widget _tile(BuildContext context, Map<String, dynamic> m, CrudSpec? spec,
      bool canEdit) {
    final pid = pick(m, ['id', 'productId']);
    final branchQty = _branchStock[pid] ?? 0;
    final soldOut = _hasBranch && branchQty <= 0;
    final stock =
        _hasBranch ? fmtNum(branchQty.toDouble()) : pick(m, ['stock', 'qty']);
    return cardBox(
      context,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        isThreeLine: true,
        leading: _thumb(context, _imageUrl(m)),
        title: Text(pick(m, ['name', 'productName', 'id']),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _info(context, 'ປະເພດ', pick(m, ['typeName'])),
          _info(context, 'Brand', pick(m, ['brandName'])),
          _info(context, 'Model', _models(m)),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (stock.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(stock,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          if (canEdit && !widget.pickerMode) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'ແກ້ໄຂ',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final ok = await Navigator.push<bool>(context,
                    MaterialPageRoute(builder: (_) => CrudForm(spec!, row: m)));
                if (ok == true) _reload();
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'ລຶບ',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                if (await confirmDelete(context, spec!, m)) _reload();
              },
            ),
          ],
        ]),
        enabled: soldOut == false,
        onTap: soldOut ? null : () => Navigator.pop(context, m),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final spec = crudSpec('prod');
    final canEdit = spec != null && spec.canWrite;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ເລືອກອາໄຫຼ່ / ສິນຄ້າ'),
        actions: [
          if (canEdit && !widget.pickerMode)
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('ເພີ່ມ'),
              onPressed: () => _add(spec),
            ),
        ],
      ),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(children: [
            _chip(0, 'ທັງໝົດ'),
            if (widget.terminalType.isNotEmpty) _chip(1, widget.terminalType),
            if (_brandLabel.isNotEmpty) _chip(2, '› $_brandLabel'),
            if (_modelLabel.isNotEmpty) _chip(3, '› $_modelLabel'),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'ຄົ້ນຫາ',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => setState(_q.clear),
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: _f,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.hasError) return ErrorView(s.error!, _reload);
              final items = asList(s.data).where(_ok).toList();
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: items.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 120),
                        Center(
                            child: Text('ບໍ່ມີລາຍການ',
                                style: TextStyle(color: p.mut))),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: items.length,
                        itemBuilder: (_, i) =>
                            _tile(context, items[i], spec, canEdit),
                      ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
