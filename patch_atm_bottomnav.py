import shutil

# ---------------------------------------------------------------- crud.dart
crud = open('lib/crud.dart', encoding='utf-8').read()
if 'atmTerminalsView' in crud:
    raise SystemExit('ABORT: already patched')

A1 = "class _CrudDetailState extends State<CrudDetail> {\n  late Future<dynamic> _f = _load();\n"
A2 = "    final title = pick(widget.row, sp.titleKeys);\n    return Scaffold(\n"
A3 = (
    "      body: FutureBuilder(\n"
    "        future: _f,\n"
    "        builder: (c, s) {\n"
    "          if (s.connectionState != ConnectionState.done) {\n"
    "            return const Center(child: CircularProgressIndicator());\n"
    "          }\n"
    "          if (s.hasError) return ErrorView(s.error!, _reload);\n"
    "          final acts = "
)

for name, a in (('A1', A1), ('A2', A2), ('A3', A3)):
    if crud.count(a) != 1:
        raise SystemExit('ABORT crud.dart %s: expected 1 match, found %d' % (name, crud.count(a)))

B1 = A1 + "  int _tab = 0;\n"
B2 = (
    "    final title = pick(widget.row, sp.titleKeys);\n"
    "    final isAtm = sp.path == '/atms';\n"
    "    return Scaffold(\n"
)
B3 = (
    "      bottomNavigationBar: isAtm\n"
    "          ? NavigationBar(\n"
    "              selectedIndex: _tab,\n"
    "              onDestinationSelected: (i) => setState(() => _tab = i),\n"
    "              destinations: const [\n"
    "                NavigationDestination(icon: Icon(Icons.info_outline), label: 'ລາຍລະອຽດ'),\n"
    "                NavigationDestination(icon: Icon(Icons.memory), label: 'Terminal'),\n"
    "                NavigationDestination(icon: Icon(Icons.history), label: 'ປະຫວັດ'),\n"
    "              ],\n"
    "            )\n"
    "          : null,\n"
    "      body: isAtm && _tab == 1\n"
    "          ? atmTerminalsView(pick(widget.row, ['atmId']))\n"
    "          : isAtm && _tab == 2\n"
    "              ? atmHistoryView(pick(widget.row, ['atmId']))\n"
    "              : FutureBuilder(\n"
    "        future: _f,\n"
    "        builder: (c, s) {\n"
    "          if (s.connectionState != ConnectionState.done) {\n"
    "            return const Center(child: CircularProgressIndicator());\n"
    "          }\n"
    "          if (s.hasError) return ErrorView(s.error!, _reload);\n"
    "          final acts = "
)

NEW_CODE = r"""

// ---------------------------------------------------- ATM: terminals + history tabs
Widget atmTerminalsView(String id) => ListPage(
      key: ValueKey('atm-term-$id'),
      title: 'Terminal',
      path: '/terminals',
      searchable: false,
      extraQuery: 'limit=200&atmId=${Uri.encodeQueryComponent(id)}',
      titleKeys: const ['barcode'],
      subKeys: const ['typeName', 'serial'],
      tagKeys: const ['state'],
    );

Widget atmHistoryView(String id) {
  final a = Uri.encodeQueryComponent(id);
  return DefaultTabController(
    key: ValueKey('atm-hist-$id'),
    length: 2,
    child: Column(children: [
      const TabBar(tabs: [Tab(text: 'ກິດຈະກຳ'), Tab(text: 'ອາໄຫຼ່')]),
      Expanded(
        child: TabBarView(children: [
          ListPage(
            title: 'ກິດຈະກຳ',
            path: '/activity-report',
            searchable: false,
            extraQuery: 'limit=200&atmId=$a',
            titleKeys: const ['tidBarcode', 'barcode'],
            subKeys: const ['activityDate', 'remark', 'terminalSerial'],
            tagKeys: const ['status'],
          ),
          ListPage(
            title: 'ອາໄຫຼ່',
            path: '/install/log',
            searchable: false,
            extraQuery: 'limit=200&atmId=$a',
            titleKeys: const ['action'],
            subKeys: const ['logDate', 'barcode', 'productName', 'serialNo', 'userName'],
          ),
        ]),
      ),
    ]),
  );
}
"""

new_crud = crud.replace(A1, B1).replace(A2, B2).replace(A3, B3).rstrip('\n') + '\n' + NEW_CODE

# ---------------------------------------------------------------- specs.dart
specs = open('lib/specs.dart', encoding='utf-8').read()
OLD_ACTIONS = (
    "        detailPath: (r) => '/atms/${Uri.encodeComponent(pick(r, ['atmId']))}',\n"
    "        actions: [\n"
    "          RowAction('Terminal', Icons.memory, atmTerminalsPage),\n"
    "          RowAction('ປະຫວັດ', Icons.history, atmHistoryPage),\n"
    "        ],\n"
)
PLAIN = "        detailPath: (r) => '/atms/${Uri.encodeComponent(pick(r, ['atmId']))}',\n"
new_specs = specs
if OLD_ACTIONS in specs:
    new_specs = specs.replace(OLD_ACTIONS, PLAIN)
    print('removed the two action buttons from specs.dart')

shutil.copy('lib/crud.dart', 'lib/crud.dart.bak3')
shutil.copy('lib/specs.dart', 'lib/specs.dart.bak3')
open('lib/crud.dart', 'w', encoding='utf-8').write(new_crud)
open('lib/specs.dart', 'w', encoding='utf-8').write(new_specs)
print('patched lib/crud.dart and lib/specs.dart')
