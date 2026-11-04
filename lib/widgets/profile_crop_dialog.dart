import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../theme/app_theme.dart';
import '../services/app_data.dart';
import 'shared_widgets.dart';

class ProfileCropDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final String userId;

  const ProfileCropDialog({
    super.key,
    required this.imageBytes,
    required this.userId,
  });

  @override
  State<ProfileCropDialog> createState() => _ProfileCropDialogState();
}

class _ProfileCropDialogState extends State<ProfileCropDialog> {
  double _zoom = 1.0;
  double _posX = 0.5; // 0.0 (left) to 1.0 (right)
  double _posY = 0.5; // 0.0 (top) to 1.0 (bottom)
  bool _saving = false;
  int? _imageWidth;
  int? _imageHeight;

  @override
  void initState() {
    super.initState();
    final decoded = img.decodeImage(widget.imageBytes);
    _imageWidth = decoded?.width;
    _imageHeight = decoded?.height;
  }

  Widget _cropPreview() {
    final width = _imageWidth;
    final height = _imageHeight;
    if (width == null || height == null) {
      return Image.memory(widget.imageBytes, fit: BoxFit.cover);
    }

    final minDimension = width < height ? width : height;
    final cropSize = minDimension / _zoom;
    final scale = 150 / cropSize;
    final previewWidth = width * scale;
    final previewHeight = height * scale;
    final left = -(width - cropSize) * _posX * scale;
    final top = -(height - cropSize) * _posY * scale;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          left: left,
          top: top,
          width: previewWidth,
          height: previewHeight,
          child: Image.memory(
            widget.imageBytes,
            width: previewWidth,
            height: previewHeight,
            fit: BoxFit.fill,
          ),
        ),
      ],
    );
  }

  Future<Uint8List> _processCrop(
    Uint8List inputBytes,
    double zoom,
    double posX,
    double posY,
  ) async {
    return await compute((Map<String, dynamic> params) {
      final bytes = params['bytes'] as Uint8List;
      final z = params['zoom'] as double;
      final px = params['posX'] as double;
      final py = params['posY'] as double;

      final original = img.decodeImage(bytes);
      if (original == null) return bytes;

      final w = original.width;
      final h = original.height;
      final minDim = w < h ? w : h;

      final cropSize = (minDim / z).round().clamp(1, minDim);
      final maxX = w - cropSize;
      final maxY = h - cropSize;

      final x = maxX > 0 ? (maxX * px).round().clamp(0, maxX) : 0;
      final y = maxY > 0 ? (maxY * py).round().clamp(0, maxY) : 0;

      final cropped = img.copyCrop(
        original,
        x: x,
        y: y,
        width: cropSize,
        height: cropSize,
      );
      final resized = img.copyResize(cropped, width: 400, height: 400);
      final encoded = img.encodeJpg(resized, quality: 85);
      return Uint8List.fromList(encoded);
    }, {'bytes': inputBytes, 'zoom': _zoom, 'posX': _posX, 'posY': _posY});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: const Text('Crop Profile Picture'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width * 0.84,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Adjust zoom and position to crop your profile picture:',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Center(
                child: ClipOval(
                  child: Container(
                    height: 150,
                    width: 150,
                    color: Colors.black12,
                    child: _cropPreview(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text(
                    'Zoom',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Slider(
                      value: _zoom,
                      min: 1.0,
                      max: 3.0,
                      divisions: 20,
                      onChanged: (v) => setState(() => _zoom = v),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text(
                    'Horizontal',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Slider(
                      value: _posX,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) => setState(() => _posX = v),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text(
                    'Vertical',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Slider(
                      value: _posY,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) => setState(() => _posY = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    final finalBytes = await _processCrop(
                      widget.imageBytes,
                      _zoom,
                      _posX,
                      _posY,
                    );
                    final base64Image = base64Encode(finalBytes);
                    await AppData.instance.updateProfileImage(
                      widget.userId,
                      base64Image,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    setState(() => _saving = false);
                    showAppSnack(context, 'Failed to save profile picture: $e');
                  }
                },
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm & Save'),
        ),
      ],
    );
  }
}
