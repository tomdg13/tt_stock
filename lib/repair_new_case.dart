import 'package:flutter/material.dart';
import 'api.dart';
import 'crud.dart' show toastMsg;
import 'repair_case.dart' show RepairStepForm;
import 'theme.dart';
import 'widgets.dart';

/// Opens a repair case with the NEW server flow:
/// POST /repair/cases (JSON: barcode, atmId, branchId, remark, parts) -> step 0,
/// then the existing RepairStepForm uploads the signed request form as step 1.
class RepairNewCasePage extends StatefulWidget {
  final String barcode, atmId;
  const RepairNewCasePage({super.key, required this.barcode, this.atmId = ''});
  @override
  State<RepairNewCasePage> createState() => _RepairNewCasePageState();
}

class _RepairNewCasePageState extends State<RepairNewCasePage> {
  final _search = TextEditingController();
  final _remark = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  final Map<String, int> _qty = {};
  final Map<String, String> _names = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _search.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final pr = asList(await Api.get('/products?limit=500'));
      if (mounted == false) return;
      setState(() {
        _products = pr;
        _loading = false;
      });
    } catch (e) {
      if (mounted == false) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  void _add(Map<String, dynamic> x) {
    final id = pick(x, ['id']);
    if (id.isEmpty) return;
    setState(() {
      _names[id] = pick(x, ['name', 'id']);
      _qty[id] = (_qty[id] ?? 0) + 1;
    });
  }

  void _change(String id, int d) {
    final n = (_qty[id] ?? 0) + d;
    setState(() {
      if (n <= 0) {
        _qty.remove(id);
      } else {
        _qty[id] = n;
      }
    });
  }

  Future<void> _save() async {
    if (_qty.isEmpty) {
      setState(() => _error = 'ກະລຸນາເລືອກອາໄຫຼ່ຢ່າງໜ້ອຍ 1 ລາຍການ');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final remark = _remark.text.trim();
      final body = <String, dynamic>{
        'barcode': widget.barcode,
        if (widget.atmId.isNotEmpty) 'atmId': widget.atmId,
        if (remark.isNotEmpty) 'remark': remark,
        'parts': [
          for (final e in _qty.entries)
            {'productId': int.tryParse(e.key) ?? e.key, 'qty': e.value}
        ],
      };
      final r = await Api.post('/repair/cases', body);
      final caseId = r is Map ? int.tryParse('${r['caseId']}') : null;
      if (mounted == false) return;
      toastMsg(context, 'ເປີດເຄດແລ້ວ');
      if (caseId is int) {
        await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => RepairStepForm(
                    stepNo: 1,
                    caseId: caseId,
                    barcode: widget.barcode,
                    atmId: widget.atmId)));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final q = _search.text.trim().toLowerCase();
    final shown = _products
        .where((x) =>
            q.isEmpty ||
            pick(x, ['name']).toLowerCase().contains(q) ||
            pick(x, ['partNo']).toLowerCase().contains(q))
        .take(30)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text('ເປີດເຄດສ້ອມ · ${widget.barcode}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('ອາໄຫຼ່ທີ່ຈະໃຊ້',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_qty.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child:
                Text('ຍັງບໍ່ໄດ້ເລືອກອາໄຫຼ່', style: TextStyle(color: p.mut)),
          ),
        for (final e in _qty.entries)
          cardBox(
            context,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(_names[e.key] ?? e.key,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _change(e.key, -1)),
                Text('${e.value}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _change(e.key, 1)),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'ຄົ້ນຫາອາໄຫຼ່ (ຊື່ ຫຼື ລະຫັດ)',
              border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (_loading) const Center(child: CircularProgressIndicator()),
        for (final x in shown)
          ListTile(
            dense: true,
            title: Text(pick(x, ['name'])),
            subtitle: pick(x, ['partNo']).isEmpty
                ? null
                : Text(pick(x, ['partNo']),
                    style: TextStyle(color: p.mut, fontSize: 12)),
            trailing: const Icon(Icons.add),
            onTap: () => _add(x),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _remark,
          maxLines: 2,
          decoration: const InputDecoration(
              labelText: 'ໝາຍເຫດ', border: OutlineInputBorder()),
        ),
        if (_error is String)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error ?? '', style: TextStyle(color: p.bad)),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.arrow_forward),
          label: const Text('ຖັດໄປ: ແນບໃບຂໍ (ຂັ້ນ 1)'),
        ),
      ]),
    );
  }
}
