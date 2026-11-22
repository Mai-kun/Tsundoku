import 'dart:typed_data';

typedef PlatformDropFile = ({String name, Uint8List bytes, String? path});

typedef PlatformDropCallback = void Function(List<PlatformDropFile> files);
