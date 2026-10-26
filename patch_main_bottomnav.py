import re
import shutil

path = 'lib/screens.dart'
s = open(path, encoding='utf-8').read()

if '_bottomBar' in s:
    raise SystemExit('ABORT: already patched')

# _key must be a mutable String field of the shell state
if not re.search(r'\bString _key\b', s) or re.search(r'\bfinal String _key\b', s):
    raise SystemExit(
        'ABORT: could not find a mutable "String _key" field. '
        'Paste: sed -n "98,125p;200,240p" lib/screens.dart'
    )

A1 = (
    "  @override\n"
    "  Widget build(BuildContext context) {\n"
    "    return Scaffold(\n"
    "      appBar: AppBar(\n"
    "        title: Text(labelOf(_key),"
)
A2 = (
    "      drawer: _drawer(),\n"
    "      body: KeyedSubtree(key: ValueKey(_key), child: _page(_key)),\n"
)

for name, a in (('A1', A1), ('A2', A2)):
    if s.count(a) != 1:
        raise SystemExit('ABORT %s: expected 1 match, found %d' % (name, s.count(a)))

METHOD = """  Widget? _bottomBar() {
    const keys = ['dash', 'stock', 'recv', 'issue'];
    final tabs = <MenuItemDef>[
      for (final g in menuGroups)
        for (final i in g.items)
          if (keys.contains(i.key) && _allowed(i)) i,
    ];
    if (tabs.isEmpty) return null;
    final idx = tabs.indexWhere((t) => t.key == _key);
    return Builder(
      builder: (ctx) => NavigationBar(
        selectedIndex: idx >= 0 ? idx : tabs.length,
        onDestinationSelected: (i) {
          if (i < tabs.length) {
            setState(() => _key = tabs[i].key);
          } else {
            Scaffold.of(ctx).openDrawer();
          }
        },
        destinations: [
          for (final t in tabs) NavigationDestination(icon: Icon(t.icon), label: t.label),
          const NavigationDestination(icon: Icon(Icons.menu), label: 'ເພີ່ມເຕີມ'),
        ],
      ),
    );
  }

"""

B2 = (
    "      drawer: _drawer(),\n"
    "      bottomNavigationBar: _bottomBar(),\n"
    "      body: KeyedSubtree(key: ValueKey(_key), child: _page(_key)),\n"
)

shutil.copy(path, path + '.bak4')
s = s.replace(A1, METHOD + A1).replace(A2, B2)
open(path, 'w', encoding='utf-8').write(s)
print('patched', path)
