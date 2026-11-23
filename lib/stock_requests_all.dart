import 'package:flutter/material.dart';
import 'api.dart';

/// Stock requests between branches, all branches the user may see.
/// Server: GET /stock/requests, POST /stock/requests/:id/approve | reject.
class StockRequestsAllPage extends StatefulWidget {
  const StockRequestsAllPage({super.key});
  @override
  State<StockRequestsAllPage> createState() => _StockRequestsAllPageState();
}

class _StockRequestsAllPageState extends State<StockRequestsAllPage> {
  late Future<List<Map<String, dynamic>>> _f = _load();
  String _status = '';
  String _branch = '';
  final _q = TextEditingController();

  dynamic get _mine => Api.user?['branchId'];

  static const _stLabel = {
    'pending': 'ລໍຖ້າອະນຸມັດ',
    'approved': 'ອະນຸມັດແລ້ວ',
    'rejected': 'ປະຕິເສດ',
    'cancelled': 'ຍົກເລີກ',
    'canceled': 'ຍົກເລີກ',
  };

  static String _s(dynamic v) => v == null ? '' : '$v';

  static String _label(String st) => _stLabel[st] ?? st;

  static Color _color(String st) => st == 'pending'
      ? Colors.orange
      : st == 'approved'
          ? Colors.green
          : st == 'rejected'
              ? Colors.red
              : Colors.grey;

  static String _items(Map<String, dynamic> r) {
    final items = r['items'] is List ? r['items'] as List : const [];
    return [
      for (final i in items)
        if (i is Map) '${_s(i['productName'] ?? i['productId'])} × ${_s(i['qty'])}'
    ].join('\n');
  }

  static String _when(dynamic v) {
    final s = _s(v).replaceFirst('T', ' ');
    return s.length >= 16 ? s.substring(0, 16) : s;
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final d = await Api.get('/stock/requests');
    debugPrint('[RQB] stock requests: ${d is List ? d.length : d}');
    return [
      for (final r in (d is List ? d : const []))
        if (r is Map) Map<String, dynamic>.from(r)
    ];
  }

  void _reload() => setState(() {
        _f = _load();
      });

  bool _canAct(Map<String, dynamic> r) =>
      _s(r['status']) == 'pending' &&
      Api.can('REQUEST_APPROVE') &&
      _mine != null &&
      _s(r['supBranchId']) == '$_mine';

  Future<void> _act(Map<String, dynamic> r, String action, String done) async {
    try {
      debugPrint('[RQB] $action request ${r['id']}');
      await Api.post('/stock/requests/${r['id']}/$action', {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      _reload();
    } catch (e) {
      debugPrint('[RQB] $action failed: $e');
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

  void _detail(Map<String, dynamic> r) {
    final st = _s(r['status']);
    final note = _s(r['note']);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_s(r['requestNo'] ?? r['id']),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('${_s(r['reqName'])}  ຂໍຈາກ  ${_s(r['supName'])}'),
                const SizedBox(height: 4),
                Text('ສະຖານະ: ${_label(st)}'),
                if (_when(r['createdAt']).isNotEmpty)
                  Text('ວັນທີ: ${_when(r['createdAt'])}'),
                const SizedBox(height: 10),
                const Text('ອາໄຫຼ່ທີ່ຂໍ',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_items(r).isEmpty ? '-' : _items(r)),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('ໝາຍເຫດ: $note'),
                ],
                if (_canAct(r)) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(c);
                          _act(r, 'reject', 'ປະຕິເສດແລ້ວ');
                        },
                        child: const Text('ປະຕິເສດ'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(c);
                          _approve(r);
                        },
                        child: const Text('ອະນຸມັດ ແລະ ສົ່ງ'),
                      ),
                    ),
                  ]),
                ],
              ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mut = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(title: const Text('ຄຳຂໍລະຫວ່າງສາຂາ (ທຸກສາຂາ)')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
          final all = snap.data ?? [];
          final statuses = <String>{for (final r in all) _s(r['status'])}
            ..remove('');
          final names = <String>{
            for (final r in all) ...[_s(r['reqName']), _s(r['supName'])]
          }..remove('');
          final stList = statuses.toList()..sort();
          final nameList = names.toList()..sort();
          final q = _q.text.trim().toLowerCase();
          final rows = all.where((r) {
            if (_status.isNotEmpty && _s(r['status']) != _status) return false;
            if (_branch.isNotEmpty &&
                _s(r['reqName']) != _branch &&
                _s(r['supName']) != _branch) {
              return false;
            }
            if (q.isEmpty) return true;
            return '${_s(r['requestNo'])} ${_s(r['reqName'])} ${_s(r['supName'])} ${_items(r)}'
                .toLowerCase()
                .contains(q);
          }).toList();

          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                ChoiceChip(
                  label: Text('ທັງໝົດ (${all.length})'),
                  selected: _status.isEmpty,
                  onSelected: (_) => setState(() => _status = ''),
                ),
                for (final st in stList)
                  ChoiceChip(
                    label: Text(
                        '${_label(st)} (${all.where((r) => _s(r['status']) == st).length})'),
                    selected: _status == st,
                    onSelected: (_) => setState(() => _status = st),
                  ),
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
                        hintText: 'ຄົ້ນຫາ ເລກຄຳຂໍ / ສາຂາ / ອາໄຫຼ່',
                        border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: nameList.contains(_branch) ? _branch : '',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('ທຸກສາຂາ')),
                    for (final n in nameList)
                      DropdownMenuItem(value: n, child: Text(n)),
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
                          final r = rows[i];
                          final st = _s(r['status']);
                          return ListTile(
                            isThreeLine: true,
                            title: Text(
                                '${_s(r['requestNo'] ?? r['id'])} · ${_s(r['reqName'])} → ${_s(r['supName'])}'),
                            subtitle: Text(_items(r)),
                            trailing: Chip(
                              label: Text(_label(st)),
                              backgroundColor: _color(st).withValues(alpha: 0.15),
                              side: BorderSide(color: _color(st)),
                              visualDensity: VisualDensity.compact,
                            ),
                            onTap: () => _detail(r),
                          );
                        },
                      ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
