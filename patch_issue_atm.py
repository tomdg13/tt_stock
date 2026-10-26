import shutil

path = 'lib/pages.dart'
s = open(path, encoding='utf-8').read()

if '_atmId' in s:
    raise SystemExit('ABORT: already patched')

EDITS = [
    # state fields
    (
        "  final _lines = <Line>[];\n"
        "  List<Map<String, dynamic>> _branches = [];\n"
        "  dynamic _branchId;\n"
        "  String _reason = 'sale';\n",
        "  final _lines = <Line>[];\n"
        "  List<Map<String, dynamic>> _branches = [];\n"
        "  dynamic _branchId;\n"
        "  List<Map<String, dynamic>> _atms = [];\n"
        "  String? _atmId;\n"
        "  String _reason = 'sale';\n",
    ),
    # load active ATMs
    (
        "    }).catchError((_) {});\n"
        "  }\n"
        "\n"
        "  Future<void> _submit() async {",
        "    }).catchError((_) {});\n"
        "    Api.get('/atms?limit=500').then((d) {\n"
        "      if (!mounted) return;\n"
        "      setState(() {\n"
        "        _atms = [\n"
        "          for (final m in asList(d))\n"
        "            if (pick(m, ['atmStatus', 'status']).toLowerCase() == 'active') m,\n"
        "        ];\n"
        "      });\n"
        "    }).catchError((_) {});\n"
        "  }\n"
        "\n"
        "  Future<void> _submit() async {",
    ),
    # request body: server expects 'reason'; add atmId
    (
        "        if (widget.issue) 'type': _reason,\n",
        "        if (widget.issue) 'reason': _reason,\n"
        "        if (widget.issue && _atmId != null) 'atmId': _atmId,\n",
    ),
    # reset after save
    (
        "        _lines.clear();\n"
        "        _note.clear();\n",
        "        _lines.clear();\n"
        "        _note.clear();\n"
        "        _atmId = null;\n",
    ),
    # dropdown under the reason field
    (
        "              onChanged: (v) => setState(() { _reason = v ?? 'sale'; }),\n"
        "            ),\n"
        "          ],\n",
        "              onChanged: (v) => setState(() { _reason = v ?? 'sale'; }),\n"
        "            ),\n"
        "            const SizedBox(height: 12),\n"
        "            DropdownButtonFormField<String>(\n"
        "              initialValue: _atmId,\n"
        "              isExpanded: true,\n"
        "              decoration: const InputDecoration(labelText: 'ຕູ້ ATM (ບໍ່ບັງຄັບ)'),\n"
        "              items: [\n"
        "                const DropdownMenuItem<String>(value: null, child: Text('— ບໍ່ລະບຸ —')),\n"
        "                for (final m in _atms)\n"
        "                  DropdownMenuItem<String>(\n"
        "                    value: pick(m, ['atmId']),\n"
        "                    child: Text(\n"
        "                      '${pick(m, ['atmId'])} · ${pick(m, ['atmLocation', 'location'])}',\n"
        "                      overflow: TextOverflow.ellipsis,\n"
        "                    ),\n"
        "                  ),\n"
        "              ],\n"
        "              onChanged: (v) => setState(() { _atmId = v; }),\n"
        "            ),\n"
        "          ],\n",
    ),
]

for i, (old, _) in enumerate(EDITS, 1):
    if s.count(old) != 1:
        raise SystemExit('ABORT edit %d: expected 1 match, found %d' % (i, s.count(old)))

shutil.copy(path, path + '.bak5')
for old, new in EDITS:
    s = s.replace(old, new)
open(path, 'w', encoding='utf-8').write(s)
print('patched', path)
