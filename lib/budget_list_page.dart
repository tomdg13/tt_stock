// Budget list: saved budgets (name, branch, period, year-end, %, total).
// Tap a row -> BudgetPage with the saved settings. "+" -> new budget.
// Server: GET /stock/budget-plans, DELETE /stock/budget-plans/:id
import 'package:flutter/material.dart';
import 'api.dart';
import 'budget_page.dart';

String _money(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (v < 0 ? '-' : '') + b.toString();
}

num _num(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

class BudgetListPage extends StatefulWidget {
  const BudgetListPage({super.key});
  @override
  State<BudgetListPage> createState() => _BudgetListPageState();
}

class _BudgetListPageState extends State<BudgetListPage> {
  late Future<List<Map<String, dynamic>>> _f;

  @override
  void initState() {
    super.initState();
    _f = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    var d = await Api.get('/stock/budget-plans');
    if (d is Map && d['data'] != null) d = d['data'];
    if (d is! List) return [];
    return [
      for (final x in d)
        if (x is Map) Map<String, dynamic>.from(x)
    ];
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _open([Map<String, dynamic>? plan]) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => BudgetPage(plan: plan)));
    if (mounted) _reload();
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ລຶບງົບປະມານ'),
        content: Text('ລຶບ "${p['name'] ?? ''}" ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('ລຶບ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete('/stock/budget-plans/${p['id']}');
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ລຶບບໍ່ສຳເລັດ: $e')));
      }
    }
  }

  Widget _card(Map<String, dynamic> p) {
    final fm = _num(p['fm']).toInt();
    final branch = '${p['branchName'] ?? ''}'.trim();
    final created = '${p['createdAt'] ?? ''}';
    final date = created.length >= 10 ? created.substring(0, 10) : created;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _open(p),
        title: Text('${p['name'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${branch.isEmpty ? 'ທຸກສາຂາ' : branch}  •  '
            '${fm == 10 ? 'ຕຸລາ - ກັນຍາ' : 'ມັງກອນ - ທັນວາ'}\n'
            'ຮອດ ${p['toYear']}  •  ເຜື່ອ ${_num(p['pct']).toInt()}%'
            '${date.isEmpty ? '' : '  •  $date'}'),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_money(_num(p['totalAmount'])),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'del') _delete(p);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'del', child: Text('ລຶບ')),
            ],
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ງົບປະມານອາໄຫຼ່')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('ສ້າງງົບປະມານ'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _f;
        },
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(padding: const EdgeInsets.all(16), children: [
                Text('${snap.error}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
                FilledButton(
                    onPressed: _reload, child: const Text('ລອງໃໝ່')),
              ]);
            }
            final rows = snap.data ?? [];
            if (rows.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('ຍັງບໍ່ມີງົບປະມານ')),
              ]);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [for (final p in rows) _card(p)],
            );
          },
        ),
      ),
    );
  }
}
