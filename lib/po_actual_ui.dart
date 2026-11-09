import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api.dart';

String _lak(Object? v) {
  final n = (v is num) ? v.round() : (num.tryParse('$v') ?? 0).round();
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

String _dt(Object? v) {
  final d = DateTime.tryParse('$v');
  if (d == null) return '';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

List<dynamic> _asL(dynamic d) {
  if (d is List) return d;
  if (d is Map && d['data'] is List) return d['data'] as List;
  return <dynamic>[];
}

Future<void> poActualMenu(BuildContext context, String poNo) async {
  debugPrint('[PO-UP] menu opened poNo=$poNo');
  final act = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('ອັບໂຫຼດ Excel'),
          subtitle: const Text('ໄຟລ໌ທີ່ບັນຊີແກ້ຖັນ F ແລ້ວ'),
          onTap: () => Navigator.pop(c, 'up'),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('ປະຫວັດການອັບໂຫຼດ'),
          onTap: () => Navigator.pop(c, 'hist'),
        ),
      ]),
    ),
  );
  if (context.mounted == false) return;
  if (act == 'up') {
    await poActualUpload(context, poNo);
  } else if (act == 'hist') {
    await poActualHistory(context, poNo);
  }
}

Future<void> poActualUpload(BuildContext context, String poNo) async {
  debugPrint('[PO-UP] start poNo=$poNo base=${Api.baseUrl} tokenNull=${Api.token == null}');
  final messenger = ScaffoldMessenger.of(context);
  void toast(String t) => messenger.showSnackBar(
      SnackBar(content: Text(t), duration: const Duration(seconds: 6)));
  try {
    final picked = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx']);
    if (picked.isEmpty) {
      debugPrint('[PO-UP] picker cancelled');
      return;
    }
    final f = picked.first;
    debugPrint('[PO-UP] picked name=${f.name} path=${f.path}');
    final fp = f.path;
    final bytes = fp == null ? null : await File(fp).readAsBytes();
    if (bytes == null) {
      toast('ອ່ານໄຟລ໌ບໍ່ໄດ້');
      return;
    }
    toast('ກຳລັງອັບໂຫຼດ...');
    final base = Api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final req =
        http.MultipartRequest('POST', Uri.parse('$base/po-actual/upload'));
    final tk = Api.token;
    if (tk != null) req.headers['Authorization'] = 'Bearer $tk';
    req.fields['poNo'] = poNo;
    req.files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: f.name));
    debugPrint('[PO-UP] POST ${req.url} bytes=${bytes.length}');
    final res = await http.Response.fromStream(await req.send());
    debugPrint('[PO-UP] status=${res.statusCode} body=${utf8.decode(res.bodyBytes, allowMalformed: true)}');
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      body = null;
    }
    messenger.hideCurrentSnackBar();
    if (res.statusCode >= 200 && res.statusCode < 300 && body is Map) {
      toast(
          'ອັບໂຫຼດແລ້ວ v${body['version']} · ${body['itemCount']} ລາຍການ · ${_lak(body['totalLak'])} LAK · ${body['uploadedBy']}');
      return;
    }
    var msg = 'ອັບໂຫຼດບໍ່ສຳເລັດ (${res.statusCode})';
    if (body is Map) {
      final m = body['message'] ?? body['error'];
      if (m is String) {
        msg = m;
      } else if (m is List) {
        msg = m.join(' ');
      }
    }
    toast(msg);
  } catch (e, st) {
    debugPrint('[PO-UP] EXCEPTION: $e\n$st');
    debugPrint('[PO] upload failed: $e');
    messenger.hideCurrentSnackBar();
    toast('ອັບໂຫຼດບໍ່ສຳເລັດ: $e');
  }
}

Future<void> poActualHistory(BuildContext context, String poNo) async {
  List<dynamic> list = <dynamic>[];
  try {
    final d =
        await Api.get('/po-actual?poNo=${Uri.encodeQueryComponent(poNo)}');
    list = _asL(d);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ໂຫຼດບໍ່ສຳເລັດ: $e')));
    }
    return;
  }
  if (context.mounted == false) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
        child: list.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('ຍັງບໍ່ມີການອັບໂຫຼດ'))
            : ListView.separated(
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final m = list[i] as Map;
                  final latest = m['isLatest'] == true;
                  return ListTile(
                    leading: CircleAvatar(child: Text('v${m['versionNo']}')),
                    title: Text(
                        '${_lak(m['totalLak'])} LAK${latest ? '  · ຫຼ້າສຸດ' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${m['uploadedByName'] ?? '-'} · ${_dt(m['uploadedAt'])}\n${m['fileName'] ?? ''} · ${m['itemCount']} ລາຍການ'),
                    isThreeLine: true,
                    onTap: () => _items(context, m['id'], m['versionNo']),
                  );
                },
              ),
      ),
    ),
  );
}

Future<void> _items(BuildContext context, Object? id, Object? ver) async {
  try {
    final d = await Api.get('/po-actual/$id');
    final rows = _asL(d);
    if (context.mounted == false) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('v$ver'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: rows.map((r) {
              final m = r as Map;
              final nt = '${m['note'] ?? ''}';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${m['itemName'] ?? m['itemId']}'),
                subtitle: m['actualUnitLak'] == null
                    ? (nt.isEmpty ? null : Text(nt))
                    : Text('${_lak(m['actualUnitLak'])} × ${m['qty']}${nt.isEmpty ? '' : ' · $nt'}'),
                trailing: Text('${_lak(m['actualLak'])} LAK',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('ປິດ'))
        ],
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ໂຫຼດບໍ່ສຳເລັດ: $e')));
    }
  }
}
