import 'dart:typed_data';

/// Apps use the system save dialog instead (see file_download.dart); this
/// browser-only path is never reached outside the web.
void saveBytes(String fileName, Uint8List bytes, String mimeType) =>
    throw UnsupportedError('Browser downloads only exist on the web.');
