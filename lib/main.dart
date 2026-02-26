import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/selfie_camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tu Chup Anh',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const PermissionWrapper(),
    );
  }
}

class PermissionWrapper extends StatefulWidget {
  const PermissionWrapper({super.key});

  @override
  State<PermissionWrapper> createState() => _PermissionWrapperState();
}

class _PermissionWrapperState extends State<PermissionWrapper> {
  bool _checked = false;
  bool _cameraGranted = false;
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    try {
      final statuses = await [
        Permission.camera,
        Permission.locationWhenInUse,
      ].request();

      final cam = statuses[Permission.camera];
      final loc = statuses[Permission.locationWhenInUse];

      if (mounted) {
        setState(() {
          _checked = true;
          _cameraGranted = cam?.isGranted ?? false;
          _locationGranted = loc?.isGranted ?? false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checked = true;
          _cameraGranted = false;
          _locationGranted = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_cameraGranted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quyen truy cap')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Ứng dụng cần quyền camera để tự động chụp ảnh. Vui lòng bật quyền trong Cài đặt.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nếu từ chối quyền vị trí, ảnh vẫn được chụp nhưng sẽ không gắn tọa độ lên ảnh.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => openAppSettings(),
                  child: const Text('Mở Cài đặt'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const SelfieCameraScreen();
  }
}
