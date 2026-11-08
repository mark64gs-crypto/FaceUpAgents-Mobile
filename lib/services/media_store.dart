import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import 'ai_provider.dart';

class MediaStore {
  MediaStore({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  static const _folder = 'attachments';

  Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, _folder));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<ChatAttachment> importFile({
    required String sourcePath,
    required String name,
    required AttachmentKind kind,
    String? mimeType,
  }) async {
    final directory = await _directory();
    final resolvedMime =
        mimeType ??
        lookupMimeType(name) ??
        lookupMimeType(sourcePath) ??
        _fallbackMime(kind);
    final extension = _extensionFor(name, resolvedMime);
    final target = p.join(directory.path, _generatedName(kind, extension));
    await File(sourcePath).copy(target);
    return ChatAttachment(
      kind: kind,
      path: target,
      name: name,
      mimeType: resolvedMime,
    );
  }

  Future<ChatAttachment> importBytes({
    required Uint8List bytes,
    required String name,
    required AttachmentKind kind,
    String? mimeType,
  }) async {
    final directory = await _directory();
    final resolvedMime =
        mimeType ?? lookupMimeType(name) ?? _fallbackMime(kind);
    final extension = _extensionFor(name, resolvedMime);
    final target = p.join(directory.path, _generatedName(kind, extension));
    await File(target).writeAsBytes(bytes, flush: true);
    return ChatAttachment(
      kind: kind,
      path: target,
      name: name,
      mimeType: resolvedMime,
    );
  }

  Future<ChatAttachment> saveGenerated(
    GeneratedMedia media,
    AttachmentKind kind,
  ) async {
    final directory = await _directory();
    final extension = media.extension.isNotEmpty
        ? media.extension.replaceAll('.', '')
        : _extensionFor('', media.mimeType);
    final target = p.join(directory.path, _generatedName(kind, extension));
    await File(target).writeAsBytes(media.bytes, flush: true);
    final prefix = kind == AttachmentKind.video ? 'video' : 'image';
    return ChatAttachment(
      kind: kind,
      path: target,
      name: '$prefix.${extension.isEmpty ? 'bin' : extension}',
      mimeType: media.mimeType,
      generated: true,
    );
  }

  String _generatedName(AttachmentKind kind, String extension) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final suffix = _uuid.v4().substring(0, 8);
    final ext = extension.isEmpty ? '' : '.$extension';
    return '${kind.name}_${stamp}_$suffix$ext';
  }

  String _extensionFor(String name, String mimeType) {
    final extension = p.extension(name).replaceAll('.', '').toLowerCase();
    if (extension.isNotEmpty) return extension;
    return switch (mimeType.toLowerCase()) {
      'image/png' => 'png',
      'image/jpeg' || 'image/jpg' => 'jpg',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      'image/heic' => 'heic',
      'video/mp4' => 'mp4',
      'video/quicktime' => 'mov',
      'video/webm' => 'webm',
      'application/pdf' => 'pdf',
      'text/plain' => 'txt',
      'application/json' => 'json',
      _ => '',
    };
  }

  String _fallbackMime(AttachmentKind kind) => switch (kind) {
    AttachmentKind.image => 'image/jpeg',
    AttachmentKind.video => 'video/mp4',
    AttachmentKind.file => 'application/octet-stream',
  };
}
