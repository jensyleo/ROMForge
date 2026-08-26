// System-library shim exposing zlib (part of macOS's libSystem, always
// present — no Homebrew/vendored dependency) to Swift, for CHD's zlib hunk
// codec (`CHDZlibDecompressor`), which uses raw DEFLATE just like MAME's own
// `chd_zlib_compressor`/`chd_zlib_decompressor`.
#include <zlib.h>
