import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as imglib;
import 'package:onnxruntime/onnxruntime.dart';

class LocalClassifierOnnx {
  static final LocalClassifierOnnx instance = LocalClassifierOnnx._();
  LocalClassifierOnnx._();

  late OrtSession _session;
  late List<String> _labels;
  bool _loaded = false;

  // must match your export
  final int _imgSize = 320;
  static const _mean = [0.485, 0.456, 0.406];
  static const _std  = [0.229, 0.224, 0.225];

  Future<void> load() async {
    if (_loaded) return;

    OrtEnv.instance.init();

    final opts = OrtSessionOptions()..appendXnnpackProvider();
    final modelBytes =
    (await rootBundle.load('assets/models/offline_ensemble_320.onnx'))
        .buffer
        .asUint8List();
    _session = await OrtSession.fromBuffer(modelBytes, opts);
    opts.release();

    final raw = await rootBundle.loadString('assets/labels.txt');
    _labels = raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    _loaded = true;
  }

  /// Center-crop -> resize -> NHWC float32 normalized
  Float32List _preprocess(Uint8List bytes) {
    final img = imglib.decodeImage(bytes)!;

    final sz = math.min(img.width, img.height);
    final crop = imglib.copyCrop(
      img,
      x: ((img.width - sz) / 2).floor(),
      y: ((img.height - sz) / 2).floor(),
      width: sz,
      height: sz,
    );
    final resized = imglib.copyResize(crop, width: _imgSize, height: _imgSize);

    final out = Float32List(_imgSize * _imgSize * 3);
    int i = 0;
    for (int y = 0; y < _imgSize; y++) {
      for (int x = 0; x < _imgSize; x++) {
        final px = resized.getPixel(x, y);

        int r8, g8, b8;
        if (px is imglib.Pixel) {
          r8 = px.r.toInt();
          g8 = px.g.toInt();
          b8 = px.b.toInt();
        } /*else if (px is int) {
          r8 = (px >> 16) & 0xFF;
          g8 = (px >> 8) & 0xFF;
          b8 = px & 0xFF;
        }*/ else {
          r8 = g8 = b8 = 0;
        }

        final r = r8 / 255.0, g = g8 / 255.0, b = b8 / 255.0;
        out[i++] = (r - _mean[0]) / _std[0];
        out[i++] = (g - _mean[1]) / _std[1];
        out[i++] = (b - _mean[2]) / _std[2];
      }
    }
    return out;
  }

  Map<String, dynamic> _postprocess(Float32List logits) {
    if (logits.isEmpty) {
      throw StateError('ONNX produced empty logits');
    }
    var maxv = double.negativeInfinity;
    for (final v in logits) { if (v > maxv) maxv = v; }
    final exps = Float32List(logits.length);
    double sum = 0;
    for (int i = 0; i < logits.length; i++) {
      final e = math.exp(logits[i] - maxv);
      exps[i] = e.toDouble();
      sum += e;
    }
    final probs = exps.map((e) => e / sum).toList();

    final idxs = List.generate(probs.length, (i) => i)
      ..sort((a, b) => probs[b].compareTo(probs[a]));
    final top1 = idxs.first;

    return {
      'label': _labels[top1],
      'confidence': probs[top1],
      'top5': idxs.take(5).map((i) => [_labels[i], probs[i]]).toList(),
    };
  }

  /// Flattens any nested output to 1-D Float32List (handles [N,C], [[...]], etc.)
  Float32List _flattenTo1D(dynamic v) {
    if (v is Float32List) return v;
    final out = <double>[];
    void walk(dynamic x) {
      if (x is Float32List) {
        out.addAll(x);
      } else if (x is List) {
        for (final y in x) { walk(y); }
      } else if (x is num) {
        out.add(x.toDouble());
      } else if (x == null) {
        // ignore
      } else {
        throw StateError('Unexpected ONNX output element: ${x.runtimeType}');
      }
    }
    walk(v);
    return Float32List.fromList(out);
  }

  Future<Map<String, dynamic>> predict(Uint8List imageBytes) async {
    if (!_loaded) await load();

    final inputNHWC = _preprocess(imageBytes);
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      inputNHWC,
      [1, _imgSize, _imgSize, 3], // NHWC
    );

    final runOpts = OrtRunOptions();
    final outputNames = _session.outputNames;

    final outputs =
    await _session.runAsync(runOpts, {'input': inputTensor}, outputNames);

    inputTensor.release();
    runOpts.release();

    final first = (outputs != null && outputs.isNotEmpty) ? outputs.first : null;
    final val = first?.value;

    // Release outputs to avoid leaks
    outputs?.forEach((o) => o?.release());

    if (val == null) {
      throw StateError('ONNX returned null output');
    }

    final logits1d = _flattenTo1D(val);
    return _postprocess(logits1d);
  }

  void dispose() {
    if (_loaded) {
      _session.release();
      _loaded = false;
    }
  }
}