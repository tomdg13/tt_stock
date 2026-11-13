import 'package:flutter/material.dart';
import 'api.dart';
import 'terminal_actions.dart' show ScanBarcodePage;

/// ເບີກອາໄຫຼ່: ເລືອກສາຂາ, ສະແກນອາໄຫຼ່, ບັນທຶກເປັນລາຍການ
class WithdrawPage extends StatefulWidget {
  const WithdrawPage({super.key});
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
    Api.get('/repair/branches').then((d) {
      if (!mounted) return;
      setState(() => _branches = d is List ? d : []);
    });
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _scan() async {
    if (_branchId == null) {
      _msg('ກະລຸນາເລືອກສາຂາກ່ອນ');
      return;
    }
    final nav = Navigator.of(context);
    while (mounted) {
      final raw = await nav.push<String>(
          MaterialPageRoute(builder: (_) => const ScanBarcodePage()));
      if (raw == null || raw.trim().isEmpty || !mounted) return;
      try {
        final r = await Api.get(
            '/products/by-barcode/${Uri.encodeComponent(raw.trim())}');
        final id = r is Map && r['productId'] != null ? '${r['productId']}' : '';
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
        if (mounted) setState(() => _error = '$e');
        return;
      }
    }
  }

  Future<void> _save() async {
    if (_branchId == null) {
      setState(() => _error = 'ກະລຸນາເລືອກສາຂາກ່ອນ');
      return;
    }
    if (_qty.isEmpty) {
      setState(() => _error = 'ຍັງບໍ່ໄດ້ເລືອກອາໄຫຼ່');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.post('/withdrawals', {
        'branchId': _branchId,
        'items': [
          for (final e in _qty.entries) {'productId': e.key, 'qty': e.value}
        ],
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      if (!mounted) return;
      _msg('ບັນທຶກລາຍການເບີກແລ້ວ');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ເບີກອາໄຫຼ່')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
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
              child: const Text('ບັນທຶກການເບີກ')),
        ),
      ]),
    );
  }
}
