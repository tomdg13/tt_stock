import shutil

path = 'lib/screens.dart'
s = open(path, encoding='utf-8').read()

if 'ValueNotifier<int>(0)' in s and "crudSpec('terms')" in s:
    raise SystemExit('ABORT: already patched')

START = "  // searchable list of terminals that are not In Use\n"
END = "  // terminals currently In Use in this ATM\n"
if s.count(START) != 1 or s.count(END) != 1:
    raise SystemExit('ABORT: markers not found. Was patch_hub_actions.py applied?')
a, b = s.index(START), s.index(END)
if a > b:
    raise SystemExit('ABORT: unexpected order')

NEW = r"""  // searchable list of terminals that are not In Use, with add / edit / delete
  Future<Map<String, dynamic>?> _pickTerminal({String? typeId}) {
    final extra = typeId == null
        ? 'limit=500'
        : 'limit=500&typeId=${Uri.encodeQueryComponent(typeId)}';
    final spec = crudSpec('terms');
    final canEdit = spec != null && spec.canWrite;
    final sig = ValueNotifier<int>(0);
    return Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (pc) => Scaffold(
          appBar: AppBar(
            title: const Text('ເລືອກ Terminal'),
            actions: [
              if (canEdit)
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('ເພີ່ມ'),
                  onPressed: () async {
                    final ok = await Navigator.push<bool>(
                        pc, MaterialPageRoute(builder: (_) => CrudForm(spec!)));
                    if (ok == true) sig.value++;
                  },
                ),
            ],
          ),
          body: ListPage(
            title: 'Terminal',
            path: '/terminals',
            extraQuery: extra,
            titleKeys: const ['barcode'],
            subKeys: const ['typeName', 'serial'],
            tagKeys: const ['state'],
            rowFilter: (m) => '${m['state'] ?? ''}' != 'In Use',
            onTapItem: (c, m) => Navigator.pop(c, m),
            reloadSignal: sig,
            rowActions: canEdit
                ? (c, m) => Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: 'ແກ້ໄຂ',
                        onPressed: () async {
                          final ok = await Navigator.push<bool>(
                              c, MaterialPageRoute(builder: (_) => CrudForm(spec!, row: m)));
                          if (ok == true) sig.value++;
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: 'ລຶບ',
                        onPressed: () async {
                          if (await confirmDelete(c, spec!, m)) sig.value++;
                        },
                      ),
                    ])
                : null,
          ),
        ),
      ),
    );
  }

"""

shutil.copy(path, path + '.bak11')
open(path, 'w', encoding='utf-8').write(s[:a] + NEW + s[b:])
print('patched', path)
