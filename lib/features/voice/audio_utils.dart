import 'dart:typed_data';

Float32List convertBytesToFloat32(Uint8List pcm16Data) {
  final samples = Float32List(pcm16Data.length ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    final sample = (pcm16Data[i * 2] | (pcm16Data[i * 2 + 1] << 8)).toSigned(16);
    samples[i] = sample / 32768.0;
  }
  return samples;
}
