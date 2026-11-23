import 'package:flutter/material.dart';
import 'api.dart';
import 'repair_case.dart' show RepairCasePage, repairMySide, caseChipText;

/// Head Office: spare-part requests (repair cases) of all branches.
/// Server: GET /repair/cases (every case the user may see), GET /repair/branches.
class RepairRequestsAllPage extends StatefulWidget {
  const RepairRequestsAllPage({super.key});
  @override
  State<RepairRequestsAllPage> createState() => _RepairRequestsAllPageState();
}

class _RepairRequestsAllPageState extends State<RepairRequestsAllPage> {
  late Future<Map<String, dynamic>> _f = _load();
  String _status = 'hq'; // hq | branch | closed | all
  String _branch = ''; // '' = all branches
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final cases = await Api.get('/repair/cases');
    final branches = await Api.get('/repair/branches');
    final side = await repairMySide();
    debugPrint(
        '[RQ] cases=${cases is List ? cases.length : cases} side=$side');
    return {
      'cases': [
        for (final c in (cases is List ? cases : const []))
          if (c is Map) Map<String, dynamic>.from(c)
      ],
      'branches': {
        for (final b in (branches is List ? branches : const []))
          if (b is Map) '${b['id']}': '${b['name'] ?? b['id']}'
      },
      'side': side,
    };
  }

  void _reload() => setState(() {
        _f = _load();
      });

  static bool _match(Map<String, dynamic> c, String st) {
    final closed = '${c['status']}' == 'CLOSED';
    final next = '${c['nextSide'] ?? ''}';
    switch (st) {
      case 'hq':
        return !closed && next == 'hq';
      case 'branch':
        return !closed && next == 'branch';
      case 'closed':
        return closed;
      default:
        return true;
    }
  }

  static String _parts(Map<String, dynamic> c) {
    final parts = c['parts'] is List ? c['parts'] as List : const [];
    return [
      for (final p in parts)
        if (p is Map) '${p['name'] ?? p['productId']} x${p['qty']}'
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final mut = Theme.of(context).hintColor;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('ຄຳຂໍອາໄຫຼ່ທຸກສາຂາ'),
        bottom: const TabBar(tabs: [
          Tab(text: 'ລາຍການ'),
          Tab(text: 'ລວມອາໄຫຼ່'),
        ]),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (c, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(padding: const EdgeInsets.all(24), children: [
              Text('${snap.error}'),
              TextButton(onPressed: _reload, child: const Text('ລອງໃໝ່')),
            ]);
          }
          final d = snap.data!;
          final all = (d['cases'] as List).cast<Map<String, dynamic>>();
          final names = (d['branches'] as Map).cast<String, String>();
          final side = '${d['side']}';
          String bname(Map<String, dynamic> k) =>
              names['${k['branchId']}'] ?? 'ສາຂາ ${k['branchId']}';

          final ids = {for (final k in all) '${k['branchId']}'}.toList()
            ..sort((a, b) => (names[a] ?? a).compareTo(names[b] ?? b));
          final q = _q.text.trim().toLowerCase();
          final rows = all.where((k) {
            if (!_match(k, _status)) return false;
            if (_branch.isNotEmpty && '${k['branchId']}' != _branch) {
              return false;
            }
            if (q.isEmpty) return true;
            final text = [
              '${k['reqNo'] ?? ''}',
              '${k['barcode'] ?? ''}',
              '${k['atmId'] ?? ''}',
              bname(k),
              _parts(k),
            ].join(' ').toLowerCase();
            return text.contains(q);
          }).toList();

          int cnt(String st) => all.where((k) => _match(k, st)).length;
          Widget chip(String key, String label) => ChoiceChip(
                label: Text('$label (${cnt(key)})'),
                selected: _status == key,
                onSelected: (_) => setState(() => _status = key),
              );

          return TabBarView(children: [
            Column(children: [
            if (side == 'branch')
              Container(
                width: double.infinity,
                color: Colors.amber.withValues(alpha: 0.2),
                padding: const EdgeInsets.all(8),
                child: const Text(
                    'ເມນູນີ້ສຳລັບ Head Office. ທ່ານເຫັນສະເພາະເຄດຂອງສາຂາທ່ານ.'),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                chip('hq', 'ລໍຖ້າ HQ'),
                chip('branch', 'ລໍຖ້າສາຂາ'),
                chip('closed', 'ປິດແລ້ວ'),
                chip('all', 'ທັງໝົດ'),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _q,
                    decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ຄົ້ນຫາ RC / Terminal / ATM / ອາໄຫຼ່',
                        border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: ids.contains(_branch) ? _branch : '',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('ທຸກສາຂາ')),
                    for (final id in ids)
                      DropdownMenuItem(
                          value: id, child: Text(names[id] ?? 'ສາຂາ $id')),
                  ],
                  onChanged: (v) => setState(() => _branch = v ?? ''),
                ),
              ]),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: rows.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(32),
                        children: [
                          Center(
                              child: Text('ບໍ່ມີລາຍການ',
                                  style: TextStyle(color: mut))),
                        ])
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final k = rows[i];
                          final closed = '${k['status']}' == 'CLOSED';
                          final next = '${k['nextSide'] ?? ''}';
                          final label = closed
                              ? 'ປິດແລ້ວ'
                              : next == 'hq'
                                  ? 'ຄິວ HQ'
                                  : 'ຄິວສາຂາ';
                          final color = closed
                              ? Colors.green
                              : next == 'hq'
                                  ? Colors.orange
                                  : Colors.blue;
                          return ListTile(
                            isThreeLine: true,
                            title: Text('${k['reqNo'] ?? k['caseId']} · ${bname(k)}'),
                            subtitle: Text(
                                '${k['barcode'] ?? ''} · ATM ${k['atmId'] ?? ''}\n${_parts(k)}\n${caseChipText(k)}'),
                            trailing: Chip(
                              label: Text(label),
                              backgroundColor: color.withValues(alpha: 0.15),
                              side: BorderSide(color: color),
                              visualDensity: VisualDensity.compact,
                            ),
                            onTap: () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => RepairCasePage(k,
                                          barcode: '${k['barcode'] ?? ''}',
                                          side: side)));
                              if (mounted) _reload();
                            },
                          );
                        },
                      ),
              ),
            ),
          ]),
            _SummaryTab(all, names),
          ]);
        },
      ),
      ),
    );
  }
}

/// Second tab: total quantity of every spare part asked in the open cases of all branches.
class _SummaryTab extends StatefulWidget {
  final List<Map<String, dynamic>> cases;
  final Map<String, String> names;
  const _SummaryTab(this.cases, this.names);
  @override
  State<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<_SummaryTab> {
  bool _hqOnly = false;

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final mut = Theme.of(context).hintColor;
    final by = <String, Map<String, dynamic>>{};
    var nCases = 0;
    for (final c in widget.cases) {
      if ('${c['status']}' == 'CLOSED') continue;
      if (_hqOnly && '${c['nextSide'] ?? ''}' != 'hq') continue;
      nCases++;
      final parts = c['parts'] is List ? c['parts'] as List : const [];
      for (final p in parts) {
        if (p is! Map) continue;
        final id = '${p['productId']}';
        final e = by.putIfAbsent(
            id,
            () => <String, dynamic>{
                  'name': '${p['name'] ?? id}',
                  'partNo': '${p['partNo'] ?? ''}',
                  'unit': '${p['unit'] ?? ''}',
                  'qty': 0.0,
                  'cases': <String>{},
                  'branches': <String>{},
                });
        e['qty'] =
            (e['qty'] as double) + (double.tryParse('${p['qty']}') ?? 0);
        (e['cases'] as Set<String>).add('${c['caseId']}');
        (e['branches'] as Set<String>)
            .add(widget.names['${c['branchId']}'] ?? 'ສາຂາ ${c['branchId']}');
      }
    }
    final rows = by.values.toList()
      ..sort((a, b) => (b['qty'] as double).compareTo(a['qty'] as double));
    final total = rows.fold<double>(0, (t, e) => t + (e['qty'] as double));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          Expanded(
            child: Text(
                'ເຄດທີ່ຍັງເປີດ $nCases · ອາໄຫຼ່ ${rows.length} ລາຍການ · ລວມ ${_num(total)} ອັນ'),
          ),
          FilterChip(
            label: const Text('ສະເພາະຄິວ HQ'),
            selected: _hqOnly,
            onSelected: (v) => setState(() => _hqOnly = v),
          ),
        ]),
      ),
      const Divider(height: 16),
      Expanded(
        child: rows.isEmpty
            ? ListView(padding: const EdgeInsets.all(32), children: [
                Center(
                    child: Text('ບໍ່ມີອາໄຫຼ່ທີ່ຖືກຂໍ',
                        style: TextStyle(color: mut))),
              ])
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = rows[i];
                  final partNo = '${e['partNo']}';
                  final br = (e['branches'] as Set<String>).toList()..sort();
                  return ListTile(
                    title: Text(
                        '${e['name']}${partNo.isEmpty ? '' : ' · $partNo'}'),
                    subtitle: Text(
                        '${(e['cases'] as Set<String>).length} ເຄດ · ${br.join(', ')}'),
                    trailing: Text(
                        '${_num(e['qty'] as double)} ${e['unit']}'.trim(),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  );
                },
              ),
      ),
    ]);
  }
}
