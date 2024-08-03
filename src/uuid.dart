import 'dart:math';

final List<String> _lut = List.generate(256, (i) => 
    (i < 16 ? '0' : '') + i.toRadixString(16));

String uuid() {
  final random = Random();
  
  int d0 = random.nextInt(0xFFFFFFFF);
  int d1 = random.nextInt(0xFFFFFFFF);
  int d2 = random.nextInt(0xFFFFFFFF);
  int d3 = random.nextInt(0xFFFFFFFF);

  return [
    _lut[d0 & 0xFF],
    _lut[(d0 >> 8) & 0xFF],
    _lut[(d0 >> 16) & 0xFF],
    _lut[(d0 >> 24) & 0xFF],
    '-',
    _lut[d1 & 0xFF],
    _lut[(d1 >> 8) & 0xFF],
    '-',
    _lut[((d1 >> 16) & 0x0F) | 0x40],
    _lut[(d1 >> 24) & 0xFF],
    '-',
    _lut[(d2 & 0x3F) | 0x80],
    _lut[(d2 >> 8) & 0xFF],
    '-',
    _lut[(d2 >> 16) & 0xFF],
    _lut[(d2 >> 24) & 0xFF],
    _lut[d3 & 0xFF],
    _lut[(d3 >> 8) & 0xFF],
    _lut[(d3 >> 16) & 0xFF],
    _lut[(d3 >> 24) & 0xFF]
  ].join('');
}