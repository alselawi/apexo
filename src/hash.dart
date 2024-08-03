int fastHash(String input) {
  int hash = 0;
  int len = input.length;

  // Process 4 characters at a time
  for (int i = 0; i < len - 3; i += 4) {
    hash ^= input.codeUnitAt(i) |
        (input.codeUnitAt(i + 1) << 8) |
        (input.codeUnitAt(i + 2) << 16) |
        (input.codeUnitAt(i + 3) << 24);
  }

  // Handle remaining characters
  for (int i = len & ~3; i < len; i++) {
    hash ^= input.codeUnitAt(i) << ((i & 3) * 8);
  }

  // Final mix
  hash ^= hash >> 16;
  hash *= 0x85ebca6b;
  hash ^= hash >> 13;
  hash *= 0xc2b2ae35;
  hash ^= hash >> 16;

  return hash;
}