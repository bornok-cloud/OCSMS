import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';

class GcashSettingsScreen extends StatefulWidget {
  const GcashSettingsScreen({super.key});

  @override
  State<GcashSettingsScreen> createState() => _GcashSettingsScreenState();
}

class _GcashSettingsScreenState extends State<GcashSettingsScreen> {
  String? _qrBase64;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qrBase64 = AppData.instance.gcashQrBase64;
  }

  Future<void> _pickQrImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;

      setState(() {
        _qrBase64 = base64Encode(file.bytes!);
      });
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Failed to pick QR image: $e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppData.instance.updateGcashSettings(
        qrBase64: _qrBase64,
      );
      if (!mounted) return;
      showAppSnack(context, 'GCash QR code updated successfully.');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Failed to update GCash QR code: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionPage(
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code_2, color: AppColors.accent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'GCash Payment Settings',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.brown,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Upload and manage the GCash QR code image displayed to customers during checkout.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const Divider(height: 32),
                const Text(
                  'GCash QR Code Image',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.brown),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Upload the QR code image for scanning during payment.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: [
                      InkWell(
                        onTap: (_qrBase64 != null && _qrBase64!.isNotEmpty)
                            ? () => showEnlargedQrDialog(context, _qrBase64!)
                            : _pickQrImage,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 200,
                          width: 200,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.4)),
                            borderRadius: BorderRadius.circular(12),
                            color: AppColors.beige.withValues(alpha: 0.5),
                          ),
                          child: _qrBase64 == null || _qrBase64!.isEmpty
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.qr_code_scanner, size: 48, color: AppColors.textMuted),
                                    SizedBox(height: 8),
                                    Text('No QR Code Uploaded', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                  ],
                                )
                              : Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(11),
                                      child: Image.memory(
                                        base64Decode(_qrBase64!),
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      right: 6,
                                      bottom: 6,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.zoom_in, color: Colors.white, size: 18),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickQrImage,
                            icon: const Icon(Icons.upload_file),
                            label: Text(_qrBase64 == null ? 'Upload QR Code' : 'Change QR Code'),
                          ),
                          if (_qrBase64 != null)
                            OutlinedButton.icon(
                              onPressed: () => setState(() => _qrBase64 = null),
                              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                              label: const Text('Remove', style: TextStyle(color: AppColors.danger)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save GCash Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
