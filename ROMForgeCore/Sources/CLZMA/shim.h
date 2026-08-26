// System-library shim exposing liblzma to Swift, for CHD's LZMA hunk codec
// (`CHDLZMADecompressor`, compression type 1).
//
// ** HOMEBREW DEPENDENCY — NOT PART OF macOS **
// Unlike zlib (CZlib — part of libSystem, always present), liblzma is NOT
// bundled with macOS. Building ROMForgeCore requires:
//     brew install xz
// This is the ONE Homebrew dependency this module introduces. If `xz`'s
// major version ever changes in a way that breaks the liblzma C API used
// here, this is the file to check first. Assumed/tested against xz 5.8.3
// (jensyleo's own machine, 2026-07-30) — see also CHANGELOG.md's build
// requirements section, which must stay in sync with this comment.
// Absolute path, not `<lzma.h>` — Xcode's own build (unlike `swift build`
// on the command line) doesn't reliably honor this package's Package.swift
// `cSettings` header search path for an embedded SPM package, so the
// Homebrew include path is hardcoded here instead. Since this whole module
// only exists because of a Homebrew dependency in the first place (see
// above), this isn't adding a new assumption — just making the existing one
// concrete enough for both build paths to find it.
#include "/opt/homebrew/opt/xz/include/lzma.h"
