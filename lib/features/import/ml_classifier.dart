import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

class MlClassifier {
  static OrtSession? _session;
  static List<String>? _labels;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      OrtEnv.instance.init();

      final modelData = await rootBundle.load('assets/model/classifier.onnx');
      final bytes = modelData.buffer.asUint8List();
      final opts = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes, opts);

      final labelsJson = await rootBundle.loadString('assets/model/labels.json');
      _labels = List<String>.from(jsonDecode(labelsJson));

      _loaded = true;
    } catch (_) {
      // Model not available yet — classifier.dart falls back to keywords
      _loaded = false;
    }
  }

  static bool get isAvailable => _loaded && _session != null && _labels != null;

  static String? predict(String description) {
    if (!isAvailable) return null;
    try {
      final input = OrtValueTensor.createTensorWithDataList(
        [description.toLowerCase()],
        [1, 1],
      );
      final runOptions = OrtRunOptions();
      final outputs = _session!.run(runOptions, {'input': input});

      // Output 0: shape [N] or [N,1] of predicted label strings
      final raw = outputs[0]?.value;
      String? label;
      if (raw is List && raw.isNotEmpty) {
        final first = raw[0];
        if (first is List && first.isNotEmpty) {
          // shape [N, 1]
          label = first[0]?.toString();
        } else {
          // shape [N] — first is already the full label string
          label = first?.toString();
        }
        // Guard against single-character extraction bug
        if (label != null && label.length == 1) label = null;
      }

      input.release();
      runOptions.release();
      for (final v in outputs) {
        v?.release();
      }

      return label;
    } catch (_) {
      return null;
    }
  }

  static void dispose() {
    _session?.release();
    _session = null;
    _labels = null;
    _loaded = false;
  }
}
