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
Future<Uint8List> _removeBackground(Uint8List bytes) async {
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
    final r = await seg.processImage(InputImage.fromFilePath(f.path));
    final fgBytes = r.foregroundBitmap;
    if (fgBytes == null) throw Exception('ບໍ່ພົບວັດຖຸໃນຮູບ');
    final fg = img.decodeImage(fgBytes);
    if (fg == null) {
      throw Exception('ອ່ານຜົນລັບບໍ່ໄດ້ (${fgBytes.length} bytes)');
    }
    final bg = img.Image(width: fg.width, height: fg.height, numChannels: 4);
    img.fill(bg, color: img.ColorRgba8(255, 255, 255, 255));
    img.compositeImage(bg, fg);
    return Uint8List.fromList(img.encodeJpg(bg, quality: 88));
  } finally {
    await seg.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
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
    } catch (e) {
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
