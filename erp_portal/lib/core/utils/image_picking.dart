import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PickedImage {
  const PickedImage({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Lets the user choose an image file. An interface so tests can fake it.
abstract interface class ImagePicking {
  /// Null when the user cancels.
  Future<PickedImage?> pickImage();
}

class FilePickerImagePicking implements ImagePicking {
  const FilePickerImagePicking();

  @override
  Future<PickedImage?> pickImage() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
    );
    if (file == null) return null;
    return PickedImage(name: file.name, bytes: await file.xFile.readAsBytes());
  }
}

final imagePickingProvider = Provider<ImagePicking>(
  (ref) => const FilePickerImagePicking(),
);

/// Lets the user choose a spreadsheet for import. Any file can be chosen so
/// a wrong type gets a clear message instead of being hidden (board S46).
abstract interface class SpreadsheetPicking {
  /// Null when the user cancels.
  Future<PickedImage?> pickSpreadsheet();
}

class FilePickerSpreadsheetPicking implements SpreadsheetPicking {
  const FilePickerSpreadsheetPicking();

  @override
  Future<PickedImage?> pickSpreadsheet() async {
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    return PickedImage(name: file.name, bytes: await file.xFile.readAsBytes());
  }
}

final spreadsheetPickingProvider = Provider<SpreadsheetPicking>(
  (ref) => const FilePickerSpreadsheetPicking(),
);

const maxImageBytes = 2 * 1024 * 1024;

/// Error text for an unusable image (boards S13, S14), or null when fine.
/// Checks the file's first bytes, not just its name.
///
/// SVG is not accepted yet: the app has no SVG renderer (see Phase 3 report).
String? validateImage(PickedImage image) {
  final b = image.bytes;
  final isPng =
      b.length > 4 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47;
  final isJpeg = b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
  if (!isPng && !isJpeg) return 'That file isn’t an image. Use PNG or JPG.';
  if (b.length > maxImageBytes) {
    return 'That image is over 2 MB. Choose a smaller one.';
  }
  return null;
}
