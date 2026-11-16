import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<bool> saveOrDownloadBytes(Uint8List bytes, String fileName) async {
  final result = await FilePicker.platform.saveFile(
    dialogTitle: 'Save Walk-In QR Code',
    fileName: fileName,
    bytes: bytes,
    type: FileType.image,
  );
  return result != null;
}
