// lib/screens/offline_classifier_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/local_classifier_onnx.dart';
import '../widgets/appbars.dart';
import '../widgets/drawer_menu.dart';

class OfflineClassifierScreen extends StatefulWidget {
  const OfflineClassifierScreen({super.key});
  @override
  State<OfflineClassifierScreen> createState() => _OfflineClassifierScreenState();
}

class _OfflineClassifierScreenState extends State<OfflineClassifierScreen> {
  final _picker = ImagePicker();
  Uint8List? _bytes;
  XFile? _file;
  String? _err;
  Map<String, dynamic>? _resp;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  Future<void> _preload() async {
    // ONNX runtime isn’t available on Flutter web; fail fast with a friendly note.
    if (kIsWeb) {
      setState(() => _err = 'Offline ONNX inference isn’t supported on web.');
      return;
    }
    try {
      await LocalClassifierOnnx.instance.load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = 'Model load failed: $e');
    }
  }

  Future<void> _pick(bool camera) async {
    setState(() {
      _err = null;
      _resp = null;
    });
    final x = camera
        ? await _picker.pickImage(source: ImageSource.camera, imageQuality: 92)
        : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (x == null) return;
    final b = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _file = x;
      _bytes = b;
    });
  }

  Future<void> _predict() async {
    if (_bytes == null) return;
    setState(() {
      _loading = true;
      _err = null;
      _resp = null;
    });
    try {
      final res = await LocalClassifierOnnx.instance.predict(_bytes!);
      if (!mounted) return;
      setState(() => _resp = res);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final imgWidget = _file == null
        ? Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: Text('No image selected')),
    )
        : ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: kIsWeb
          ? Image.memory(_bytes!, height: 200, width: double.infinity, fit: BoxFit.cover)
          : Image.file(File(_file!.path),
          height: 200, width: double.infinity, fit: BoxFit.cover),
    );

    return Scaffold(
      appBar: topLevelAppBar('Offline Classifier'),
      drawer: const DrawerMenu(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          imgWidget,
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => _pick(false),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pick(true),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
              FilledButton.tonal(
                onPressed: (_bytes != null && !_loading && !kIsWeb) ? _predict : null,
                child: _loading
                    ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Predict (offline)'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_err != null) Text(_err!, style: const TextStyle(color: Colors.red)),
          if (_resp != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Prediction: ${_resp!['label']}  (${((_resp!['confidence'] as num) * 100).toStringAsFixed(1)}%)",
                      style: Theme.of(c).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text('Top-5:'),
                    ...((_resp!['top5'] as List).map((e) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e[0].toString()),
                        Text('${((e[1] as num) * 100).toStringAsFixed(1)}%'),
                      ],
                    ))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}