import 'dart:typed_data';

/// Non-web builds (tests): downloads are not supported.
void saveBytes(String fileName, Uint8List bytes, String mimeType) =>
    throw UnsupportedError('File downloads are only available on the web.');
