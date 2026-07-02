import 'dart:typed_data';

/// Decoded OSC message.
class OscMessage {
  final String address;
  final String typetag; // starts with ','
  final List<Object> args;

  const OscMessage(this.address, this.typetag, this.args);

  @override
  String toString() => 'OscMessage($address $typetag $args)';
}

/// Encodes a single OSC message to bytes.
///
/// [typetag] must start with ',' (e.g. ',f' ',s' ',i' ',').
/// [args] must match typetag characters after the comma, in order.
Uint8List encodeOsc(String address, String typetag, List<Object> args) {
  final buf = BytesBuilder();
  buf.add(_encodeString(address));
  buf.add(_encodeString(typetag));
  for (var i = 0; i < args.length; i++) {
    final tag = typetag[i + 1];
    final arg = args[i];
    switch (tag) {
      case 'i':
        buf.add(_encodeInt32(arg as int));
      case 'f':
        buf.add(_encodeFloat32((arg as num).toDouble()));
      case 's':
        buf.add(_encodeString(arg as String));
      case 'b':
        buf.add(_encodeBlob(arg as Uint8List));
      default:
        throw ArgumentError('Unsupported OSC type tag: $tag');
    }
  }
  return buf.toBytes();
}

/// Decodes an OSC message from [bytes].
OscMessage decodeOsc(Uint8List bytes) {
  var offset = 0;

  final (address, addrLen) = _decodeString(bytes, offset);
  offset += addrLen;

  final (typetag, tagLen) = _decodeString(bytes, offset);
  offset += tagLen;

  final args = <Object>[];
  for (var i = 1; i < typetag.length; i++) {
    switch (typetag[i]) {
      case 'i':
        args.add(_decodeInt32(bytes, offset));
        offset += 4;
      case 'f':
        args.add(_decodeFloat32(bytes, offset));
        offset += 4;
      case 's':
        final (s, len) = _decodeString(bytes, offset);
        args.add(s);
        offset += len;
      case 'b':
        final (blob, len) = _decodeBlob(bytes, offset);
        args.add(blob);
        offset += len;
      default:
        // Unknown tag — stop parsing args.
        break;
    }
  }

  return OscMessage(address, typetag, args);
}

/// Parses an X32 meter blob.
///
/// The blob content uses little-endian encoding (sole X32 exception):
///   [uint32 LE count][count × float32 LE]
/// The OSC blob length prefix is big-endian (standard OSC) and has already
/// been stripped by [decodeOsc]; [blob] is the raw content bytes.
List<double> decodeMeterBlob(Uint8List blob) {
  if (blob.length < 4) return const [];
  final bd = blob.buffer.asByteData(blob.offsetInBytes, blob.lengthInBytes);
  final count = bd.getUint32(0, Endian.little);
  final floats = <double>[];
  for (var i = 0; i < count; i++) {
    final byteOffset = 4 + i * 4;
    if (byteOffset + 4 > blob.length) break;
    floats.add(bd.getFloat32(byteOffset, Endian.little));
  }
  return floats;
}

/// Converts an X32 fader float (0..1) to dB.
///
/// Piecewise curve from the Unofficial X32/M32 OSC Remote Protocol (Maillot).
/// CONFIRM AGAINST REAL HARDWARE.
double floatToDb(double f) {
  if (f >= 0.5) return f * 40 - 30;
  if (f >= 0.25) return f * 80 - 50;
  if (f >= 0.0625) return f * 160 - 70;
  return f * 480 - 90;
}

/// Converts dB to X32 fader float (0..1).
///
/// Inverse of [floatToDb]. CONFIRM AGAINST REAL HARDWARE.
double dbToFloat(double db) {
  if (db >= -10) return (db + 30) / 40;
  if (db >= -30) return (db + 50) / 80;
  if (db >= -60) return (db + 70) / 160;
  return (db + 90) / 480;
}

// ── Internal helpers ────────────────────────────────────────────────────────

/// OSC string: null-terminated, padded to next 4-byte boundary.
Uint8List _encodeString(String s) {
  final bytes = s.codeUnits;
  final len = bytes.length + 1; // +1 for null terminator
  final padded = _padTo4(len);
  final out = Uint8List(padded);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i];
  }
  return out;
}

(String, int) _decodeString(Uint8List bytes, int offset) {
  var end = offset;
  while (end < bytes.length && bytes[end] != 0) {
    end++;
  }
  final s = String.fromCharCodes(bytes, offset, end);
  final rawLen = end - offset + 1; // including null
  return (s, _padTo4(rawLen));
}

Uint8List _encodeInt32(int v) {
  final out = ByteData(4);
  out.setInt32(0, v, Endian.big);
  return out.buffer.asUint8List();
}

int _decodeInt32(Uint8List bytes, int offset) {
  return bytes.buffer.asByteData().getInt32(offset, Endian.big);
}

Uint8List _encodeFloat32(double v) {
  final out = ByteData(4);
  out.setFloat32(0, v, Endian.big);
  return out.buffer.asUint8List();
}

double _decodeFloat32(Uint8List bytes, int offset) {
  return bytes.buffer.asByteData().getFloat32(offset, Endian.big);
}

/// OSC blob: [int32 BE size][bytes][padding to 4-byte boundary].
Uint8List _encodeBlob(Uint8List data) {
  final sizeBytes = _encodeInt32(data.length);
  final padded = _padTo4(data.length);
  final out = Uint8List(4 + padded);
  out.setAll(0, sizeBytes);
  out.setAll(4, data);
  return out;
}

(Uint8List, int) _decodeBlob(Uint8List bytes, int offset) {
  final size = _decodeInt32(bytes, offset);
  final blob = bytes.sublist(offset + 4, offset + 4 + size);
  final totalLen = 4 + _padTo4(size);
  return (blob, totalLen);
}

int _padTo4(int n) => (n + 3) & ~3;
