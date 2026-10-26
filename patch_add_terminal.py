import re
import shutil

# ------------------------------------------------ pubspec must already have the scanner
pub = open('pubspec.yaml', encoding='utf-8').read()
if 'mobile_scanner' not in pub:
    raise SystemExit('ABORT: run "flutter pub add mobile_scanner" first, then run this script again.')

path = 'lib/screens.dart'
s = open(path, encoding='utf-8').read()
if 'BarcodeScanPage' in s:
    raise SystemExit('ABORT: already patched')

START = "// ------------------------------------------------------------ ATM hub for Issue"
END = "// ------------------------------------------------------------ ATM -> terminals -> products"
if s.count(START) != 1 or s.count(END) != 1:
    raise SystemExit('ABORT: hub markers not found. Were patch_issue_atm_hub.py and patch_atm_tree.py applied?')
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

  Future<void> _add() async {
    final code = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const BarcodeScanPage()));
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
      if (ok != true) return;
      await Api.post('/activities', {'status': 'In Use', 'barcode': barcode, 'atmId': widget.atmId});
      if (!mounted) return;
      setState(() { _rev++; });
      _snack('ບັນທຶກແລ້ວ');
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final atmId = widget.atmId;
    final canAdd = Api.can('ATM_MANAGE');
    return Scaffold(
      appBar: AppBar(title: Text('ຕູ້ ATM · $atmId')),
      body: AtmTerminalTree(atmId, key: ValueKey(_rev), onAdd: canAdd ? _add : null),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            if (canAdd) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('ເພີ່ມ Terminal'),
                onPressed: _add,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
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
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ barcode scanner
class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});
  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  bool _done = false;

  void _finish(String v) {
    if (_done) return;
    _done = true;
    Navigator.pop(context, v);
  }

  Future<void> _manual() async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ປ້ອນ Barcode'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Barcode'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('ຍົກເລີກ')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('ຕົກລົງ')),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) _finish(v.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ສະແກນ Barcode'),
        actions: [
          IconButton(icon: const Icon(Icons.keyboard_outlined), tooltip: 'ປ້ອນເອງ', onPressed: _manual),
        ],
      ),
      body: MobileScanner(
        onDetect: (capture) {
          for (final b in capture.barcodes) {
            final v = b.rawValue;
            if (v != null && v.isNotEmpty) {
              _finish(v);
              break;
            }
          }
        },
      ),
    );
  }
}

"""

# AtmTerminalTree: optional onAdd + button in the empty state
E1_OLD = "  final String atmId;\n  const AtmTerminalTree(this.atmId, {super.key});\n"
E1_NEW = "  final String atmId;\n  final VoidCallback? onAdd;\n  const AtmTerminalTree(this.atmId, {super.key, this.onAdd});\n"
E2_OLD = "                  Center(child: Text('ຍັງບໍ່ມີ Terminal ໃນຕູ້ນີ້', style: TextStyle(color: p.mut))),\n"
E2_NEW = (
    E2_OLD
    + "                  if (widget.onAdd != null)\n"
    + "                    Padding(\n"
    + "                      padding: const EdgeInsets.only(top: 16),\n"
    + "                      child: Center(\n"
    + "                        child: FilledButton.tonalIcon(\n"
    + "                          onPressed: widget.onAdd,\n"
    + "                          icon: const Icon(Icons.qr_code_scanner),\n"
    + "                          label: const Text('ເພີ່ມ Terminal'),\n"
    + "                        ),\n"
    + "                      ),\n"
    + "                    ),\n"
)

new_s = s[:a] + NEW_HUB + s[b:]
for name, old, new in (('E1', E1_OLD, E1_NEW), ('E2', E2_OLD, E2_NEW)):
    if new_s.count(old) != 1:
        raise SystemExit('ABORT %s: expected 1 match, found %d' % (name, new_s.count(old)))
    new_s = new_s.replace(old, new)
new_s = "import 'package:mobile_scanner/mobile_scanner.dart';\n" + new_s

shutil.copy(path, path + '.bak9')
open(path, 'w', encoding='utf-8').write(new_s)
print('patched', path)

# ------------------------------------------------ Android camera permission
man = 'android/app/src/main/AndroidManifest.xml'
try:
    m = open(man, encoding='utf-8').read()
    if 'android.permission.CAMERA' not in m:
        shutil.copy(man, man + '.bak9')
        m = re.sub(r'(<manifest[^>]*>)', r'\1\n    <uses-permission android:name="android.permission.CAMERA"/>', m, count=1)
        open(man, 'w', encoding='utf-8').write(m)
        print('added CAMERA permission to AndroidManifest.xml')
except FileNotFoundError:
    print('AndroidManifest.xml not found, skipped')

# ------------------------------------------------ iOS camera usage text
plist = 'ios/Runner/Info.plist'
try:
    p = open(plist, encoding='utf-8').read()
    if 'NSCameraUsageDescription' not in p:
        shutil.copy(plist, plist + '.bak9')
        i = p.rindex('</dict>')
        p = (p[:i]
             + '\t<key>NSCameraUsageDescription</key>\n'
             + '\t<string>Scan terminal barcodes</string>\n'
             + p[i:])
        open(plist, 'w', encoding='utf-8').write(p)
        print('added NSCameraUsageDescription to Info.plist')
except FileNotFoundError:
    print('Info.plist not found, skipped')
