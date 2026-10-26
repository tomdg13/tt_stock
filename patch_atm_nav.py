import shutil

NEW_CODE = r"""

// ---------------------------------------------------- ATM: terminals + history
Future<void> atmTerminalsPage(BuildContext context, Row_ r) async {
  final id = pick(r, ['atmId']);
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('Terminal · $id')),
        body: ListPage(
          title: 'Terminal',
          path: '/terminals',
          searchable: false,
          extraQuery: 'limit=200&atmId=${Uri.encodeQueryComponent(id)}',
          titleKeys: const ['barcode'],
          subKeys: const ['typeName', 'serial'],
          tagKeys: const ['state'],
        ),
      ),
    ),
  );
}

Future<void> atmHistoryPage(BuildContext context, Row_ r) async {
  final id = pick(r, ['atmId']);
  final a = Uri.encodeQueryComponent(id);
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text('ປະຫວັດ · $id'),
            bottom: const TabBar(tabs: [Tab(text: 'ກິດຈະກຳ'), Tab(text: 'ອາໄຫຼ່')]),
          ),
          body: TabBarView(children: [
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
      ),
    ),
  );
}
"""

ACTIONS = (
    "        detailPath: (r) => '/atms/${Uri.encodeComponent(pick(r, ['atmId']))}',\n"
    "        actions: [\n"
    "          RowAction('Terminal', Icons.memory, atmTerminalsPage),\n"
    "          RowAction('ປະຫວັດ', Icons.history, atmHistoryPage),\n"
    "        ],\n"
)
OLD = "        detailPath: (r) => '/atms/${Uri.encodeComponent(pick(r, ['atmId']))}',\n"

crud = open('lib/crud.dart', encoding='utf-8').read()
specs = open('lib/specs.dart', encoding='utf-8').read()

if 'atmTerminalsPage' in crud:
    raise SystemExit('ABORT: already patched')
if specs.count(OLD) != 1:
    raise SystemExit('ABORT specs.dart: expected 1 match, found %d' % specs.count(OLD))

shutil.copy('lib/crud.dart', 'lib/crud.dart.bak2')
shutil.copy('lib/specs.dart', 'lib/specs.dart.bak2')
open('lib/crud.dart', 'w', encoding='utf-8').write(crud.rstrip('\n') + '\n' + NEW_CODE)
open('lib/specs.dart', 'w', encoding='utf-8').write(specs.replace(OLD, ACTIONS))
print('patched lib/crud.dart and lib/specs.dart')
