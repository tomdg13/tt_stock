import 'dart:ui' as ui;
import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection;
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'api.dart';
import 'ldb_letterhead.dart';

const double _sc = 3.0;
bool _fontOk = false;
final RegExp _needImg = RegExp(r'[^\x00-\x7F]');

Future<void> _ensureFonts() async {
  if (_fontOk) return;
  final a = FontLoader('PhetsarathReq')
    ..addFont(rootBundle.load('assets/fonts/Phetsarath-OT.ttf'));
  await a.load();
  final b = FontLoader('PhetsarathReqBold')
    ..addFont(rootBundle.load('assets/fonts/Phetsarath-OT-Bold.ttf'));
  await b.load();
  _fontOk = true;
}

pw.Widget _plain(String t, double size, bool bold) => pw.Text(t,
    style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));

Future<pw.Widget> _txt(String t,
    {double size = 10,
    bool bold = false,
    double maxW = 520,
    pw.Alignment al = pw.Alignment.centerLeft}) async {
  if (t.isEmpty) return pw.SizedBox(height: size);
  if (!_needImg.hasMatch(t)) return _plain(t, size, bold);
  await _ensureFonts();
  final tp = TextPainter(
    text: TextSpan(
        text: t,
        style: TextStyle(
            fontFamily: bold ? 'PhetsarathReqBold' : 'PhetsarathReq',
            fontSize: size * _sc,
            color: const ui.Color(0xFF000000))),
    textDirection: TextDirection.ltr,
  );
  tp.layout(maxWidth: maxW * _sc);
  final w = tp.width.ceil() + 2;
  final h = tp.height.ceil() + 2;
  final rec = ui.PictureRecorder();
  final cv = ui.Canvas(rec);
  tp.paint(cv, const ui.Offset(1, 1));
  final im = await rec.endRecording().toImage(w, h);
  final bd = await im.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) return _plain(t, size, bold);
  return pw.Align(
    alignment: al,
    child: pw.Image(pw.MemoryImage(bd.buffer.asUint8List()),
        width: w / _sc, height: h / _sc),
  );
}

pw.Widget _cell(pw.Widget w) =>
    pw.Padding(padding: const pw.EdgeInsets.all(4), child: w);

String _s(dynamic m, String k) {
  if (m is Map) {
    final v = m[k];
    return v == null ? '' : '$v';
  }
  return '';
}

String _date(dynamic v) {
  final d = DateTime.tryParse('$v');
  if (d == null) return '';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

Future<pw.Widget> _sig(String label) async {
  return pw.SizedBox(
    width: 200,
    child: pw.Column(children: [
      await _txt(label,
          size: 11, bold: true, maxW: 200, al: pw.Alignment.center),
      pw.SizedBox(height: 44),
      pw.Container(width: 150, height: 0.8, color: PdfColors.black),
      pw.SizedBox(height: 4),
      await _txt('ວັນທີ: ......../......../............',
          size: 9, maxW: 200, al: pw.Alignment.center),
    ]),
  );
}

Future<void> shareRepairRequestPdf(int caseId) async {
  final c = await Api.get('/repair/cases/$caseId');
  if (c is! Map) throw Exception('ບໍ່ພົບເຄດ');
  var branchName = '';
  try {
    final bl = await Api.get('/repair/branches');
    if (bl is List) {
      for (final b in bl) {
        if (b is Map && '${b['id']}' == '${c['branchId']}') {
          branchName = '${b['name'] ?? ''}';
          break;
        }
      }
    }
  } catch (_) {}
  final reqNo = _s(c, 'reqNo');
  final remark = _s(c, 'remark');
  final parts = c['parts'] is List ? c['parts'] as List : const [];

  final info = <pw.Widget>[
    await _txt('ເລກຄຳຂໍ: $reqNo', size: 11),
    pw.SizedBox(height: 3),
    await _txt('ວັນທີ: ${_date(c['openedAt'])}', size: 11),
    pw.SizedBox(height: 3),
    await _txt('ບາໂຄດຕູ້ (Terminal): ${_s(c, 'barcode')}', size: 11),
    pw.SizedBox(height: 3),
    await _txt('ຕູ້ ATM: ${_s(c, 'atmId')}', size: 11),
    pw.SizedBox(height: 3),
    await _txt('ສາຂາ: $branchName', size: 11),
    if (remark.isNotEmpty) pw.SizedBox(height: 3),
    if (remark.isNotEmpty) await _txt('ໝາຍເຫດ: $remark', size: 11),
  ];

  final head = ['ລ/ດ', 'ລາຍການອາໄຫຼ່', 'Part No', 'ຈຳນວນ', 'ໜ່ວຍ'];
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        for (final h in head)
          _cell(await _txt(h, size: 10, bold: true, maxW: 200)),
      ],
    ),
  ];
  var i = 0;
  for (final p in parts) {
    i++;
    rows.add(pw.TableRow(children: [
      _cell(await _txt('$i', size: 10, maxW: 30)),
      _cell(await _txt(_s(p, 'name'), size: 10, maxW: 250)),
      _cell(await _txt(_s(p, 'partNo'), size: 10, maxW: 110)),
      _cell(await _txt(_s(p, 'qty'), size: 10, maxW: 40)),
      _cell(await _txt(_s(p, 'unit'), size: 10, maxW: 40)),
    ]));
  }

  final title = await _txt('ໃບຂໍເບີກອາໄຫຼ່ ເພື່ອສ້ອມແປງ', size: 16, bold: true);
  final sig1 = await _sig('ຜູ້ຂໍ');
  final sig2 = await _sig('ຫົວໜ້າສາຂາ');

  final lh = await loadLetterhead();
  final pageW = PdfPageFormat.a4.width;
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.fromLTRB(
          24, pageW * lh.headerRatio + 10, 24, pageW * lh.footerRatio + 8),
      buildBackground: (ctx) => ldbPdfBackground(lh),
    ),
    build: (ctx) => [
      title,
      pw.SizedBox(height: 10),
      ...info,
      pw.SizedBox(height: 12),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(30),
          1: const pw.FlexColumnWidth(4),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FixedColumnWidth(44),
          4: const pw.FixedColumnWidth(44),
        },
        children: rows,
      ),
      pw.SizedBox(height: 40),
      pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [sig1, sig2]),
    ],
  ));

  final bytes = await doc.save();
  await Printing.sharePdf(bytes: bytes, filename: 'RepairRequest_$reqNo.pdf');
}
