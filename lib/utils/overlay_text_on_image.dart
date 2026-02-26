import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Ve chu len anh bang Flutter Canvas + TextPainter de hien thi dung chu Viet (co dau).
/// Luu ket qua ra file JPEG.
Future<bool> overlayTextOnImage({
  required Uint8List imageBytes,
  required String outputPath,
  required String overlayText,
}) async {
  ui.Image? decodedImage;
  try {
    decodedImage = await _decodeImage(imageBytes);
    if (decodedImage == null) return false;

    final w = decodedImage.width.toDouble();
    final h = decodedImage.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawImageRect(
      decodedImage,
      Rect.fromLTWH(0, 0, w, h),
      Rect.fromLTWH(0, 0, w, h),
      Paint(),
    );

    final fontSize = (w / 18).clamp(22.0, 36.0);
    final textPainter = TextPainter(
      text: TextSpan(
        text: overlayText,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          height: 1.25,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(color: Colors.black, offset: Offset(1, 1), blurRadius: 2),
            Shadow(color: Colors.black54, offset: Offset(0, 0), blurRadius: 1),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: w - 48);
    final textHeight = textPainter.height;
    final padding = fontSize * 0.6;
    final y = (h - textHeight - padding).clamp(padding, h - padding - 8);
    textPainter.paint(canvas, Offset(24, y));

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(decodedImage.width, decodedImage.height);
    final byteData = await outImage.toByteData(format: ui.ImageByteFormat.png);
    outImage.dispose();
    decodedImage.dispose();

    if (byteData == null) return false;
    final pngBytes = byteData.buffer.asUint8List();
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) return false;
    final jpegBytes = img.encodeJpg(decoded, quality: 90);
    await File(outputPath).writeAsBytes(jpegBytes);
    return true;
  } catch (_) {
    decodedImage?.dispose();
    return false;
  }
}

Future<ui.Image?> _decodeImage(Uint8List bytes) async {
  final completer = Completer<ui.Image?>();
  ui.decodeImageFromList(bytes, (ui.Image image) {
    if (!completer.isCompleted) completer.complete(image);
  });
  return completer.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () {
      if (!completer.isCompleted) completer.complete(null);
      return null;
    },
  );
}
