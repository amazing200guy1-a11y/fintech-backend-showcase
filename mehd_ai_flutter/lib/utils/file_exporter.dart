// Platform-conditional file export.
// On Web: uses dart:html Blob + AnchorElement for browser download.
// On Native: unsupported (native share uses share_plus with path_provider).
export 'file_exporter_stub.dart'
    if (dart.library.html) 'file_exporter_web.dart';
