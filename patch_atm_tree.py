import shutil

path = 'lib/screens.dart'
s = open(path, encoding='utf-8').read()

if 'AtmTerminalTree' in s:
    raise SystemExit('ABORT: already patched')

OLD = (
    "      body: ListPage(\n"
    "        title: 'Terminal',\n"
    "        path: '/terminals',\n"
    "        searchable: false,\n"
    "        extraQuery: 'limit=200&atmId=${Uri.encodeQueryComponent(atmId)}',\n"
    "        titleKeys: const ['barcode'],\n"
    "        subKeys: const ['typeName', 'serial'],\n"
    "        tagKeys: const ['state'],\n"
    "      ),\n"
    "      bottomNavigationBar: SafeArea(\n"
)
NEW = (
    "      body: AtmTerminalTree(atmId),\n"
    "      bottomNavigationBar: SafeArea(\n"
)

if s.count(OLD) != 1:
    raise SystemExit(
        'ABORT: expected 1 match, found %d. Was patch_issue_atm_hub.py applied?' % s.count(OLD)
    )

CLASSES = r"""

// ------------------------------------------------------------ ATM -> terminals -> products
class AtmTerminalTree extends StatefulWidget {
  final String atmId;
  const AtmTerminalTree(this.atmId, {super.key});
  @override
  State<AtmTerminalTree> createState() => _AtmTerminalTreeState();
}

class _AtmTerminalTreeState extends State<AtmTerminalTree> {
  late Future<dynamic> _f = _load();

  Future<dynamic> _load() => Api.get('/atms/${Uri.encodeComponent(widget.atmId)}');
  void _reload() => setState(() { _f = _load(); });

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return FutureBuilder(
      future: _f,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) return ErrorView(s.error!, _reload);
        final d = s.data;
        final terms = d is Map && d['terminals'] is List ? asList(d['terminals']) : <Map<String, dynamic>>[];
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: terms.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 120),
                  Center(child: Text('ຍັງບໍ່ມີ Terminal ໃນຕູ້ນີ້', style: TextStyle(color: p.mut))),
                ])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [for (final t in terms) _TerminalTile(t)],
                ),
        );
      },
    );
  }
}

class _TerminalTile extends StatefulWidget {
  final Map<String, dynamic> t;
  const _TerminalTile(this.t);
  @override
  State<_TerminalTile> createState() => _TerminalTileState();
}

class _TerminalTileState extends State<_TerminalTile> {
  Future<dynamic>? _parts;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final t = widget.t;
    final barcode = pick(t, ['barcode']);
    final sub = [pick(t, ['typeName']), pick(t, ['model']), pick(t, ['serial'])]
        .where((e) => e.isNotEmpty)
        .join(' · ');
    return cardBox(
      context,
      margin: const EdgeInsets.only(bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.memory),
          title: Text(barcode, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub.isEmpty ? null : Text(sub, style: TextStyle(color: p.mut, fontSize: 13)),
          onExpansionChanged: (open) {
            if (open && _parts == null) {
              setState(() { _parts = Api.get('/terminals/${Uri.encodeComponent(barcode)}'); });
            }
          },
          children: [
            if (_parts != null)
              FutureBuilder(
                future: _parts,
                builder: (c, s) {
                  if (s.connectionState != ConnectionState.done) {
                    return const Padding(
                        padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                  }
                  if (s.hasError) {
                    return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('${s.error}', style: TextStyle(color: p.bad)));
                  }
                  final d = s.data;
                  final parts = d is Map && d['parts'] is List ? asList(d['parts']) : <Map<String, dynamic>>[];
                  if (parts.isEmpty) {
                    return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('ບໍ່ມີສິນຄ້າໃນ Terminal ນີ້', style: TextStyle(color: p.mut)));
                  }
                  return Column(children: [
                    for (final x in parts)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.settings_input_component_outlined, size: 20),
                        title: Text(pick(x, ['productName'])),
                        subtitle: Text(
                          [pick(x, ['serialNo']), pick(x, ['installedAt'])].where((e) => e.isNotEmpty).join(' · '),
                          style: TextStyle(color: p.mut, fontSize: 12),
                        ),
                      ),
                  ]);
                },
              ),
          ],
        ),
      ),
    );
  }
}
"""

shutil.copy(path, path + '.bak8')
s = s.replace(OLD, NEW).rstrip('\n') + '\n' + CLASSES
open(path, 'w', encoding='utf-8').write(s)
print('patched', path)
