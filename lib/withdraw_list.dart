import 'package:flutter/material.dart';
import 'api.dart';
import 'withdraw_page.dart';
import 'main_shell.dart';

/// ລາຍການເບີກ + ກວດຄືນ (ໃຊ້ແລ້ວ / ຄືນ)
class WithdrawListPage extends StatefulWidget {
  const WithdrawListPage({super.key});
  @override
  State<WithdrawListPage> createState() => _WithdrawListPageState();
}

class _WithdrawListPageState extends State<WithdrawListPage> {
  late Future<dynamic> _f = Api.get('/withdrawals');

  void _reload() => setState(() => _f = Api.get('/withdrawals'));

  Future<void> _check(Map w) async {
    final items = (w['items'] as List? ?? []).cast<Map>();
    final used = {for (final i in items) '${i['id']}': TextEditingController(text: '${i['qtyUsed'] ?? 0}')};
    final ret = {for (final i in items) '${i['id']}': TextEditingController(text: '${i['qtyReturned'] ?? 0}')};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('ກວດຄືນ ${w['withdrawNo'] ?? w['id']}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final i in items) ...[
              Text('${i['productName']}  (ເບີກ ${i['qty']})'),
              Row(children: [
                Expanded(child: TextField(controller: used['${i['id']}'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ໃຊ້ແລ້ວ'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: ret['${i['id']}'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ຄືນ'))),
              ]),
              const SizedBox(height: 12),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ຍົກເລີກ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ປິດລາຍການ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/withdrawals/${w['id']}/return', {
        'items': [
          for (final i in items)
            {
              'id': i['id'],
              'qtyUsed': int.tryParse(used['${i['id']}']!.text) ?? 0,
              'qtyReturned': int.tryParse(ret['${i['id']}']!.text) ?? 0,
            }
        ],
      });
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ລາຍການເບີກອາໄຫຼ່')),
      bottomNavigationBar: const ShellBar(),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('ເບີກໃໝ່'),
        onPressed: () async {
          final r = await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const WithdrawPage()));
          if (r == true) _reload();
        },
      ),
      body: FutureBuilder<dynamic>(
        future: _f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) return Center(child: Text('${s.error}'));
          final rows = s.data is List ? s.data as List : [];
          if (rows.isEmpty) return const Center(child: Text('ຍັງບໍ່ມີລາຍການເບີກ'));
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final w = rows[i] as Map;
              return ListTile(
                title: Text('${w['withdrawNo'] ?? w['id']} · ${w['branchName'] ?? ''}'),
                subtitle: Text('${w['createdAt'] ?? ''} · ${w['status'] ?? ''}'),
                trailing: const Icon(Icons.fact_check_outlined),
                onTap: () => _check(w),
              );
            },
          );
        },
      ),
    );
  }
}
