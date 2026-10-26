import shutil

path = 'lib/screens.dart'
s = open(path, encoding='utf-8').read()

if 'AtmIssueHub' in s:
    raise SystemExit('ABORT: already patched')

OLD = (
    "          onTapItem: (ctx, m) => Navigator.push(\n"
    "            ctx,\n"
    "            MaterialPageRoute(\n"
    "              builder: (_) => Scaffold(\n"
    "                appBar: AppBar(title: Text('ເອົາອອກ · ${pick(m, ['atmId'])}')),\n"
    "                body: StockFormPage(issue: true, atmId: pick(m, ['atmId'])),\n"
    "              ),\n"
    "            ),\n"
    "          ),\n"
)
NEW = (
    "          onTapItem: (ctx, m) => Navigator.push(\n"
    "            ctx,\n"
    "            MaterialPageRoute(builder: (_) => AtmIssueHub(pick(m, ['atmId']))),\n"
    "          ),\n"
)

if s.count(OLD) != 1:
    raise SystemExit(
        'ABORT: expected 1 match, found %d. Was patch_issue_pick_atm.py applied?' % s.count(OLD)
    )

CLASS = r"""

// ------------------------------------------------------------ ATM hub for Issue
class AtmIssueHub extends StatelessWidget {
  final String atmId;
  const AtmIssueHub(this.atmId, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ຕູ້ ATM · $atmId')),
      body: ListPage(
        title: 'Terminal',
        path: '/terminals',
        searchable: false,
        extraQuery: 'limit=200&atmId=${Uri.encodeQueryComponent(atmId)}',
        titleKeys: const ['barcode'],
        subKeys: const ['typeName', 'serial'],
        tagKeys: const ['state'],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
    );
  }
}
"""

shutil.copy(path, path + '.bak7')
s = s.replace(OLD, NEW).rstrip('\n') + '\n' + CLASS
open(path, 'w', encoding='utf-8').write(s)
print('patched', path)
