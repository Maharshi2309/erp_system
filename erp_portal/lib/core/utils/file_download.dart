import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart'
    as platform;

/// Gives the person a file to save (templates, error reports, exports).
abstract interface class FileDownloads {
  void save(String fileName, Uint8List bytes, {required String mimeType});
}

class BrowserFileDownloads implements FileDownloads {
  const BrowserFileDownloads();

  @override
  void save(String fileName, Uint8List bytes, {required String mimeType}) =>
      platform.saveBytes(fileName, bytes, mimeType);
}

final fileDownloadsProvider = Provider<FileDownloads>(
  (ref) => const BrowserFileDownloads(),
);

const xlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const csvMimeType = 'text/csv';
