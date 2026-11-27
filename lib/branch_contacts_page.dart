import 'package:flutter/material.dart';
import 'api.dart';

/// Sticker address and phone of every branch (GET/POST /branch-contacts, table TT_BRANCH_CONTACT).
class BranchContactsPage extends StatefulWidget {
  const BranchContactsPage({super.key});
  @override
  State<BranchContactsPage> createState() => _BranchContactsPageState();
}

class _BranchContactsPageState extends State<BranchContactsPage> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final d = await Api.get('/branch-contacts');
    if (d is List) {
      return [
        for (final x in d)
          if (x is Map) Map<String, dynamic>.from(x)
      ];
    }
    return <Map<String, dynamic>>[];
  }

  void _reload() => setState(() {
        _f = _load();
      });

  Future<void> _edit(Map<String, dynamic> br) async {
    final ac = TextEditingController(text: '${br['address'] ?? ''}');
    final pc = TextEditingController(text: '${br['phone'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${br['name'] ?? ''}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: ac,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'ທີ່ຢູ່', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: pc,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'ເບີໂທ', border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ຍົກເລີກ')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('ບັນທຶກ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/branch-contacts/${br['id']}',
          {'address': ac.text.trim(), 'phone': pc.text.trim()});
      _reload();
    } catch (e) {
      if (mounted == false) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mut = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(title: const Text('ທີ່ຢູ່ ແລະ ເບີໂທສາຂາ')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (c, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          final rows = snap.data ?? [];
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i];
              final addr = '${r['address'] ?? ''}';
              final ph = '${r['phone'] ?? ''}';
              return ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text('${r['code'] ?? ''} · ${r['name'] ?? ''}'),
                subtitle: Text(
                    addr.isEmpty && ph.isEmpty
                        ? 'ຍັງບໍ່ມີຂໍ້ມູນ'
                        : [addr, ph].where((x) => x.isNotEmpty).join('\n'),
                    style: TextStyle(color: addr.isEmpty && ph.isEmpty ? mut : null)),
                isThreeLine: addr.isNotEmpty && ph.isNotEmpty,
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _edit(r),
              );
            },
          );
        },
      ),
    );
  }
}
