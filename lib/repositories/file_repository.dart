import 'package:mime/mime.dart';

import '../core/api/api_client.dart';
import 'base_repository.dart';

/// Result of an upload.
class UploadedFile {
  const UploadedFile({required this.bucket, required this.path, required this.ref, required this.url, required this.size});

  final String bucket;
  final String path;

  /// `bucket/path`: store this in the database row and pass it to [FileRepository.url] later.
  final String ref;

  /// Plain URL for public buckets (avatars); null for private ones.
  final String? url;
  final int size;
}

/// Uploads and downloads go through the HR Toffy API only: the app never holds
/// a storage credential. Private files are opened through short-lived signed URLs.
class FileRepository extends BaseRepository {
  FileRepository({super.auth});

  /// `POST /organizations/:orgId/files?bucket=...` (multipart).
  /// [employeeId] uploads on behalf of someone else (HR only); [channelId] is for chat attachments.
  Future<UploadedFile> upload({
    required String bucket,
    required List<int> bytes,
    required String fileName,
    String? contentType,
    String? employeeId,
    String? channelId,
  }) async {
    final type = contentType ?? lookupMimeType(fileName, headerBytes: bytes.take(16).toList()) ?? 'application/octet-stream';
    final data = await api.postMultipart(
      orgPath('/files'),
      fileField: 'file',
      bytes: bytes,
      filename: fileName,
      contentType: type,
      query: {
        'bucket': bucket,
        if (employeeId != null) 'employeeId': employeeId,
        if (channelId != null) 'channelId': channelId,
      },
    );
    if (data is! Map || data['ref'] == null) {
      throw const ApiException(500, 'Unexpected upload response');
    }
    return UploadedFile(
      bucket: data['bucket'].toString(),
      path: data['path'].toString(),
      ref: data['ref'].toString(),
      url: data['url']?.toString(),
      size: (data['size'] as num?)?.toInt() ?? bytes.length,
    );
  }

  /// `GET /organizations/:orgId/files/url?ref=...` -> a URL that opens the file for a while.
  /// [ref] may be a `bucket/path` reference, a legacy Supabase-era URL stored in an old row,
  /// or a bare legacy path (then give [bucketHint]).
  Future<String> url(String ref, {String? bucketHint, int? expiresInSeconds}) async {
    if (ref.startsWith('http') && !ref.contains('/storage/v1/object/')) return ref; // an ordinary external URL
    final data = await api.get(orgPath('/files/url'), query: {
      'ref': ref,
      if (bucketHint != null) 'bucket': bucketHint,
      if (expiresInSeconds != null) 'expiresIn': expiresInSeconds,
    });
    final url = data is Map ? data['url']?.toString() : null;
    if (url == null || url.isEmpty) throw const ApiException(404, 'File not found');
    return url;
  }

  /// `DELETE /organizations/:orgId/files?ref=...`
  Future<void> delete(String ref, {String? bucketHint}) async {
    await api.delete(orgPath('/files'), query: {'ref': ref, if (bucketHint != null) 'bucket': bucketHint});
  }
}
