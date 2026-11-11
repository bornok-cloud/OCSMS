export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart'
    if (dart.library.io) 'file_download_io.dart';
