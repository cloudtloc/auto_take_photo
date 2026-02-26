import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/selfie_camera_screen.dart';

// #region agent log
void _agentDebugLog({
  required String runId,
  required String hypothesisId,
  required String location,
  required String message,
  required Map<String, dynamic> data,
}) {
  final log = {
    'sessionId': '3c4b30',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  try {
    final file = File('debug-3c4b30.log');
    file.writeAsStringSync(
      '${jsonEncode(log)}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}
// #endregion agent log

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
      // #region agent log
      _agentDebugLog(
        runId: 'initial',
        hypothesisId: 'H1',
        location: 'main.dart:_requestPermissions:before',
        message: 'Requesting camera/location permissions',
        data: {
          'platform': Platform.operatingSystem,
        },
      );
      // #endregion agent log

      final statuses = await [
        Permission.camera,
        Permission.locationWhenInUse,
      ].request();

      final cam = statuses[Permission.camera];
      final loc = statuses[Permission.locationWhenInUse];

      // #region agent log
      _agentDebugLog(
        runId: 'initial',
        hypothesisId: 'H1',
        location: 'main.dart:_requestPermissions:after',
        message: 'Permissions request result',
        data: {
          'camera': cam?.toString(),
          'location': loc?.toString(),
        },
      );
      // #endregion agent log

      if (mounted) {
        setState(() {
          _checked = true;
          _cameraGranted = cam?.isGranted ?? false;
          _locationGranted = loc?.isGranted ?? false;
        });
      }
    } catch (e) {
      // #region agent log
      _agentDebugLog(
        runId: 'initial',
        hypothesisId: 'H2',
        location: 'main.dart:_requestPermissions:error',
        message: 'Error when requesting permissions',
        data: {
          'error': e.toString(),
        },
      );
      // #endregion agent log

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
