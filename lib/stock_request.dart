import 'main_shell.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'pages.dart';
import 'theme.dart';
import 'widgets.dart';

const _reqStatus = <String, List<dynamic>>{
  'pending': ['ລໍຖ້າອະນຸມັດ', Colors.orange],
  'approved': ['ອະນຸມັດແລ້ວ', Colors.green],
  'rejected': ['ປະຕິເສດ', Colors.red],
  'cancelled': ['ຍົກເລີກ', Colors.grey],
};

Widget _statusChip(String st) {
  final info = _reqStatus[st];
  final Color c = info == null ? Colors.grey : info[1] as Color;
  final String label = info == null ? st : info[0] as String;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10)),
    child: Text(label,
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

class StockRequestsPage extends StatefulWidget {
  const StockRequestsPage({super.key});
  @override
  State<StockRequestsPage> createState() => _StockRequestsPageState();
}

class _StockRequestsPageState extends State<StockRequestsPage> {
  late Future<dynamic> _f = Api.get('/stock/requests');

  void _reload() => setState(() {
        _f = Api.get('/stock/requests');
      });

  dynamic get _mine => Api.user?['branchId'];

  bool _same(dynamic a, dynamic b) => '$a' == '$b';

  List<Map<String, dynamic>> _rowsFor(dynamic d, bool inbox) {
    final all = asList(d);
    if (_mine == null) return all;
    return all
        .where((r) => _same(inbox ? r['supBranchId'] : r['reqBranchId'], _mine))
        .toList();
  }

  Future<void> _act(Map<String, dynamic> r, String action, String done) async {
    try {
      await Api.post('/stock/requests/${r['id']}/$action', {});
      if (mounted == false) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _approve(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ອະນຸມັດ ແລະ ສົ່ງອາໄຫຼ່?'),
        content: const Text('ສະຕັອກຈະຖືກຕັດອອກຈາກສາຂາຂອງທ່ານທັນທີ'),
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
    if (ok == true) await _act(r, 'approve', 'ອະນຸມັດແລ້ວ ສ້າງໃບໂອນແລ້ວ');
  }

  Widget _card(Map<String, dynamic> r, bool inbox) {
    final p = pal(context);
    final st = pick(r, ['status']);
    final items =
        r['items'] is List ? asList(r['items']) : <Map<String, dynamic>>[];
    final lines = items
        .map((i) =>
            '${pick(i, ['productName', 'productId'])} × ${pick(i, ['qty'])}')
        .join('\n');
    final note = pick(r, ['note']);
    final canSend = Api.can('REQUEST_APPROVE');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          border: Border.all(color: p.bd),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(pick(r, ['requestNo', 'id']),
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          _statusChip(st),
        ]),
        const SizedBox(height: 2),
        Text('${pick(r, ['reqName'])} ຂໍຈາກ ${pick(r, ['supName'])}',
            style: TextStyle(color: p.mut, fontSize: 13)),
        if (lines.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(lines)),
        if (note.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note, style: TextStyle(color: p.mut, fontSize: 12))),
        if (st == 'pending')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, children: [
              if (inbox && canSend)
                FilledButton(
                    onPressed: () => _approve(r),
                    child: const Text('ອະນຸມັດ ແລະ ສົ່ງ')),
              if (inbox && canSend)
                OutlinedButton(
                    onPressed: () => _act(r, 'reject', 'ປະຕິເສດແລ້ວ'),
                    child: const Text('ປະຕິເສດ')),
              if (inbox == false)
                OutlinedButton(
                    onPressed: () => _act(r, 'cancel', 'ຍົກເລີກແລ້ວ'),
                    child: const Text('ຍົກເລີກຄຳຂໍ')),
            ]),
          ),
      ]),
    );
  }

  Widget _tab(bool inbox) => RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              futureBlock(_f, _reload, (d) {
                final rows = _rowsFor(d, inbox);
                if (rows.isEmpty) {
                  return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('ຍັງບໍ່ມີລາຍການ',
                          style: TextStyle(color: pal(context).mut)));
                }
                return Column(
                    children: [for (final r in rows) _card(r, inbox)]);
              }),
            ]),
      );

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        bottomNavigationBar: const ShellBar(),
        appBar: AppBar(
          title: const Text('ຂໍອາໄຫຼ່ລະຫວ່າງສາຂາ'),
          bottom: const TabBar(tabs: [
            Tab(text: 'ຄຳຂໍທີ່ເຂົ້າມາ'),
            Tab(text: 'ຄຳຂໍຂອງຂ້ອຍ'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final ok = await Navigator.push<bool>(context,
                MaterialPageRoute(builder: (_) => const StockRequestForm()));
            if (ok == true) _reload();
          },
          icon: const Icon(Icons.add),
          label: const Text('ຂໍອາໄຫຼ່'),
        ),
        body: TabBarView(children: [_tab(true), _tab(false)]),
      ),
    );
  }
}

class StockRequestForm extends StatefulWidget {
  final dynamic supBranchId;
  const StockRequestForm({super.key, this.supBranchId});
  @override
  State<StockRequestForm> createState() => _StockRequestFormState();
}

class _StockRequestFormState extends State<StockRequestForm> {
  final _lines = <Line>[];
  final _note = TextEditingController();
  List<Map<String, dynamic>> _branches = [];
  dynamic _req, _sup;
  List<dynamic> _allowed = [];
  List<Map<String, dynamic>> _sups = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _req = Api.user?['branchId'];
    _sup = widget.supBranchId;
    _loadAllowed();
    loadBranches().then((b) {
      if (mounted) {
        setState(() {
          _branches = b;
        });
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadAllowed() async {
    if (_req == null) return;
    try {
      final d = await Api.get('/stock/request-suppliers?reqBranchId=$_req');
      if (mounted) {
        setState(() {
          _allowed = d is List ? [for (final x in d) x['id']] : [];
          _sups = asList(d);
          if (_allowed.any((x) => '$x' == '$_sup') == false) _sup = null;
        });
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    if (_req == null) {
      return setState(() {
        _error = 'ເລືອກສາຂາທີ່ຂໍ';
      });
    }
    if (_sup == null) {
      return setState(() {
        _error = 'ເລືອກສາຂາທີ່ຈະຂໍອາໄຫຼ່ຈາກ';
      });
    }
    if ('$_req' == '$_sup') {
      return setState(() {
        _error = 'ສາຂາຕ້ອງຕ່າງກັນ';
      });
    }
    if (_lines.isEmpty) {
      return setState(() {
        _error = 'ເພີ່ມສິນຄ້າຢ່າງນ້ອຍ 1 ລາຍການ';
      });
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.post('/stock/requests', {
        'reqBranchId': _req,
        'supBranchId': _sup,
        'note': _note.text.trim(),
        'items': [
          for (final l in _lines) {'productId': l.product['id'], 'qty': l.qty}
        ],
      });
      if (mounted == false) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ສົ່ງຄຳຂໍແລ້ວ')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final supList = _sups;
    return Scaffold(
      bottomNavigationBar: const ShellBar(),
      appBar: AppBar(title: const Text('ຂໍອາໄຫຼ່ຈາກສາຂາອື່ນ')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (Api.user?['branchId'] == null) ...[
          branchDropdown('ສາຂາທີ່ຂໍ', _branches, _req, (v) {
            setState(() {
              _req = v;
              _sup = null;
              _allowed = [];
              _loadAllowed();
            });
          }),
          const SizedBox(height: 12),
        ],
        branchDropdown(
            supList.isEmpty ? 'ຂໍຈາກສາຂາ (ຍັງບໍ່ມີສິດຂໍ)' : 'ຂໍຈາກສາຂາ',
            supList,
            _sup, (v) {
          setState(() {
            _sup = v;
          });
        }),
        const SizedBox(height: 12),
        LineEditor(_lines),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'ໝາຍເຫດ'),
        ),
        if (_error is String)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('$_error', style: TextStyle(color: p.bad))),
        const SizedBox(height: 14),
        saveButton('ສົ່ງຄຳຂໍ', _busy, _send),
      ]),
    );
  }
}

class BranchRequestsBar extends StatelessWidget {
  const BranchRequestsBar({super.key});
  @override
  Widget build(BuildContext context) {
    if (Api.can('REQUEST_SEND') == false &&
        Api.can('REQUEST_APPROVE') == false) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const StockRequestsPage())),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('ຄຳຂໍອາໄຫຼ່ລະຫວ່າງສາຂາ'),
        ),
      ),
    );
  }
}

Widget branchRequestButton(BuildContext context, Map<String, dynamic> row) {
  final mine = Api.user?['branchId'];
  if ('${row['id']}' == '$mine') return const SizedBox.shrink();
  if (Api.can('REQUEST_SEND') == false && Api.can('REQUEST_APPROVE') == false) {
    return const SizedBox.shrink();
  }
  return TextButton.icon(
    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => StockRequestForm(supBranchId: row['id']))),
    icon: const Icon(Icons.inventory_2_outlined, size: 18),
    label: const Text('ຂໍອາໄຫຼ່'),
  );
}

class RequestSettingsBar extends StatelessWidget {
  const RequestSettingsBar({super.key});
  @override
  Widget build(BuildContext context) {
    if (Api.can('BRANCH_MANAGE') == false) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const RequestBranchesPage())),
          icon: const Icon(Icons.checklist, size: 18),
          label: const Text('ກຳນົດສາຂາທີ່ຂໍອາໄຫຼ່ໄດ້'),
        ),
      ),
    );
  }
}

class RequestBranchesPage extends StatefulWidget {
  const RequestBranchesPage({super.key});
  @override
  State<RequestBranchesPage> createState() => _RequestBranchesPageState();
}

class _RequestBranchesPageState extends State<RequestBranchesPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  Object? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/stock/request-branches');
      if (mounted) {
        setState(() {
          _rows = [for (final r in asList(d)) Map<String, dynamic>.from(r)];
          _loading = false;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _set(Map<String, dynamic> b, bool v) async {
    final old = b['canRequest'];
    setState(() {
      b['canRequest'] = v ? 1 : 0;
    });
    try {
      await Api.post('/stock/request-branches/${b['id']}', {'canRequest': v});
    } catch (e) {
      if (mounted) {
        setState(() {
          b['canRequest'] = old;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_err is Object) {
      body = ErrorView(_err ?? '', _load);
    } else {
      final n = _rows.where((r) => '${r['canRequest']}' == '1').length;
      body = ListView(padding: const EdgeInsets.all(16), children: [
        Text('ຕິກສາຂາທີ່ອະນຸຍາດໃຫ້ຂໍອາໄຫຼ່ຈາກສາຂາອື່ນ  ($n/${_rows.length})',
            style: TextStyle(color: p.mut)),
        const SizedBox(height: 8),
        for (final b in _rows)
          CheckboxListTile(
            value: '${b['canRequest']}' == '1',
            onChanged: (v) => _set(b, v == true),
            title: Text(pick(b, ['name'])),
            subtitle: Text(pick(b, ['code']), style: TextStyle(color: p.mut)),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('ກຳນົດສາຂາທີ່ຂໍອາໄຫຼ່ໄດ້')),
      body: body,
    );
  }
}

class BranchAccessResult {
  final List<dynamic> seeIds;
  final List<dynamic> reqIds;
  BranchAccessResult(this.seeIds, this.reqIds);
}

Future<BranchAccessResult?> pickBranchAccess(BuildContext context, String title,
    List<MapEntry<dynamic, String>> all, List<dynamic> see, List<dynamic> req) {
  final seeSet = <String>{for (final x in see) '$x'};
  final reqSet = <String>{for (final x in req) '$x'};
  return showDialog<BranchAccessResult>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) {
        return AlertDialog(
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('ກຳນົດສິດ: ເບິ່ງຂໍ້ມູນ ແລະ ຂໍອາໄຫຼ່',
                style: TextStyle(fontSize: 13))
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Row(children: [
                Expanded(child: SizedBox()),
                SizedBox(
                    width: 64,
                    child: Center(
                        child: Text('ເບິ່ງ',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)))),
                SizedBox(
                    width: 64,
                    child: Center(
                        child: Text('ຂໍອາໄຫຼ່',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)))),
              ]),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final o in all)
                    Row(children: [
                      Expanded(child: Text(o.value)),
                      SizedBox(
                        width: 64,
                        child: Center(
                          child: Checkbox(
                            value: seeSet.contains('${o.key}'),
                            onChanged: (v) => setS(() {
                              if (v == true) {
                                seeSet.add('${o.key}');
                              } else {
                                seeSet.remove('${o.key}');
                                reqSet.remove('${o.key}');
                              }
                            }),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Center(
                          child: Checkbox(
                            value: reqSet.contains('${o.key}'),
                            onChanged: (v) => setS(() {
                              if (v == true) {
                                reqSet.add('${o.key}');
                                seeSet.add('${o.key}');
                              } else {
                                reqSet.remove('${o.key}');
                              }
                            }),
                          ),
                        ),
                      ),
                    ]),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('ຍົກເລີກ')),
            FilledButton(
                onPressed: () => Navigator.pop(
                    c,
                    BranchAccessResult([
                      for (final o in all)
                        if (seeSet.contains('${o.key}')) o.key
                    ], [
                      for (final o in all)
                        if (reqSet.contains('${o.key}')) o.key
                    ])),
                child: const Text('ບັນທຶກ')),
          ],
        );
      },
    ),
  );
}

Future<List<dynamic>?> pickRequestBranches(BuildContext context, String title,
    List<MapEntry<dynamic, String>> all, List<dynamic> req) {
  final sel = <String>{for (final x in req) '$x'};
  return showDialog<List<dynamic>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) {
        return AlertDialog(
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('ຕິກສາຂາຫຼັກທີ່ຂໍອາໄຫຼ່ໄດ້ (Head Office ຂໍໄດ້ສະເໝີ)',
                style: TextStyle(fontSize: 13)),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              for (final o in all)
                CheckboxListTile(
                  value: sel.contains('${o.key}'),
                  onChanged: (v) => setS(() {
                    if (v == true) {
                      sel.add('${o.key}');
                    } else {
                      sel.remove('${o.key}');
                    }
                  }),
                  title: Text(o.value),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('ຍົກເລີກ')),
            FilledButton(
                onPressed: () => Navigator.pop(c, [
                      for (final o in all)
                        if (sel.contains('${o.key}')) o.key
                    ]),
                child: const Text('ບັນທຶກ')),
          ],
        );
      },
    ),
  );
}

Future<BranchAccessResult?> pickBranchPerms(
    BuildContext context,
    String title,
    List<MapEntry<dynamic, String>> all,
    Set<String> hqIds,
    List<dynamic> see,
    List<dynamic> req) {
  final seeSet = <String>{for (final x in see) '$x'};
  final reqSet = <String>{for (final x in req) '$x'};
  return showDialog<BranchAccessResult>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) {
        return AlertDialog(
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('ກຳນົດສິດ: ເບິ່ງຂໍ້ມູນ ແລະ ຂໍອາໄຫຼ່',
                style: TextStyle(fontSize: 13)),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Row(children: [
                Expanded(child: SizedBox()),
                SizedBox(
                    width: 64,
                    child: Center(
                        child: Text('ເບິ່ງ',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)))),
                SizedBox(
                    width: 64,
                    child: Center(
                        child: Text('ຂໍອາໄຫຼ່',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)))),
              ]),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final o in all)
                    Row(children: [
                      Expanded(child: Text(o.value)),
                      SizedBox(
                        width: 64,
                        child: Center(
                          child: Checkbox(
                            value: seeSet.contains('${o.key}'),
                            onChanged: (v) => setS(() {
                              if (v == true) {
                                seeSet.add('${o.key}');
                              } else {
                                seeSet.remove('${o.key}');
                              }
                            }),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Center(
                          child: Checkbox(
                            value: hqIds.contains('${o.key}') ||
                                reqSet.contains('${o.key}'),
                            onChanged: hqIds.contains('${o.key}')
                                ? null
                                : (v) => setS(() {
                                      if (v == true) {
                                        reqSet.add('${o.key}');
                                      } else {
                                        reqSet.remove('${o.key}');
                                      }
                                    }),
                          ),
                        ),
                      ),
                    ]),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('ຍົກເລີກ')),
            FilledButton(
                onPressed: () => Navigator.pop(
                    c,
                    BranchAccessResult([
                      for (final o in all)
                        if (seeSet.contains('${o.key}')) o.key
                    ], [
                      for (final o in all)
                        if (reqSet.contains('${o.key}') &&
                            hqIds.contains('${o.key}') == false)
                          o.key
                    ])),
                child: const Text('ບັນທຶກ')),
          ],
        );
      },
    ),
  );
}

class BranchRequestInfo extends StatefulWidget {
  final dynamic branchId;
  const BranchRequestInfo(this.branchId, {super.key});
  @override
  State<BranchRequestInfo> createState() => _BranchRequestInfoState();
}

class _BranchRequestInfoState extends State<BranchRequestInfo> {
  late Future<List<String>> _f = _load();

  Future<List<String>> _load() async {
    final list = await loadBranches();
    final self =
        list.where((b) => '${b['id']}' == '${widget.branchId}').toList();
    if (self.isNotEmpty && '${self.first['isHq']}' == '1') {
      return ['ທຸກສາຂາ'];
    }
    final perms = await Api.get('/branches/${widget.branchId}/branch-perms');
    final req =
        perms is Map && perms['reqIds'] is List ? perms['reqIds'] as List : [];
    final names = <String>[];
    for (final b in list) {
      if ('${b['id']}' == '${widget.branchId}') continue;
      final isHq = '${b['isHq']}' == '1';
      final ticked = req.any((x) => '$x' == '${b['id']}');
      if (isHq) {
        names.insert(0, pick(b, ['name']));
      } else if (ticked) {
        names.add(pick(b, ['name']));
      }
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'ສາຂາທີ່ຂໍອາໄຫຼ່ໄດ້',
      child: futureBlock(_f, () {
        setState(() {
          _f = _load();
        });
      }, (d) {
        final names = d is List ? d : [];
        if (names.isEmpty) return const Text('ຍັງບໍ່ມີ');
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final n in names)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('$n')),
              ]),
            ),
        ]);
      }),
    );
  }
}
