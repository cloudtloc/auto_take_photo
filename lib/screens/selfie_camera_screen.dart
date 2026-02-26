import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/place_name_service.dart';
import '../utils/camera_input_image.dart';
import 'captured_photos_screen.dart';

class SelfieCameraScreen extends StatefulWidget {
  const SelfieCameraScreen({super.key});

  @override
  State<SelfieCameraScreen> createState() => _SelfieCameraScreenState();
}

class _SelfieCameraScreenState extends State<SelfieCameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = -1;
  FaceDetector? _faceDetector;
  bool _isProcessing = false;
  bool _isStreaming = false;
  bool _isDialogOpen = false;
  List<Face> _faces = [];
  DateTime? _faceDetectedAt;
  static const _delayBeforeCapture = Duration(milliseconds: 1500);
  bool _isCapturing = false;
  String? _lastCapturedPath;
  String? _errorMessage;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDetector();
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStream();
    _faceDetector?.close();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // App vao background: giai phong camera de tranh loi va tiet kiem tai nguyen.
      _stopStream();
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      // App tro lai foreground: khoi dong lai camera.
      _initCamera();
    }
  }

  void _initDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableContours: false,
        enableLandmarks: false,
        enableTracking: false,
        minFaceSize: 0.15,
      ),
    );
  }

  String _twoDigits(int n) => n >= 10 ? '$n' : '0$n';

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString();
    final m = _twoDigits(dt.month);
    final d = _twoDigits(dt.day);
    final h = _twoDigits(dt.hour);
    final mi = _twoDigits(dt.minute);
    final s = _twoDigits(dt.second);
    return '$y-$m-$d $h:$mi:$s';
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) {
      try {
        _cameras = await availableCameras();
      } catch (e) {
        setState(() => _errorMessage = 'Không lấy được danh sách camera: $e');
        return;
      }
    }
    for (var i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == CameraLensDirection.front) {
        _cameraIndex = i;
        break;
      }
    }
    if (_cameraIndex == -1) _cameraIndex = 0;
    await _startCamera();
  }

  Future<void> _startCamera() async {
    final camera = _cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _errorMessage = null);
      _startStream();
      setState(() {});
    } on CameraException catch (e) {
      setState(() => _errorMessage = 'Lỗi máy ảnh: ${e.description}');
    }
  }

  Future<void> _startStream() async {
    if (_controller == null || !_controller!.value.isInitialized || _isStreaming) return;
    await _controller!.startImageStream(_processCameraImage);
    setState(() => _isStreaming = true);
  }

  Future<void> _stopStream() async {
    if (_controller == null || !_isStreaming) return;
    try {
      await _controller!.stopImageStream();
    } catch (_) {}
    setState(() => _isStreaming = false);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessing ||
        _isCapturing ||
        _isDialogOpen ||
        _controller == null ||
        _faceDetector == null) {
      return;
    }
    final inputImage = CameraInputImage.fromCameraImage(
      image: image,
      controller: _controller!,
      camera: _cameras[_cameraIndex],
      onRotation: (r) => _rotation = r,
    );
    if (inputImage == null) return;
    _isProcessing = true;
    try {
      final faces = await _faceDetector!.processImage(inputImage);
      if (!mounted) return;
      setState(() {
        _faces = faces;
        _updateAutoCapture(faces);
      });
    } catch (_) {
      // bo qua frame loi
    } finally {
      _isProcessing = false;
    }
  }

  void _updateAutoCapture(List<Face> faces) {
    if (_isCapturing) return;
    if (faces.length == 1) {
      final face = faces.first;
      final rotY = face.headEulerAngleY?.abs() ?? 0;
      final rotZ = face.headEulerAngleZ?.abs() ?? 0;
      if (rotY < 15 && rotZ < 15) {
        final now = DateTime.now();
        if (_faceDetectedAt == null) {
          _faceDetectedAt = now;
        } else if (now.difference(_faceDetectedAt!) >= _delayBeforeCapture) {
          _triggerCapture();
          _faceDetectedAt = null;
        }
      } else {
        _faceDetectedAt = null;
      }
    } else {
      _faceDetectedAt = null;
    }
  }

  Future<void> _triggerCapture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;

    // Bắt buộc phải có vị trí trước khi chụp.
    final Position? pos = await _requireLocation();
    if (pos == null) {
      return;
    }

    _isCapturing = true;
    await _stopStream();
    try {
      final XFile file = await _controller!.takePicture();
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final name = 'selfie_${now.millisecondsSinceEpoch}.jpg';
      final path = p.join(dir.path, name);

      final String timeLabel = _formatDateTime(now);
      final String locationLabel =
          'Lat ${pos.latitude.toStringAsFixed(5)}, Lon ${pos.longitude.toStringAsFixed(5)}';
      final String? placeName = await PlaceNameService.getPlaceName(
        pos.latitude,
        pos.longitude,
      );
      final String placeLine = (placeName != null && placeName.isNotEmpty)
          ? placeName.replaceAll('\n', ' ').length > 60
              ? '${placeName.replaceAll('\n', ' ').substring(0, 60)}...'
              : placeName.replaceAll('\n', ' ')
          : '';
      final overlayText = placeLine.isEmpty
          ? '$timeLabel\n$locationLabel'
          : '$timeLabel\n$placeLine\n$locationLabel';

      try {
        final bytes = await File(file.path).readAsBytes();
        final img.Image? original = img.decodeImage(bytes);
        if (original != null) {
          final textColor = img.ColorRgba8(255, 255, 255, 255);
          const padding = 16;
          final numLines = overlayText.split('\n').length;
          final lineHeight = 18;
          int y = original.height - (lineHeight * numLines + 12);
          if (y < 8) y = 8;
          img.drawString(
            original,
            overlayText,
            font: img.arial14,
            x: padding,
            y: y,
            color: textColor,
          );
          final encoded = img.encodeJpg(original, quality: 90);
          await File(path).writeAsBytes(encoded);
        } else {
          await File(file.path).copy(path);
        }
      } catch (_) {
        await File(file.path).copy(path);
      }

      try {
        await File(file.path).delete();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _lastCapturedPath = path;
          _isCapturing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã chụp xong: $name')),
        );
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CapturedPhotosScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCapturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chụp ảnh: $e')),
        );
      }
    }
    if (mounted) await _startStream();
  }

  Future<Position?> _requireLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return null;
        setState(() => _isDialogOpen = true);
        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Bật vị trí'),
              content: const Text(
                'Vui lòng bật GPS (dịch vụ vị trí) để ứng dụng có thể gắn tọa độ lên ảnh.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Đóng'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await Geolocator.openLocationSettings();
                  },
                  child: const Text('Mở cài đặt vị trí'),
                ),
              ],
            );
          },
        );
        if (mounted) {
          setState(() => _isDialogOpen = false);
        }
        return null;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        if (!mounted) return null;
        setState(() => _isDialogOpen = true);
        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Cấp quyền vị trí'),
              content: const Text(
                'Ứng dụng cần quyền vị trí để gắn tọa độ lên ảnh. '
                'Vui lòng cấp quyền vị trí trong phần cài đặt ứng dụng.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Đóng'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await Geolocator.openAppSettings();
                  },
                  child: const Text('Mở cài đặt ứng dụng'),
                ),
              ],
            );
          },
        );
        if (mounted) {
          setState(() => _isDialogOpen = false);
        }
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 5),
      );
      return pos;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không lấy được vị trí: $e')),
        );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _errorMessage != null
            ? _buildError()
            : _controller == null || !_controller!.value.isInitialized
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _buildCamera(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() => _errorMessage = null);
                _initCamera();
              },
              child: const Text('Tải lại', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCamera() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: CameraPreview(_controller!),
        ),
        if (_faces.isNotEmpty) _buildFaceOverlay(),
        Positioned(
          top: 16,
          right: 16,
          child: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.black54,
            ),
            onPressed: () async {
              await _stopStream();
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CapturedPhotosScreen(),
                ),
              );
              if (mounted) {
                await _startStream();
              }
            },
            child: const Text(
              'Xem ảnh',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Text(
            _isCapturing
                ? 'Đang chụp...'
                : _faces.isEmpty
                    ? 'Đưa mặt vào sẽ tự động chụp'
                    : _faces.length == 1
                        ? 'Giữ mặt ổn định...'
                        : '1 khuôn mặt mới chụp',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              shadows: [Shadow(blurRadius: 4, color: Colors.black)],
            ),
          ),
        ),
        if (_isCapturing)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: const Text(
                'Đang chụp, vui lòng giữ nguyên...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (_lastCapturedPath != null)
          Positioned(
            bottom: 24,
            left: 24,
            child: Text(
              'Ảnh đã lưu tại: $_lastCapturedPath',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _buildFaceOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          painter: FaceOverlayPainter(
            faces: _faces,
            imageSize: Size(
              _controller!.value.previewSize?.width ?? 0,
              _controller!.value.previewSize?.height ?? 0,
            ),
            cameraLensDirection: _cameras[_cameraIndex].lensDirection,
            rotation: _rotation,
          ),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
      },
    );
  }
}

class FaceOverlayPainter extends CustomPainter {
  FaceOverlayPainter({
    required this.faces,
    required this.imageSize,
    required this.cameraLensDirection,
    required this.rotation,
  });

  final List<Face> faces;
  final Size imageSize;
  final CameraLensDirection cameraLensDirection;
  final InputImageRotation rotation;

  @override
  void paint(Canvas canvas, Size size) {
    for (final face in faces) {
      final rect = Rect.fromLTRB(
        _translateX(face.boundingBox.left, size, imageSize),
        _translateY(face.boundingBox.top, size, imageSize),
        _translateX(face.boundingBox.right, size, imageSize),
        _translateY(face.boundingBox.bottom, size, imageSize),
      );
      final paint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(rect, paint);
    }
  }

  double _translateX(double x, Size canvasSize, Size imageSize) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return x *
            canvasSize.width /
            (Platform.isIOS ? imageSize.width : imageSize.height);
      case InputImageRotation.rotation270deg:
        return canvasSize.width -
            x *
                canvasSize.width /
                (Platform.isIOS ? imageSize.width : imageSize.height);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        switch (cameraLensDirection) {
          case CameraLensDirection.back:
            return x * canvasSize.width / imageSize.width;
          default:
            return canvasSize.width - x * canvasSize.width / imageSize.width;
        }
    }
  }

  double _translateY(double y, Size canvasSize, Size imageSize) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y *
            canvasSize.height /
            (Platform.isIOS ? imageSize.height : imageSize.width);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * canvasSize.height / imageSize.height;
    }
  }

  @override
  bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) {
    return oldDelegate.faces != faces;
  }
}
