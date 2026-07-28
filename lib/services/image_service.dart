import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import 'github_service.dart';

class ImageService {
  static const _channel = MethodChannel('hexo/native');
  final GitHubService github;

  ImageService(this.github);

  Future<Uint8List?> pickImageBytes() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('pickImage');
      if (result is Uint8List) return result;
      if (result is List) return Uint8List.fromList(result.cast<int>());
      if (result is String && result.isNotEmpty) {
        // base64
        return base64Decode(result);
      }
      if (result is Map) {
        final b64 = result['base64']?.toString();
        if (b64 != null && b64.isNotEmpty) return base64Decode(b64);
        final path = result['path']?.toString();
        if (path != null && path.isNotEmpty) {
          return await File(path).readAsBytes();
        }
      }
    } catch (e) {
      // fallback: try open document via channel returning path only
      rethrow;
    }
    return null;
  }

  Future<Uint8List> compressIfNeeded(
    Uint8List bytes,
    AppSettings settings,
  ) async {
    if (!settings.autoCompressImage) return bytes;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: settings.compressMaxWidth > 0
            ? settings.compressMaxWidth
            : null,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return bytes;
      // PNG re-encode as size control; quality parameter is advisory for channel
      final out = bd.buffer.asUint8List();
      // If re-encode bigger (unlikely for large photos), keep original
      if (out.lengthInBytes >= bytes.lengthInBytes && bytes.lengthInBytes < 2 * 1024 * 1024) {
        return bytes;
      }
      // Prefer original JPEG when small enough
      if (bytes.lengthInBytes <= 400 * 1024) return bytes;
      return out;
    } catch (_) {
      return bytes;
    }
  }

  Future<String> uploadToImageBed(
    Uint8List bytes,
    AppSettings settings, {
    String? fileName,
  }) async {
    final name = fileName ??
        'img_${DateTime.now().millisecondsSinceEpoch}.png';
    final compressed = await compressIfNeeded(bytes, settings);

    final token = settings.imageBedToken.isNotEmpty
        ? settings.imageBedToken
        : settings.effectiveGithubToken;
    if (token.isEmpty) throw Exception('请先配置图床 Token 或默认 GitHub Token');

    final owner = settings.imageBedOwner.isNotEmpty
        ? settings.imageBedOwner
        : '';
    final repo = settings.imageBedRepo;
    if (owner.isEmpty || repo.isEmpty) {
      throw Exception('请在设置中配置图床仓库 owner/repo');
    }
    final path =
        '${settings.imageBedPath.replaceAll(RegExp(r'/+$'), '')}/$name'
            .replaceAll(RegExp(r'^/+'), '');
    final rawUrl = await github.uploadBinary(
      token: token,
      owner: owner,
      repo: repo,
      branch: settings.imageBedBranch,
      path: path,
      bytes: compressed,
      message: 'chore: upload $name',
    );
    if (settings.imageBedCdn.isNotEmpty) {
      final cdn = settings.imageBedCdn.replaceAll(RegExp(r'/+$'), '');
      return '$cdn/$path';
    }
    // jsDelivr fallback
    return 'https://cdn.jsdelivr.net/gh/$owner/$repo@${settings.imageBedBranch}/$path';
  }

  String markdownImage(String url, {String alt = 'image'}) => '![$alt]($url)';
}
