import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/place_name_service.dart';
import '../utils/camera_input_image.dart';
import '../utils/overlay_text_on_image.dart';
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
  DateTime? _lastCaptureTime;
  static const _cooldownAfterCapture = Duration(seconds: 3);
  String _loadingStep = 'Đang chuẩn bị...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _doInit());
  }

  Future<void> _yieldToUi() async {
    await Future.delayed(const Duration(milliseconds: 80));
  }

  Future<void> _doInit() async {
    if (!mounted) return;
    setState(() => _loadingStep = 'Đang kiểm tra quyền...');
    await _yieldToUi();
    if (!mounted) return;
    final cameraStatus = await Permission.camera.status;
    if (!cameraStatus.isGranted) {
      if (mounted) {
        setState(() {
          _loadingStep = '';
          _errorMessage =
              'Chưa cấp quyền camera. Vui lòng bật quyền trong Cài đặt.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _loadingStep = 'Đang tải mô hình nhận diện...');
    await _yieldToUi();
    if (!mounted) return;
    try {
      _initDetector();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingStep = '';
          _errorMessage = 'Khởi tạo thất bại: $e';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _loadingStep = 'Đang khởi tạo camera...');
    await _yieldToUi();
    if (!mounted) return;
    await _initCamera();
    if (mounted) setState(() => _loadingStep = '');
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
    if (mounted && _loadingStep.isEmpty) {
      setState(() => _loadingStep = 'Đang khởi tạo camera...');
    }
    if (_cameras.isEmpty) {
      if (mounted) setState(() => _loadingStep = 'Đang lấy danh sách camera...');
      await _yieldToUi();
      if (!mounted) return;
      try {
        _cameras = await availableCameras();
      } catch (e) {
        if (mounted) {
          setState(() {
            _loadingStep = '';
            _errorMessage = 'Không lấy được danh sách camera: $e';
          });
        }
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
    if (mounted) setState(() => _loadingStep = 'Đang mở camera...');
    await _yieldToUi();
    if (!mounted) return;
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _errorMessage = null;
        _loadingStep = '';
      });
      _startStream();
      setState(() {});
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _loadingStep = '';
          _errorMessage = 'Lỗi máy ảnh: ${e.description}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingStep = '';
          _errorMessage = 'Lỗi: $e';
        });
      }
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
    if (_lastCaptureTime != null &&
        DateTime.now().difference(_lastCaptureTime!) < _cooldownAfterCapture) {
      return;
    }
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
    _isCapturing = true;

    final Position? pos = await _requireLocation();
    if (pos == null) {
      if (mounted) setState(() => _isCapturing = false);
      return;
    }

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
        final ok = await overlayTextOnImage(
          imageBytes: bytes,
          outputPath: path,
          overlayText: overlayText,
        );
        if (!ok) {
          await File(file.path).copy(path);
        }
      } catch (_) {
        await File(file.path).copy(path);
      }

      try {
        await File(file.path).delete();
      } catch (_) {}

      if (mounted) {
        _lastCaptureTime = DateTime.now();
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
                ? _buildLoading()
                : _buildCamera(),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _loadingStep.isNotEmpty ? _loadingStep : 'Đang tải...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
                setState(() {
                  _errorMessage = null;
                  _loadingStep = 'Đang khởi tạo camera...';
                });
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
