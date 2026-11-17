import 'package:flutter/material.dart';
import 'api.dart';
import 'product_images.dart' show productImageUrl;
import 'withdraw_bill.dart';
import 'terminal_actions.dart' show ScanBarcodePage, PickProductPage;

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
    _loadTerm();
    Api.get('/repair/branches').then((d) {
      if (!mounted) return;
      setState(() => _branches = d is List ? d : []);
    });
  }

  Map<String, dynamic> _term = {};
  Map<String, dynamic> _atm = {};

  /// Terminal + ATM data: the part list is filtered by terminal type / ATM brand / model.
  Future<void> _loadTerm() async {
    if (widget.barcode.isEmpty) return;
    try {
      final t =
          await Api.get('/terminals/${Uri.encodeComponent(widget.barcode)}');
      if (t is Map) _term = Map<String, dynamic>.from(t);
      final atmId =
          widget.atmId.isNotEmpty ? widget.atmId : '${_term['atmId'] ?? ''}';
      if (atmId.isNotEmpty) {
        final a = await Api.get('/atms/${Uri.encodeComponent(atmId)}');
        if (a is Map) _atm = Map<String, dynamic>.from(a);
      }
    } catch (_) {}
  }

  Future<void> _pick() async {
    if (_branchId == null) {
      _msg('ກະລຸນາເລືອກສາຂາກ່ອນ');
      return;
    }
    final row = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
            builder: (_) => PickProductPage(
                branchId: _branchId,
                terminalType: '${_term['typeName'] ?? ''}',
                terminalTypeId: '${_term['typeId'] ?? ''}',
                terminal: _term,
                atm: _atm)));
    if (row == null || !mounted) return;
    final id = '${row['id'] ?? row['productId'] ?? ''}';
    if (id.isEmpty) return;
    setState(() {
      _names[id] = '${row['name'] ?? id}';
      _qty[id] = (_qty[id] ?? 0) + 1;
    });
    _loadImg(id);
  }

  /// First image of each part (GET /products/:id/images), loaded once per part.
  final Map<String, String> _img = {};

  Future<void> _loadImg(String id) async {
    if (_img.containsKey(id)) return;
    _img[id] = '';
    try {
      final d = await Api.get('/products/${Uri.encodeComponent(id)}/images');
      if (d is List && d.isNotEmpty && d.first is Map) {
        final u = '${(d.first as Map)['url'] ?? ''}';
        if (mounted && u.isNotEmpty) setState(() => _img[id] = u);
      }
    } catch (e) {
      debugPrint('image load failed for $id: $e');
    }
  }

  Widget _thumb(String id) {
    final url = productImageUrl(_img[id] ?? '');
    final box = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8)),
      child: const Icon(Icons.memory, size: 24),
    );
    if (url.isEmpty) return box;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => box),
    );
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
        _loadImg(id);
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
      final r = await Api.post('/withdrawals', {
        'branchId': _branchId,
        if (widget.barcode.isNotEmpty) 'draft': true,
        if (widget.barcode.isNotEmpty) 'barcode': widget.barcode,
        if (widget.atmId.isNotEmpty) 'atmId': widget.atmId,
        'items': [
          for (final e in _qty.entries) {'productId': e.key, 'qty': e.value}
        ],
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      if (!mounted) return;
      _msg(widget.barcode.isNotEmpty
          ? 'ສ້າງໃບເບີກແລ້ວ (ຍັງບໍ່ຕັດສະຕັອກ)'
          : 'ບັນທຶກລາຍການເບີກແລ້ວ');
      await _showBill(r);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// After saving: open the bill of the new withdrawal (found in GET /withdrawals).
  Future<void> _showBill(dynamic r) async {
    try {
      final id = r is Map ? '${r['id']}' : '';
      if (id.isEmpty) {
        return;
      }
      final list = await Api.get('/withdrawals');
      if (list is! List) {
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
    } catch (e) {
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
            leading: _thumb(id),
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
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.list_alt),
          label: const Text('ເລືອກອາໄຫຼ່ຈາກລາຍການ'),
          onPressed: (_busy || _branchId == null) ? null : _pick,
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
