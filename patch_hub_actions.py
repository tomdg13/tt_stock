import shutil

path = 'lib/screens.dart'
s = open(path, encoding='utf-8').read()

if '_replace(' in s:
    raise SystemExit('ABORT: already patched')

START = "// ------------------------------------------------------------ ATM hub for Issue"
END = "// ------------------------------------------------------------ barcode scanner"
if s.count(START) != 1 or s.count(END) != 1:
    raise SystemExit('ABORT: markers not found. Was patch_add_terminal.py applied?')
a, b = s.index(START), s.index(END)
if a > b:
    raise SystemExit('ABORT: unexpected order of sections')

NEW_HUB = r"""// ------------------------------------------------------------ ATM hub for Issue
class AtmIssueHub extends StatefulWidget {
  final String atmId;
  const AtmIssueHub(this.atmId, {super.key});
  @override
  State<AtmIssueHub> createState() => _AtmIssueHubState();
}

class _AtmIssueHubState extends State<AtmIssueHub> {
  int _rev = 0;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ຢືນຢັນ'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('ຍົກເລີກ')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('ບັນທຶກ')),
        ],
      ),
    );
    return ok == true;
  }

  Future<String?> _scan() => Navigator.push<String>(
      context, MaterialPageRoute(builder: (_) => const BarcodeScanPage()));

  // searchable list of terminals that are not In Use
  Future<Map<String, dynamic>?> _pickTerminal({String? typeId}) {
    final extra = typeId == null
        ? 'limit=500'
        : 'limit=500&typeId=${Uri.encodeQueryComponent(typeId)}';
    return Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('ເລືອກ Terminal')),
          body: ListPage(
            title: 'Terminal',
            path: '/terminals',
            extraQuery: extra,
            titleKeys: const ['barcode'],
            subKeys: const ['typeName', 'serial'],
            tagKeys: const ['state'],
            rowFilter: (m) => '${m['state'] ?? ''}' != 'In Use',
            onTapItem: (c, m) => Navigator.pop(c, m),
          ),
        ),
      ),
    );
  }

  // terminals currently In Use in this ATM
  Future<Map<String, dynamic>?> _pickCurrent() async {
    final d = await Api.get('/atms/${Uri.encodeComponent(widget.atmId)}');
    final terms = d is Map && d['terminals'] is List ? asList(d['terminals']) : <Map<String, dynamic>>[];
    if (!mounted) return null;
    if (terms.isEmpty) {
      _snack('ບໍ່ມີ Terminal ໃນຕູ້ນີ້ ໃຫ້ໃຊ້ "ເພີ່ມ" ກ່ອນ');
      return null;
    }
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('ເລືອກ Terminal ທີ່ຈະປ່ຽນອອກ', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final t in terms)
            ListTile(
              leading: const Icon(Icons.memory),
              title: Text(pick(t, ['barcode'])),
              subtitle: Text([pick(t, ['typeName']), pick(t, ['serial'])].where((e) => e.isNotEmpty).join(' · ')),
              onTap: () => Navigator.pop(c, t),
            ),
        ]),
      ),
    );
  }

  Future<void> _addCode(String? code) async {
    if (code == null || code.trim().isEmpty || !mounted) return;
    final barcode = code.trim();
    try {
      final info = await Api.get('/terminals/${Uri.encodeComponent(barcode)}');
      if (!mounted) return;
      final st = info is Map ? '${info['state'] ?? ''}' : '';
      final cur = info is Map ? '${info['atmId'] ?? ''}' : '';
      if (st == 'In Use' && cur == widget.atmId) {
        _snack('Terminal ນີ້ຢູ່ໃນຕູ້ນີ້ແລ້ວ');
        return;
      }
      final msg = st == 'In Use' && cur.isNotEmpty
          ? 'Terminal $barcode ຢູ່ໃນຕູ້ $cur ແລ້ວ. ຍ້າຍມາຕູ້ ${widget.atmId}?'
          : 'ເພີ່ມ Terminal $barcode ເຂົ້າຕູ້ ${widget.atmId}?';
      if (!await _confirm(msg)) return;
      await Api.post('/activities', {'status': 'In Use', 'barcode': barcode, 'atmId': widget.atmId});
      if (!mounted) return;
      setState(() { _rev++; });
      _snack('ບັນທຶກແລ້ວ');
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Future<void> _addScan() async => _addCode(await _scan());

  Future<void> _addPick() async {
    final m = await _pickTerminal();
    if (m != null) await _addCode(pick(m, ['barcode']));
  }

  Future<void> _replace(bool byScan) async {
    try {
      final old = await _pickCurrent();
      if (old == null || !mounted) return;
      final oldCode = pick(old, ['barcode']);
      final oi = await Api.get('/terminals/${Uri.encodeComponent(oldCode)}');
      final typeId = oi is Map && oi['typeId'] != null ? '${oi['typeId']}' : null;
      if (!mounted) return;
      String? raw;
      if (byScan) {
        raw = await _scan();
      } else {
        final m = await _pickTerminal(typeId: typeId);
        raw = m == null ? null : pick(m, ['barcode']);
      }
      if (raw == null || raw.trim().isEmpty || !mounted) return;
      final nc = raw.trim();
      if (nc == oldCode) {
        _snack('Terminal ຊ້ຳກັນ');
        return;
      }
      final ni = await Api.get('/terminals/${Uri.encodeComponent(nc)}');
      if (!mounted) return;
      final st = ni is Map ? '${ni['state'] ?? ''}' : '';
      final cur = ni is Map ? '${ni['atmId'] ?? ''}' : '';
      if (st == 'In Use' && cur == widget.atmId) {
        _snack('Terminal ໃໝ່ຢູ່ໃນຕູ້ນີ້ແລ້ວ');
        return;
      }
      final warn = <String>[
        if (st == 'In Use' && cur.isNotEmpty) 'Terminal ໃໝ່ຢູ່ໃນຕູ້ $cur',
        if (typeId != null && ni is Map && '${ni['typeId']}' != typeId) 'ປະເພດບໍ່ຕົງກັນ',
      ];
      final note = warn.isEmpty ? '' : '\n⚠ ' + warn.join(', ');
      if (!await _confirm('ປ່ຽນ $oldCode → $nc ໃນຕູ້ ${widget.atmId}?$note')) return;
      await Api.post('/atms/${Uri.encodeComponent(widget.atmId)}/replace',
          {'oldBarcode': oldCode, 'newBarcode': nc});
      if (!mounted) return;
      setState(() { _rev++; });
      _snack('ປ່ຽນແລ້ວ');
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  Widget _act(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final atmId = widget.atmId;
    final canAdd = Api.can('ATM_MANAGE');
    return Scaffold(
      appBar: AppBar(title: Text('ຕູ້ ATM · $atmId')),
      body: AtmTerminalTree(atmId, key: ValueKey(_rev), onAdd: canAdd ? _addScan : null),
      bottomNavigationBar: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.upload_outlined),
                  label: const Text('ເອົາສິນຄ້າອອກ'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text('ເອົາອອກ · $atmId')),
                        body: StockFormPage(issue: true, atmId: atmId),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (canAdd)
              Row(children: [
                _act(Icons.playlist_add, 'ເພີ່ມ · ເລືອກ', _addPick),
                _act(Icons.qr_code_scanner, 'ເພີ່ມ · ສະແກນ', _addScan),
                _act(Icons.document_scanner_outlined, 'ປ່ຽນ · ສະແກນ', () => _replace(true)),
                _act(Icons.swap_horiz, 'ປ່ຽນ · ເລືອກ', () => _replace(false)),
              ]),
          ]),
        ),
      ),
    );
  }
}

"""

shutil.copy(path, path + '.bak10')
open(path, 'w', encoding='utf-8').write(s[:a] + NEW_HUB + s[b:])
print('patched', path)
