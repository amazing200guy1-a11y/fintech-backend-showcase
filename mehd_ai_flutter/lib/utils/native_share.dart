// Conditional export: native share uses dart:io + path_provider + share_plus.
// On web the stub is compiled instead (dart:io is unavailable).
export 'native_share_stub.dart'
    if (dart.library.html) 'native_share_web.dart';
