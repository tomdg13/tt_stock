import 'package:flutter/foundation.dart' show compute;
// Image editor for product photos: crop / rotate, remove background (ML Kit), undo.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';

/// Opens the editor. Returns the edited image bytes, or null if cancelled.
Future<Uint8List?> editProductImage(BuildContext context, Uint8List bytes) {
  return Navigator.push<Uint8List>(
      context, MaterialPageRoute(builder: (_) => ImageEditorPage(bytes)));
}

Future<Uint8List?> _crop(Uint8List bytes) async {
  final dir = await Directory.systemTemp.createTemp('crop');
  try {
    final f = File('${dir.path}/in.jpg');
    await f.writeAsBytes(bytes);
    final out = await ImageCropper().cropImage(
      sourcePath: f.path,
      maxWidth: 1600,
      maxHeight: 1600,
      compressQuality: 88,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'ຕັດ / ໝຸນຮູບ',
          lockAspectRatio: false,
          initAspectRatio: CropAspectRatioPreset.original,
        ),
        IOSUiSettings(title: 'ຕັດ / ໝຸນຮູບ'),
      ],
    );
    return out == null ? null : await out.readAsBytes();
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Cuts out the main subject and puts a white background behind it.
Future<Uint8List> _removeBackgroundMlKit(Uint8List bytes) async {
  void log(String m) => debugPrint('[EDITOR][BG] $m');
  final sw = Stopwatch()..start();
  log('start: input ${bytes.length} bytes, android=${Platform.isAndroid}');
  if (!Platform.isAndroid) {
    throw Exception('ລຶບພື້ນຫຼັງໃຊ້ໄດ້ສະເພາະ Android');
  }
  final dir = await Directory.systemTemp.createTemp('seg');
  final seg = SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundBitmap: true,
      enableForegroundConfidenceMask: false,
      enableMultipleSubjects: SubjectResultOptions(
          enableConfidenceMask: false, enableSubjectBitmap: false),
    ),
  );
  try {
    final f = File('${dir.path}/in.jpg');
    await f.writeAsBytes(bytes);
    log('temp file written: ${f.path} (${await f.length()} bytes)');
    log('calling ML Kit processImage (60s timeout)...');
    final r = await seg
        .processImage(InputImage.fromFilePath(f.path))
        .timeout(const Duration(seconds: 20),
            onTimeout: () => throw Exception(
                'ML Kit timeout 60s (model not downloaded / no Google Play services?)'));
    log('ML Kit returned after ${sw.elapsedMilliseconds} ms: '
        'foregroundBitmap=${r.foregroundBitmap?.length} bytes, subjects=${r.subjects.length}');
    final fgBytes = r.foregroundBitmap;
    if (fgBytes == null || fgBytes.isEmpty) {
      throw Exception('ບໍ່ພົບວັດຖຸໃນຮູບ (foregroundBitmap is null/empty)');
    }
    log('foreground header bytes: ${fgBytes.take(8).toList()} (PNG starts 137,80,78,71)');
    final fg = img.decodeImage(fgBytes);
    log('decoded foreground: ${fg == null ? 'NULL' : '${fg.width}x${fg.height} channels=${fg.numChannels}'}');
    if (fg == null) {
      throw Exception('ອ່ານຜົນລັບບໍ່ໄດ້ (${fgBytes.length} bytes)');
    }
    final bg = img.Image(width: fg.width, height: fg.height, numChannels: 4);
    img.fill(bg, color: img.ColorRgba8(255, 255, 255, 255));
    img.compositeImage(bg, fg);
    final out = Uint8List.fromList(img.encodeJpg(bg, quality: 88));
    log('done: output ${out.length} bytes, total ${sw.elapsedMilliseconds} ms');
    return out;
  } finally {
    try {
      await seg.close();
    } catch (e) {
      log('seg.close error: $e');
    }
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Offline fallback: removes the background by flood-filling from the photo edges.
Uint8List _offlineCutout(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('ອ່ານຮູບບໍ່ໄດ້');
  img.Image im = decoded;
  const maxSide = 900;
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: maxSide)
        : img.copyResize(im, height: maxSide);
  }
  final w = im.width, h = im.height, n = w * h;
  final cr = Uint8List(n), cg = Uint8List(n), cb = Uint8List(n);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      final i = y * w + x;
      cr[i] = p.r.toInt();
      cg[i] = p.g.toInt();
      cb[i] = p.b.toInt();
    }
  }
  // background colour = median colour of the border pixels
  final lr = <int>[], lg = <int>[], lb = <int>[];
  void addB(int i) {
    lr.add(cr[i]);
    lg.add(cg[i]);
    lb.add(cb[i]);
  }

  for (var x = 0; x < w; x++) {
    addB(x);
    addB((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    addB(y * w);
    addB(y * w + w - 1);
  }
  int med(List<int> v) {
    v.sort();
    return v[v.length ~/ 2];
  }

  final rr = med(lr), rg = med(lg), rb = med(lb);
  const seedTol2 = 70 * 70, propTol2 = 90 * 90, stepTol2 = 20 * 20;
  int toRef(int i) {
    final a = cr[i] - rr, b = cg[i] - rg, c = cb[i] - rb;
    return a * a + b * b + c * c;
  }

  int step(int i, int j) {
    final a = cr[i] - cr[j], b = cg[i] - cg[j], c = cb[i] - cb[j];
    return a * a + b * b + c * c;
  }

  final mask = Uint8List(n);
  final stack = <int>[];
  void seed(int i) {
    if (mask[i] == 0 && toRef(i) < seedTol2) {
      mask[i] = 1;
      stack.add(i);
    }
  }

  void tryN(int c, int j) {
    if (mask[j] == 0 && toRef(j) < propTol2 && step(c, j) < stepTol2) {
      mask[j] = 1;
      stack.add(j);
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final c = stack.removeLast();
    final x = c % w, y = c ~/ w;
    if (x > 0) tryN(c, c - 1);
    if (x < w - 1) tryN(c, c + 1);
    if (y > 0) tryN(c, c - w);
    if (y < h - 1) tryN(c, c + w);
  }
  var bgCount = 0;
  for (var i = 0; i < n; i++) {
    bgCount += mask[i];
  }
  if (bgCount > n * 0.97) {
    throw Exception('ບໍ່ພົບວັດຖຸ (ພື້ນຫຼັງກວມທັງຮູບ)');
  }
  if (bgCount < n * 0.02) {
    throw Exception('ບໍ່ພົບພື້ນຫຼັງທີ່ຊັດເຈນ ລອງຕັດຮູບໃຫ້ເຫັນພື້ນຫຼັງກ່ອນ');
  }
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      var r = cr[i], g = cg[i], b = cb[i];
      if (mask[i] == 1) {
        r = 255;
        g = 255;
        b = 255;
      } else {
        final edge = (x > 0 && mask[i - 1] == 1) ||
            (x < w - 1 && mask[i + 1] == 1) ||
            (y > 0 && mask[i - w] == 1) ||
            (y < h - 1 && mask[i + w] == 1);
        if (edge) {
          r = (r + 255) ~/ 2;
          g = (g + 255) ~/ 2;
          b = (b + 255) ~/ 2;
        }
      }
      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 88));
}

/// Tries ML Kit first; if it is not available (model missing, iPhone, ...) uses the offline remover.
Future<Uint8List> _removeBackground(Uint8List bytes) async {
  try {
    return await _removeBackgroundMlKit(bytes);
  } catch (e) {
    debugPrint('[EDITOR][BG] ML Kit failed -> offline fallback. Reason: $e');
  }
  final out = await compute(_offlineCutout, bytes);
  debugPrint('[EDITOR][BG] offline cutout done: ${out.length} bytes');
  return out;
}

class ImageEditorPage extends StatefulWidget {
  final Uint8List bytes;
  const ImageEditorPage(this.bytes, {super.key});
  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  late final List<Uint8List> _hist = [widget.bytes];
  bool _busy = false;

  Uint8List get _cur => _hist.last;

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<Uint8List?> Function() job) async {
    setState(() => _busy = true);
    try {
      final r = await job();
      if (r != null && mounted) setState(() => _hist.add(r));
    } catch (e, st) {
      debugPrint('[EDITOR][BG] ERROR ${e.runtimeType}: $e\n$st');
      if (mounted) {
        final m = '$e';
        _toast(m.contains('optional module') || m.contains('downloaded')
            ? 'ກຳລັງດາວໂຫຼດໂມເດວ AI ຄັ້ງທຳອິດ ກະລຸນາລໍຖ້າ 1-2 ນາທີ ແລ້ວລອງໃໝ່'
            : m);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('ແກ້ໄຂຮູບ'),
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'ບັນທຶກ',
              onPressed: _busy ? null : () => Navigator.pop(context, _cur)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: InteractiveViewer(
                    child: Image.memory(_cur, fit: BoxFit.contain)),
              ),
            ),
            if (_busy)
              const Positioned.fill(
                  child: ColoredBox(
                      color: Colors.black54,
                      child: Center(child: CircularProgressIndicator()))),
          ]),
        ),
        SafeArea(
          top: false,
          child: Container(
            color: const Color(0xFF22252E),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _btn(Icons.crop_rotate, 'ຕັດ / ໝຸນ', () => _run(() => _crop(_cur))),
              _btn(Icons.auto_fix_high, 'ລຶບພື້ນຫຼັງ',
                  () => _run(() => _removeBackground(_cur))),
              _btn(Icons.undo, 'ຍ້ອນກັບ',
                  _hist.length > 1 ? () => setState(() => _hist.removeLast()) : null),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _btn(IconData i, String t, VoidCallback? f) => InkWell(
        onTap: _busy ? null : f,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, color: f == null ? Colors.white24 : Colors.white),
            const SizedBox(height: 4),
            Text(t,
                style: TextStyle(
                    fontSize: 12,
                    color: f == null ? Colors.white24 : Colors.white)),
          ]),
        ),
      );
}
