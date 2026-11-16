import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

Future<bool> saveOrDownloadBytes(Uint8List bytes, String fileName) async {
  final blob = web.Blob([bytes.buffer.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..style.display = 'none'
    ..download = fileName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  web.document.body?.removeChild(anchor);
  web.URL.revokeObjectURL(url);
  return true;
}
