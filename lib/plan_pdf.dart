import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection;
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'api.dart';
import 'ldb_letterhead.dart';
import 'product_images.dart' show productImageUrl;
import 'widgets.dart';

const String _branchName = 'Head Office';
const String _toLine =
    'ຮຽນ: ທ່ານ ຫົວໜ້າຝ່າຍເຕັກໂນໂລຊີຂໍ້ມູນຂ່າວສານທີ່ນັບຖືຢ່າງສູງ';
const String _subjectLine = 'ເລື່ອງ: ຂໍຊື້ອາໄຫຼ່ເອທີເອັມ';
const String _closing1 =
    'ດັ່ງນັ້ນ ຈຶ່ງສະເໜີມາຍັງທ່ານເພື່ອພິຈາລະນາ ແລະ ແກ້ໄຂຕາມຄວາມເໝາະສົມດ້ວຍ.';
const String _closing2 = 'ຮຽນມາດ້ວຍຄວາມເຄົາລົບ ແລະ ນັບຖືຢ່າງສູງ.';
const String _sign1 = 'ຫົວໜ້າສາຂາ';
const String _sign2 = 'ຜູ້ສະເໜີ';

const List<String> _months = [
  'ມັງກອນ',
  'ກຸມພາ',
  'ມີນາ',
  'ເມສາ',
  'ພຶດສະພາ',
  'ມິຖຸນາ',
  'ກໍລະກົດ',
  'ສິງຫາ',
  'ກັນຍາ',
  'ຕຸລາ',
  'ພະຈິກ',
  'ທັນວາ',
];

const double _k = 3.0;

class _Ti {
  final Uint8List bytes;
  final double w;
  final double h;
  const _Ti(this.bytes, this.w, this.h);
}

final Map<String, _Ti> _cache = {};
bool _fontOk = false;

Future<void> _font() async {
  if (_fontOk) return;
  final a = FontLoader('PhetsarathPlan')
    ..addFont(rootBundle.load('assets/fonts/Phetsarath-OT.ttf'));
  await a.load();
  final b = FontLoader('PhetsarathPlanBold')
    ..addFont(rootBundle.load('assets/fonts/Phetsarath-OT-Bold.ttf'));
  await b.load();
  _fontOk = true;
}

Future<_Ti?> _render(String t, double size, bool bold, double maxW) async {
  final tp = TextPainter(
    text: TextSpan(
        text: t,
        style: TextStyle(
            fontFamily: bold ? 'PhetsarathPlanBold' : 'PhetsarathPlan',
            fontSize: size * _k,
            color: const ui.Color(0xFF000000))),
    textDirection: TextDirection.ltr,
  );
  if (maxW > 0) {
    tp.layout(maxWidth: maxW * _k);
  } else {
    tp.layout();
  }
  final w = tp.width.ceil() + 2;
  final h = tp.height.ceil() + 2;
  final rec = ui.PictureRecorder();
  final cv = ui.Canvas(rec);
  tp.paint(cv, const ui.Offset(1, 1));
  final im = await rec.endRecording().toImage(w, h);
  final bd = await im.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) return null;
  return _Ti(bd.buffer.asUint8List(), w.toDouble() / _k, h.toDouble() / _k);
}

Future<pw.Widget> _t(String t,
    {double size = 10, bool bold = false, double maxW = 0}) async {
  if (t.isEmpty) return pw.SizedBox(height: size + 2);
  final key = '${bold ? 1 : 0}|$size|$maxW|$t';
  final c = _cache[key] ?? await _render(t, size, bold, maxW);
  if (c == null) {
    return pw.Text(t, style: pw.TextStyle(fontSize: size));
  }
  _cache[key] = c;
  return pw.Image(pw.MemoryImage(c.bytes), width: c.w, height: c.h);
}

Future<pw.Widget> _c(String t,
    {bool bold = false,
    bool right = false,
    bool center = false,
    double maxW = 0}) async {
  final w = await _t(t, size: 9, bold: bold, maxW: maxW);
  final al = right
      ? pw.Alignment.centerRight
      : (center ? pw.Alignment.center : pw.Alignment.centerLeft);
  return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Align(alignment: al, child: w));
}

List<Object>? _makeThumb(Uint8List b) {
  final im = img.decodeImage(b);
  if (im == null) return null;
  final sq = img.copyResizeCropSquare(im, size: 96);
  final jpg = Uint8List.fromList(img.encodeJpg(sq, quality: 78));
  return <Object>[jpg];
}

Future<Map<String, Uint8List>> _loadThumbs(Set<String> urls) async {
  final out = <String, Uint8List>{};
  final headers = Api.token == null
      ? <String, String>{}
      : <String, String>{'Authorization': 'Bearer ${Api.token}'};
  await Future.wait(urls.map((u) async {
    try {
      final res = await http
          .get(Uri.parse(u), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final r = await compute(_makeThumb, res.bodyBytes);
        if (r is List<Object>) {
          out[u] = r[0] as Uint8List;
        }
      }
    } catch (e) {
      debugPrint('[PLANPDF] image failed $u: $e');
    }
  }));
  return out;
}

String _q(num v) => v % 1 == 0 ? '${v.toInt()}' : '$v';

String _two(int n) => n < 10 ? '0$n' : '$n';

Future<pw.Widget> _sig(String title) async {
  final t = await _t(title, size: 10, bold: true);
  return pw.Column(children: [t, pw.SizedBox(height: 60)]);
}

Future<void> exportPlanPdf(
    Map<String, dynamic> plan, List<Map<String, dynamic>> items) async {
  await _font();
  final rows = items.where((x) => x['done'] == true).toList();
  rows.sort((a, b) {
    final c = '${a['brand'] ?? ''}'.compareTo('${b['brand'] ?? ''}');
    if (c == 0) return '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
    return c;
  });

  final urls = <String>{};
  for (final it in rows) {
    final u = productImageUrl('${it['imageUrl'] ?? ''}');
    if (u.isNotEmpty) urls.add(u);
  }
  final thumbs = await _loadThumbs(urls);
  debugPrint('[PLANPDF] images ${thumbs.length}/${urls.length}');

  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(34),
    1: const pw.FlexColumnWidth(1),
    2: const pw.FixedColumnWidth(62),
    3: const pw.FixedColumnWidth(58),
    4: const pw.FixedColumnWidth(50),
    5: const pw.FixedColumnWidth(44),
  };

  final trs = <pw.TableRow>[];
  trs.add(pw.TableRow(repeat: true,
    children: [
      await _c('ລຳດັບ', bold: true, center: true),
      await _c('ອາໄຫຼ່', bold: true, center: true),
      await _c('ຍີ່ຫໍ້', bold: true, center: true),
      await _c('ທີ່ເກັບ', bold: true, center: true),
      await _c('ຈຳນວນ', bold: true, center: true),
      await _c('ໜ່ວຍ', bold: true, center: true),
    ],
  ));

  var sumQty = 0.0;
  for (var i = 0; i < rows.length; i++) {
    final x = rows[i];
    final u = productImageUrl('${x['imageUrl'] ?? ''}');
    final th = thumbs[u];
    final qv = x['buyQty'] ?? x['must'] ?? x['qty'];
    final qn = num0(qv).toDouble();
    sumQty += qn;
    final nameW = await _t(_nm(x), size: 9, maxW: 240);
    if (_newBrand(rows, i)) {
      trs.add(await _brandRow(rows, i, widths.length, 1));
    }
    trs.add(pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        await _c('${i + 1}', center: true),
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (th != null)
                  pw.Image(pw.MemoryImage(th),
                      width: 44, height: 44, fit: pw.BoxFit.fill),
                if (th != null) pw.SizedBox(height: 3),
                nameW,
              ]),
        ),
        await _c('${x['brand'] ?? ''}', center: true),
        await _c('${x['bin'] ?? ''}', center: true),
        await _c(_q(qn), bold: true, center: true),
        await _c('${x['unit'] ?? ''}', center: true),
      ],
    ));
  }

  trs.add(pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
    children: [
      await _c(''),
      await _c('ລວມ ${rows.length} ລາຍການ', bold: true),
      await _c(''),
      await _c(''),
      await _c(_q(sumQty), bold: true, center: true),
      await _c(''),
    ],
  ));

  final n = DateTime.now();
  final dateLao = '${n.day} ${_months[n.month - 1]} ${n.year}';
  final planName = '${plan['name'] ?? ''}';
  final note = '${plan['note'] ?? ''}';

  final left = await _t('ສາຂາ $_branchName', size: 10);
  final noLine = await _t('ເລກທີ່: ................................', size: 10);
  final dateLine = await _t('$_branchName, ວັນທີ $dateLao', size: 10);
  final title = await _t('ໜັງສືສະເໜີ', size: 20, bold: true);
  final toW = await _t(_toLine, size: 10, maxW: 520);
  final subW = await _t(_subjectLine, size: 10, maxW: 520);
  final planW = await _t('- ອີງຕາມແຜນຊື້: $planName', size: 10, maxW: 520);
  final noteW = note.isEmpty
      ? null
      : await _t('- ໝາຍເຫດ: $note', size: 10, maxW: 520);
  final intro = await _t(
      'ສາຂາ $_branchName ຂໍຖືເປັນກຽດສະເໜີມາຍັງທ່ານເພື່ອຂໍຊື້ອາໄຫຼ່ເອທີເອັມ ຕາມລາຍລະອຽດດັ່ງລຸ່ມນີ້:',
      size: 10,
      maxW: 490);
  final cl1 = await _t(_closing1, size: 10, maxW: 490);
  final cl2 = await _t(_closing2, size: 10, maxW: 520);
  final s1 = await _sig(_sign1);
  final s2 = await _sig(_sign2);

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
      pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            left,
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [noLine, pw.SizedBox(height: 3), dateLine]),
          ]),
      pw.SizedBox(height: 14),
      pw.Center(child: title),
      pw.SizedBox(height: 14),
      toW,
      pw.SizedBox(height: 4),
      subW,
      pw.SizedBox(height: 4),
      planW,
      if (noteW != null) pw.SizedBox(height: 4),
      if (noteW != null) noteW,
      pw.SizedBox(height: 8),
      pw.Padding(padding: const pw.EdgeInsets.only(left: 30), child: intro),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: widths,
        children: trs,
      ),
      pw.SizedBox(height: 10),
      pw.Padding(padding: const pw.EdgeInsets.only(left: 30), child: cl1),
      pw.SizedBox(height: 4),
      pw.Align(alignment: pw.Alignment.centerRight, child: cl2),
      pw.SizedBox(height: 24),
      pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [s1, s2]),
    ],
  ));

  final bytes = await doc.save();
  await Printing.sharePdf(
      bytes: bytes,
      filename: 'buyplan_${n.year}${_two(n.month)}${_two(n.day)}.pdf');
}

Future<pw.TableRow> _sheetHead() async {
  return pw.TableRow(repeat: true,
    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
    children: [
      await _c('ລຳດັບ', bold: true, center: true),
      await _c('ຮູບ', bold: true, center: true),
      await _c('ສິນຄ້າ', bold: true, center: true),
      await _c('ສະຕັອກ', bold: true, center: true),
      await _c('ນັບຕົວຈິງ', bold: true, center: true),
      await _c('ໃຊ້', bold: true, center: true),
      await _c('ຕ້ອງຊື້', bold: true, center: true),
      await _c('ຊື້ມາແລ້ວ', bold: true, center: true),
      await _c('ຊື້ແຜນນີ້', bold: true, center: true),
    ],
  );
}

String _num(dynamic v) => v is num ? _q(v) : '-';

Future<void> exportPlanSheetPdf(
    Map<String, dynamic> plan, List<Map<String, dynamic>> items) async {
  await _font();
  final rows = items.where((x) => x['done'] == true).toList();
  rows.sort((a, b) {
    final c = '${a['brand'] ?? ''}'.compareTo('${b['brand'] ?? ''}');
    if (c == 0) return '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
    return c;
  });

  final urls = <String>{};
  for (final it in rows) {
    final u = productImageUrl('${it['imageUrl'] ?? ''}');
    if (u.isNotEmpty) urls.add(u);
  }
  final thumbs = await _loadThumbs(urls);

  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(30),
    1: const pw.FixedColumnWidth(46),
    2: const pw.FlexColumnWidth(1),
    3: const pw.FixedColumnWidth(44),
    4: const pw.FixedColumnWidth(52),
    5: const pw.FixedColumnWidth(36),
    6: const pw.FixedColumnWidth(48),
    7: const pw.FixedColumnWidth(44),
    8: const pw.FixedColumnWidth(52),
  };

  var sumMust = 0.0;
  var sumBuy = 0.0;
  final chunks = <List<pw.TableRow>>[];
  var cur = <pw.TableRow>[];
  for (var i = 0; i < rows.length; i++) {
    final x = rows[i];
    final u = productImageUrl('${x['imageUrl'] ?? ''}');
    final th = thumbs[u];
    final must = x['isNew'] == true ? null : (x['must'] ?? x['qty']);
    if (must is num) sumMust += must.toDouble();
    final buy = x['buyQty'];
    if (buy is num) sumBuy += buy.toDouble();
    if (_newBrand(rows, i)) {
      cur.add(await _brandRow(rows, i, widths.length, 2));
    }
    cur.add(pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        await _c('${i + 1}', center: true),
        pw.Padding(
          padding: const pw.EdgeInsets.all(3),
          child: th is Uint8List
              ? pw.Image(pw.MemoryImage(th),
                  width: 38, height: 38, fit: pw.BoxFit.fill)
              : pw.SizedBox(width: 38, height: 38),
        ),
        await _c(_nm(x), maxW: 180),
        await _c(_num(x['stock']), center: true),
        await _c(_num(x['counted']), center: true),
        await _c(_num(x['used']), center: true),
        await _c(_num(must), bold: true, center: true),
        await _c(_oth(x['other']), center: true),
        await _c(_num(buy), bold: true, center: true),
      ],
    ));
    if (cur.length == 100000) {
      chunks.add(cur);
      cur = <pw.TableRow>[];
    }
  }
  if (cur.isNotEmpty) chunks.add(cur);

  final n = DateTime.now();
  final body = <pw.Widget>[...await _letterTop(plan)];
  for (var k = 0; k < chunks.length; k++) {
    final head = await _sheetHead();
    final list = <pw.TableRow>[head, ...chunks[k]];
    if (k == chunks.length - 1) {
      list.add(pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          await _c(''),
          await _c(''),
          await _c('ລວມ', bold: true),
          await _c(''),
          await _c(''),
          await _c(''),
          await _c(_q(sumMust), bold: true, center: true),
          await _c(''),
          await _c(_q(sumBuy), bold: true, center: true),
        ],
      ));
    }
    body.add(pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: widths,
      children: list,
    ));
  }

  body.add(await _letterBottom());

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
    build: (ctx) => body,
  ));

  final bytes = await doc.save();
  await Printing.sharePdf(
      bytes: bytes,
      filename:
          'buyplan_sheet_${n.year}${_two(n.month)}${_two(n.day)}.pdf');
}

Future<List<pw.Widget>> _letterTop(Map<String, dynamic> plan) async {
  final n = DateTime.now();
  final dateLao = '${n.day} ${_months[n.month - 1]} ${n.year}';
  final planName = '${plan['name'] ?? ''}';
  final note = '${plan['note'] ?? ''}';
  final left = await _t('ສາຂາ $_branchName', size: 10);
  final noLine = await _t('ເລກທີ່: ................................', size: 10);
  final dateLine = await _t('$_branchName, ວັນທີ $dateLao', size: 10);
  final title = await _t('ໜັງສືສະເໜີ', size: 20, bold: true);
  final toW = await _t(_toLine, size: 10, maxW: 520);
  final subW = await _t(_subjectLine, size: 10, maxW: 520);
  final planW = await _t('- ອີງຕາມແຜນຊື້: $planName', size: 10, maxW: 520);
  final pw.Widget? noteW =
      note.isEmpty ? null : await _t('- ໝາຍເຫດ: $note', size: 10, maxW: 520);
  final intro = await _t(
      'ສາຂາ $_branchName ຂໍຖືເປັນກຽດສະເໜີມາຍັງທ່ານເພື່ອຂໍຊື້ອາໄຫຼ່ເອທີເອັມ ຕາມລາຍລະອຽດດັ່ງລຸ່ມນີ້:',
      size: 10,
      maxW: 490);
  return <pw.Widget>[
    pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          left,
          pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [noLine, pw.SizedBox(height: 3), dateLine]),
        ]),
    pw.SizedBox(height: 14),
    pw.Center(child: title),
    pw.SizedBox(height: 14),
    toW,
    pw.SizedBox(height: 4),
    subW,
    pw.SizedBox(height: 4),
    planW,
    if (noteW is pw.Widget) pw.SizedBox(height: 4),
    if (noteW is pw.Widget) noteW,
    pw.SizedBox(height: 8),
    pw.Padding(padding: const pw.EdgeInsets.only(left: 30), child: intro),
    pw.SizedBox(height: 8),
  ];
}

Future<pw.Widget> _letterBottom() async {
  final cl1 = await _t(_closing1, size: 10, maxW: 490);
  final cl2 = await _t(_closing2, size: 10, maxW: 520);
  final s1 = await _sig(_sign1);
  final s2 = await _sig(_sign2);
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.SizedBox(height: 12),
    pw.Padding(padding: const pw.EdgeInsets.only(left: 30), child: cl1),
    pw.SizedBox(height: 4),
    pw.Align(alignment: pw.Alignment.centerRight, child: cl2),
    pw.SizedBox(height: 24),
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
      s1,
      s2,
    ]),
  ]);
}

String _nm(Map<String, dynamic> x) {
  final n = '${x['name'] ?? ''}';
  return x['isNew'] == true ? '$n\n(ເຄື່ອງທີ່ບໍ່ເຄີຍຊື້)' : n;
}

String _oth(dynamic v) => (v is num && v > 0) ? _q(v) : '-';

bool _newBrand(List<Map<String, dynamic>> rows, int i) {
  if (i == 0) return true;
  final a = '${rows[i - 1]['brand'] ?? ''}';
  final b = '${rows[i]['brand'] ?? ''}';
  return a.compareTo(b) < 0;
}

Future<pw.TableRow> _brandRow(
    List<Map<String, dynamic>> rows, int i, int cols, int labelCol) async {
  final b = '${rows[i]['brand'] ?? ''}';
  final cnt = rows.where((y) => '${y['brand'] ?? ''}' == b).length;
  final label = b.isEmpty ? '(ບໍ່ມີ Brand)' : b;
  final cells = <pw.Widget>[];
  for (var c = 0; c < cols; c++) {
    cells.add(c == labelCol
        ? await _c('$label ($cnt)', bold: true)
        : await _c(''));
  }
  return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: cells);
}
