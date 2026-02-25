import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CapturedPhotosScreen extends StatefulWidget {
  const CapturedPhotosScreen({super.key});

  @override
  State<CapturedPhotosScreen> createState() => _CapturedPhotosScreenState();
}

class _CapturedPhotosScreenState extends State<CapturedPhotosScreen> {
  bool _loading = true;
  List<File> _photos = [];

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    setState(() {
      _loading = true;
    });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final directory = Directory(dir.path);
      final files = await directory
          .list()
          .where((entity) =>
              entity is File &&
              p.basename(entity.path).startsWith('selfie_') &&
              p.extension(entity.path).toLowerCase() == '.jpg')
          .cast<File>()
          .toList();

      files.sort((a, b) {
        final at = a.lastModifiedSync();
        final bt = b.lastModifiedSync();
        return bt.compareTo(at);
      });

      if (!mounted) return;
      setState(() {
        _photos = files;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _photos = [];
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ảnh đã chụp'),
        actions: [
          TextButton(
            onPressed: _loadPhotos,
            child: const Text(
              'Làm mới',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_photos.isEmpty) {
      return const Center(
        child: Text('Chưa có ảnh nào được chụp.'),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final file = _photos[index];
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PhotoViewerScreen(imageFile: file),
              ),
            );
          },
          child: Hero(
            tag: file.path,
            child: Image.file(
              file,
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}

class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.imageFile});

  final File imageFile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xem ảnh'),
      ),
      body: Center(
        child: Hero(
          tag: imageFile.path,
          child: InteractiveViewer(
            child: Image.file(imageFile),
          ),
        ),
      ),
    );
  }
}

