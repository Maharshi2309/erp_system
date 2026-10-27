import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/app_overlays.dart';
import 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart'
    as platform;

/// Gives the person a file to save (templates, error reports, exports).
abstract interface class FileDownloads {
  /// True once the file is saved; false when the person cancels the save
  /// dialog. Throws when the file can't be written.
  Future<bool> save(
    String fileName,
    Uint8List bytes, {
    required String mimeType,
  });
}

/// Web: the browser's download. Apps (macOS, iOS, Android, Windows):
/// the system "Save" dialog, which writes the file (D-80).
class PlatformFileDownloads implements FileDownloads {
  const PlatformFileDownloads();

  @override
  Future<bool> save(
    String fileName,
    Uint8List bytes, {
    required String mimeType,
  }) async {
    if (kIsWeb) {
      platform.saveBytes(fileName, bytes, mimeType);
      return true;
    }
    final dot = fileName.lastIndexOf('.');
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: 'Save $fileName',
      type: dot < 0 ? FileType.any : FileType.custom,
      allowedExtensions: dot < 0 ? null : [fileName.substring(dot + 1)],
    );
    return uri != null;
  }
}

final fileDownloadsProvider = Provider<FileDownloads>(
  (ref) => const PlatformFileDownloads(),
);

/// Saves a file and tells the person what happened: [done] (or "Saved
/// file name") when saved, nothing when they cancel, and a plain error when
/// it can't be written. Returns whether it was saved.
Future<bool> downloadFile(
  BuildContext context,
  WidgetRef ref,
  String fileName,
  Uint8List bytes, {
  required String mimeType,
  String? done,
}) async {
  try {
    final saved = await ref
        .read(fileDownloadsProvider)
        .save(fileName, bytes, mimeType: mimeType);
    if (saved && context.mounted) {
      showAppToast(context, done ?? 'Saved $fileName');
    }
    return saved;
  } on Object catch (e) {
    debugPrint('Saving $fileName failed: $e');
    if (context.mounted) {
      showAppToast(
        context,
        'Couldn’t save $fileName. Check that the app may save files and try again.',
        icon: Icons.error_outline,
      );
    }
    return false;
  }
}

/// For a button handler that doesn't wait for the result.
void startDownload(
  BuildContext context,
  WidgetRef ref,
  String fileName,
  Uint8List bytes, {
  required String mimeType,
  String? done,
}) => unawaited(
  downloadFile(context, ref, fileName, bytes, mimeType: mimeType, done: done),
);

const xlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const csvMimeType = 'text/csv';
