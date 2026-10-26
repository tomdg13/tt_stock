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


patch('lib/widgets.dart', [
    (
        "  final Widget Function(BuildContext, Map<String, dynamic>)? rowActions;\n",
        "  final Widget Function(BuildContext, Map<String, dynamic>)? rowActions;\n"
        "  final bool Function(Map<String, dynamic>)? rowFilter;\n",
    ),
    (
        "    this.rowActions,\n  });",
        "    this.rowActions,\n    this.rowFilter,\n  });",
    ),
    (
        "            final items = asList(s.data);\n",
        "            final all = asList(s.data);\n"
        "            final items = widget.rowFilter == null ? all : all.where(widget.rowFilter!).toList();\n",
    ),
])

patch('lib/screens.dart', [
    (
        "detailPath: (m) => '/atms/${Uri.encodeComponent(pick(m, ['atmId']))}',",
        "detailPath: (m) => '/atms/${Uri.encodeComponent(pick(m, ['atmId']))}',\n"
        "          rowFilter: (m) => pick(m, ['atmStatus', 'status']).toLowerCase() == 'active',",
    ),
])
