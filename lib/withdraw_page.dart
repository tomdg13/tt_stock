import 'package:flutter/material.dart';
import 'api.dart';
import 'withdraw_bill.dart';
import 'terminal_actions.dart' show ScanBarcodePage;

/// ເບີກອາໄຫຼ່: ເລືອກສາຂາ, ສະແກນອາໄຫຼ່, ບັນທຶກເປັນລາຍການ
class WithdrawPage extends StatefulWidget {
  final String barcode, atmId;
  const WithdrawPage({super.key, this.barcode = '', this.atmId = ''});
  @override
  State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  List<dynamic> _branches = [];
  dynamic _branchId;
  final Map<String, String> _names = {};
  final Map<String, int> _qty = {};
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    debugPrint('[WD] page open barcode=${widget.barcode} atmId=${widget.atmId}');
    Api.get('/repair/branches').then((d) {
      debugPrint('[WD] branches loaded: ${d is List ? d.length : d}');
      if (!mounted) return;
      setState(() => _branches = d is List ? d : []);
    });
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _scan() async {
    debugPrint('[WD] scan tapped branchId=$_branchId');
    if (_branchId == null) {
      _msg('ກະລຸນາເລືອກສາຂາກ່ອນ');
      return;
    }
    final nav = Navigator.of(context);
    while (mounted) {
      final raw = await nav.push<String>(
          MaterialPageRoute(builder: (_) => const ScanBarcodePage()));
      debugPrint('[WD] scanner returned raw=$raw');
      if (raw == null || raw.trim().isEmpty || !mounted) return;
      try {
        final r = await Api.get(
            '/products/by-barcode/${Uri.encodeComponent(raw.trim())}');
        final id = r is Map && r['productId'] != null ? '${r['productId']}' : '';
        debugPrint('[WD] by-barcode result=$r -> productId=$id');
        if (id.isEmpty) {
          _msg('ບໍ່ພົບສິນຄ້າ: $raw');
          continue;
        }
        final p = await Api.get('/products/$id');
        setState(() {
          _names[id] = p is Map ? '${p['name'] ?? id}' : id;
          _qty[id] = (_qty[id] ?? 0) + 1;
        });
      } catch (e) {
        debugPrint('[WD] scan FAILED: $e');
        if (mounted) setState(() => _error = '$e');
        return;
      }
    }
  }

  Future<void> _save() async {
    debugPrint('[WD] save tapped branchId=$_branchId parts=$_qty barcode=${widget.barcode} atmId=${widget.atmId}');
    if (_branchId == null) {
      debugPrint('[WD] save blocked: no branch chosen');
      setState(() => _error = 'ກະລຸນາເລືອກສາຂາກ່ອນ');
      return;
    }
    if (_qty.isEmpty) {
      debugPrint('[WD] save blocked: no parts added');
      setState(() => _error = 'ຍັງບໍ່ໄດ້ເລືອກອາໄຫຼ່');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await Api.post('/withdrawals', {
        'branchId': _branchId,
        if (widget.barcode.isNotEmpty) 'barcode': widget.barcode,
        if (widget.atmId.isNotEmpty) 'atmId': widget.atmId,
        'items': [
          for (final e in _qty.entries) {'productId': e.key, 'qty': e.value}
        ],
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      if (!mounted) return;
      _msg('ບັນທຶກລາຍການເບີກແລ້ວ');
      debugPrint('[WD] POST /withdrawals response=$r');
      await _showBill(r);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[WD] save FAILED: $e');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// After saving: open the bill of the new withdrawal (found in GET /withdrawals).
  Future<void> _showBill(dynamic r) async {
    try {
      final id = r is Map ? '${r['id']}' : '';
      debugPrint('[WD] showBill: response id=$id');
      if (id.isEmpty) {
        debugPrint('[WD] showBill: no id in response, no bill');
        return;
      }
      final list = await Api.get('/withdrawals');
      if (list is! List) {
        debugPrint('[WD] showBill: /withdrawals is not a list: $list');
        return;
      }
      for (final w in list) {
        if (w is Map && '${w['id']}' == id) {
          if (!mounted) return;
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      WithdrawBillPage(Map<String, dynamic>.from(w))));
          return;
        }
      }
      debugPrint('[WD] showBill: withdrawal $id not found in list of ${list.length}');
    } catch (e) {
      debugPrint('[WD] showBill error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ເບີກອາໄຫຼ່')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.barcode.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.memory),
              title: Text('Terminal ${widget.barcode}'),
              subtitle: widget.atmId.isEmpty
                  ? null
                  : Text('ຕູ້ ATM ${widget.atmId}'),
            ),
          ),
        DropdownButtonFormField<dynamic>(
          initialValue: _branches.any((b) => b['id'] == _branchId) ? _branchId : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'ເບີກຈາກສາຂາ'),
          items: [
            for (final b in _branches)
              DropdownMenuItem(value: b['id'], child: Text('${b['name']}')),
          ],
          onChanged: (v) => setState(() => _branchId = v),
        ),
        const SizedBox(height: 12),
        if (_qty.isEmpty)
          const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('ຍັງບໍ່ໄດ້ເລືອກອາໄຫຼ່'))),
        for (final id in _qty.keys)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_names[id] ?? id),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() {
                        if ((_qty[id] ?? 1) > 1) {
                          _qty[id] = _qty[id]! - 1;
                        } else {
                          _qty.remove(id);
                        }
                      })),
              Text('${_qty[id]}'),
              IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _qty[id] = _qty[id]! + 1)),
            ]),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('ສະແກນ'),
          onPressed: (_busy || _branchId == null) ? null : _scan,
        ),
        const SizedBox(height: 12),
        TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'ໝາຍເຫດ (ບໍ່ບັງຄັບ)')),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('ສ້າງໃບເບີກ')),
        ),
      ]),
    );
  }
}
