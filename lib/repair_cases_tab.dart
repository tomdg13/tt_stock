import 'package:flutter/material.dart';
import 'api.dart';
import 'repair_case.dart';
import 'widgets.dart';

/// Tab: list of repair cases for one terminal (GET /repair/cases?barcode=).
class RepairCasesTab extends StatefulWidget {
  final String barcode;
  final Future<void> Function()? onOpenCase;
  const RepairCasesTab(this.barcode, {super.key, this.onOpenCase});
  @override
  State<RepairCasesTab> createState() => _RepairCasesTabState();
}

class _RepairCasesTabState extends State<RepairCasesTab> {
  late Future<Map<String, dynamic>> _f = _load();

  Future<Map<String, dynamic>> _load() async {
    final d = await Api.get(
        '/repair/cases?barcode=${Uri.encodeQueryComponent(widget.barcode)}');
    return {'cases': asList(d), 'side': await repairMySide()};
  }

  void _reload() => setState(() {
        _f = _load();
      });

  Future<void> _open(Map<String, dynamic> c, String side) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                RepairCasePage(c, barcode: widget.barcode, side: side)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _body(context),
      floatingActionButton: widget.onOpenCase == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await widget.onOpenCase!();
                if (mounted) _reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('ເປີດເຄດສ້ອມ'),
            ),
    );
  }

  Widget _body(BuildContext context) {
    final mut = Theme.of(context).hintColor;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<Map<String, dynamic>>(
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
          final cases =
              (snap.data!['cases'] as List).cast<Map<String, dynamic>>();
          final side = '${snap.data!['side']}';
          if (cases.isEmpty) {
            return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(32),
                children: [
                  Center(
                      child: Text('ຍັງບໍ່ມີເຄດສ້ອມ',
                          style: TextStyle(color: mut))),
                ]);
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              for (final k in cases)
                Builder(builder: (_) {
                  final cur = int.tryParse('${k['currentStep']}') ?? 0;
                  final closed = '${k['status']}' == 'CLOSED';
                  final doneName = (cur >= 1 && cur <= kRepairSteps.length)
                      ? kRepairSteps[cur - 1]
                      : '-';
                  final nextName =
                      cur < kRepairSteps.length ? kRepairSteps[cur] : '-';
                  final stepName = closed
                      ? 'ສຳເລັດແລ້ວ'
                      : 'ແລ້ວ: $doneName\nຕໍ່ໄປ: ຂັ້ນ ${cur + 1} $nextName';
                  return Card(
                    child: ListTile(
                      onTap: () => _open(k, side),
                      leading: CircleAvatar(
                        backgroundColor: closed ? Colors.green : null,
                        child: closed
                            ? const Icon(Icons.check, color: Colors.white)
                            : Text('$cur/7'),
                      ),
                      title: Text('ເຄດ #${k['caseId']}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(stepName),
                      trailing: Text(closed ? 'ປິດແລ້ວ' : '${k['status'] ?? ''}',
                          style: TextStyle(color: mut)),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
