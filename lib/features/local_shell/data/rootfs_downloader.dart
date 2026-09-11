import 'dart:io';

import 'package:conduit/features/local_shell/domain/rootfs_manifest.dart';
import 'package:http/http.dart' as http;

enum DownloadFailureKind { network, lowDisk, corrupt, unknown }

class DownloadException implements Exception {
  const DownloadException(this.kind, this.message);

  final DownloadFailureKind kind;
  final String message;

  @override
  String toString() => 'DownloadException($kind, $message)';
}

abstract interface class RootfsDownloader {
  Future<void> download({
    RootfsManifest? manifest,
    Uri? sourceUrl,
    String? sourceFilePath,
    required String destination,
    void Function(double progress)? onProgress,
  });
}

class HttpRootfsDownloader implements RootfsDownloader {
  HttpRootfsDownloader([http.Client? client])
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<void> download({
    RootfsManifest? manifest,
    Uri? sourceUrl,
    String? sourceFilePath,
    required String destination,
    void Function(double progress)? onProgress,
  }) async {
    final file = File(destination);
    await file.parent.create(recursive: true);

    // Bypass for local file import
    if (sourceFilePath != null && sourceFilePath.isNotEmpty) {
      final source = File(sourceFilePath);
      if (!await source.exists()) {
        throw DownloadException(
          DownloadFailureKind.unknown,
          'Local rootfs archive not found: $sourceFilePath',
        );
      }
      final total = await source.length();
      var copied = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in source.openRead()) {
          sink.add(chunk);
          copied += chunk.length;
          if (total > 0) {
            onProgress?.call((copied / total).clamp(0.0, 1.0));
          }
        }
        await sink.flush();
        await sink.close();
      } catch (error) {
        await sink.close().catchError((_) {});
        throw DownloadException(
          DownloadFailureKind.unknown,
          'Failed to copy local archive: $error',
        );
      }
      onProgress?.call(1);
      return;
    }

    final effectiveUrl = sourceUrl ?? manifest?.archiveUrl;
    if (effectiveUrl == null) {
      throw const DownloadException(
        DownloadFailureKind.unknown,
        'No source URL or manifest provided for download.',
      );
    }

    final total = manifest?.downloadSizeBytes ?? 0;
    var existing = await file.exists() ? await file.length() : 0;
    if (total > 0 && existing > total) {
      await file.delete();
      existing = 0;
    }

    final hasChecksum = manifest != null && manifest.sha256.isNotEmpty;
    final verifier = hasChecksum ? Sha256Verifier(manifest.sha256) : null;
    final alreadyComplete = verifier != null && total > 0 && existing == total;
    if (alreadyComplete) {
      await _hashFile(file, verifier);
    } else {
      await _fetch(
        url: effectiveUrl,
        file: file,
        existing: existing,
        total: total,
        verifier: verifier,
        onProgress: onProgress,
      );
    }

    if (verifier != null && !verifier.verify()) {
      await file.delete().catchError((_) => file);
      throw const DownloadException(
        DownloadFailureKind.corrupt,
        'Downloaded archive failed checksum verification.',
      );
    }
    onProgress?.call(1);
  }

  Future<void> _fetch({
    required Uri url,
    required File file,
    required int existing,
    required int total,
    required Sha256Verifier? verifier,
    required void Function(double)? onProgress,
  }) async {
    final request = http.Request('GET', url);
    if (existing > 0) {
      request.headers['Range'] = 'bytes=$existing-';
    }

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (error) {
      throw DownloadException(DownloadFailureKind.network, '$error');
    }

    if (response.statusCode == 416 && existing > 0) {
      await file.delete().catchError((_) => file);
      return _fetch(
        url: url,
        file: file,
        existing: 0,
        total: total,
        verifier: verifier,
        onProgress: onProgress,
      );
    }

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw DownloadException(
        DownloadFailureKind.network,
        'Unexpected HTTP status ${response.statusCode}',
      );
    }

    final resuming = response.statusCode == 206;
    if (resuming && verifier != null) {
      await _hashFile(file, verifier);
    }
    final sink = file.openWrite(
      mode: resuming ? FileMode.append : FileMode.write,
    );
    var received = resuming ? existing : 0;
    final grandTotal = total > 0
        ? total
        : received + (response.contentLength ?? 0);

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        verifier?.addChunk(chunk);
        received += chunk.length;
        if (grandTotal > 0) {
          onProgress?.call((received / grandTotal).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
    } on FileSystemException catch (error) {
      await sink.close().catchError((_) {});
      if (error.osError?.errorCode == 28) {
        throw const DownloadException(
          DownloadFailureKind.lowDisk,
          'No space left on device.',
        );
      }
      throw DownloadException(DownloadFailureKind.unknown, '$error');
    } catch (error) {
      await sink.close().catchError((_) {});
      throw DownloadException(DownloadFailureKind.network, '$error');
    }
  }

  Future<void> _hashFile(File file, Sha256Verifier verifier) async {
    await for (final chunk in file.openRead()) {
      verifier.addChunk(chunk);
    }
  }
}
