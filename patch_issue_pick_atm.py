import shutil

# ------------------------------------------------------------ pages.dart
pages = open('lib/pages.dart', encoding='utf-8').read()
if 'final String? atmId;' in pages:
    raise SystemExit('ABORT: already patched')

P_EDITS = [
    (
        "  final bool issue;\n"
        "  const StockFormPage({super.key, required this.issue});\n",
        "  final bool issue;\n"
        "  final String? atmId;\n"
        "  const StockFormPage({super.key, required this.issue, this.atmId});\n",
    ),
    (
        "  String? _atmId;\n",
        "  late String? _atmId = widget.atmId;\n",
    ),
    (
        "        _atmId = null;\n",
        "        _atmId = widget.atmId;\n",
    ),
    (
        "            const SizedBox(height: 12),\n"
        "            DropdownButtonFormField<String>(\n"
        "              initialValue: _atmId,\n",
        "            const SizedBox(height: 12),\n"
        "            if (widget.atmId != null)\n"
        "              Text('ຕູ້ ATM: ${widget.atmId}', style: const TextStyle(fontWeight: FontWeight.w600))\n"
        "            else\n"
        "            DropdownButtonFormField<String>(\n"
        "              initialValue: _atmId,\n",
    ),
]
for i, (old, _) in enumerate(P_EDITS, 1):
    if pages.count(old) != 1:
        raise SystemExit('ABORT pages.dart edit %d: expected 1 match, found %d' % (i, pages.count(old)))

# ---------------------------------------------------------- screens.dart
screens = open('lib/screens.dart', encoding='utf-8').read()
S_OLD = "case 'issue': return const StockFormPage(issue: true);"
S_NEW = """case 'issue':
        return ListPage(
          title: 'ຕູ້ ATM', path: '/atms', extraQuery: 'limit=100',
          titleKeys: const ['atmId'], subKeys: const ['atmLocation', 'location', 'groupName', 'atmGroupId'],
          tagKeys: const ['atmStatus', 'status'],
          rowFilter: (m) => pick(m, ['atmStatus', 'status']).toLowerCase() == 'active',
          onTapItem: (ctx, m) => Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text('ເອົາອອກ · ${pick(m, ['atmId'])}')),
                body: StockFormPage(issue: true, atmId: pick(m, ['atmId'])),
              ),
            ),
          ),
        );"""
if screens.count(S_OLD) != 1:
    raise SystemExit('ABORT screens.dart: expected 1 match, found %d' % screens.count(S_OLD))

shutil.copy('lib/pages.dart', 'lib/pages.dart.bak6')
shutil.copy('lib/screens.dart', 'lib/screens.dart.bak6')
for old, new in P_EDITS:
    pages = pages.replace(old, new)
screens = screens.replace(S_OLD, S_NEW)
open('lib/pages.dart', 'w', encoding='utf-8').write(pages)
open('lib/screens.dart', 'w', encoding='utf-8').write(screens)
print('patched lib/pages.dart and lib/screens.dart')
