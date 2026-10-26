import shutil


def patch(path, edits):
    s = open(path, encoding='utf-8').read()
    for old, new in edits:
        if s.count(old) != 1:
            raise SystemExit(
                "ABORT %s: expected 1 match, found %d for:\n%s" % (path, s.count(old), old)
            )
    shutil.copy(path, path + '.bak')
    for old, new in edits:
        s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)
    print("patched", path)


patch('lib/crud.dart', [
    (
        "  final List<String> titleKeys, subKeys, tagKeys, trailKeys;\n",
        "  final List<String> titleKeys, subKeys, tagKeys, trailKeys;\n"
        "  final bool Function(Map<String, dynamic>)? rowFilter;\n",
    ),
    (
        "    this.tagKeys = const [],\n",
        "    this.tagKeys = const [],\n    this.rowFilter,\n",
    ),
    (
        "          tagKeys: sp.tagKeys,\n",
        "          tagKeys: sp.tagKeys,\n          rowFilter: sp.rowFilter,\n",
    ),
])

patch('lib/specs.dart', [
    (
        "tagKeys: const ['atmStatus', 'status'],\n        detailPath: (r) => '/atms/",
        "tagKeys: const ['atmStatus', 'status'],\n"
        "        rowFilter: (r) => pick(r, ['atmStatus', 'status']).toLowerCase() == 'active',\n"
        "        detailPath: (r) => '/atms/",
    ),
])
