// System-library shim exposing libFLAC's stream decoder to Swift, for CHD's
// FLAC hunk codec (`CHDFLACDecompressor`, compression type 3 and the "cdfl"
// CD-composite variant).
//
// ** HOMEBREW DEPENDENCY — NOT PART OF macOS **
// libFLAC is NOT bundled with macOS. Building ROMForgeCore requires:
//     brew install flac
// This is the second (of two) Homebrew dependencies this module introduces,
// alongside CLZMA's `xz`. If `flac`'s major version ever changes in a way
// that breaks the libFLAC C API used here, this is the file to check first.
// Assumed/tested against flac 1.5.0 (jensyleo's own machine, 2026-07-30) —
// see also CHANGELOG.md's build requirements section, which must stay in
// sync with this comment.
// Absolute path — see Sources/CLZMA/shim.h's own comment: Xcode's build
// doesn't reliably honor this package's Package.swift header search path
// for an embedded SPM package the way `swift build` does.
#include "/opt/homebrew/opt/flac/include/FLAC/stream_decoder.h"
