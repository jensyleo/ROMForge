// swift-tools-version: 6.0
//
// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.

import PackageDescription

let package = Package(
    name: "ROMForgeCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ROMForgeCore", targets: ["ROMForgeCore"]),
        .executable(name: "romforge-cli", targets: ["romforge-cli"]),
    ],
    dependencies: [
        // ZIP reading/writing for archive scanning and rebuilding (v0.3). MIT
        // license — permissive, no conflict with ROMForge's GPL-3.0.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        // Exposes system zlib (part of libSystem, always present — no
        // Homebrew/vendored dependency) for CHD's zlib hunk codec, which
        // uses raw DEFLATE just like MAME's own chd_zlib_compressor.
        .systemLibrary(name: "CZlib", pkgConfig: "zlib"),
        // Exposes liblzma for CHD's LZMA hunk codec (compression type 1).
        // ** Requires Homebrew: `brew install xz` ** — unlike CZlib, this is
        // NOT part of macOS. See Sources/CLZMA/shim.h for the version this
        // was built/tested against and what to check if a future xz update
        // breaks the build.
        .systemLibrary(name: "CLZMA", pkgConfig: "liblzma"),
        // Exposes libFLAC for CHD's FLAC hunk codec (compression type 3 and
        // the "cdfl" CD-composite variant).
        // ** Requires Homebrew: `brew install flac` ** — see
        // Sources/CFLAC/shim.h for the version this was built/tested
        // against.
        .systemLibrary(name: "CFLAC", pkgConfig: "flac"),
        .target(
            name: "ROMForgeCore",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation"), "CZlib", "CLZMA", "CFLAC"],
            // pkgConfig above resolves the Homebrew .pc files fine when
            // PKG_CONFIG_PATH already includes Homebrew's pkgconfig dirs
            // (true for anyone using Homebrew's own shell integration), but
            // falls back to these explicit Apple Silicon Homebrew prefixes
            // otherwise so `swift build`/Xcode still finds the headers/libs.
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/opt/xz/include", "-I/opt/homebrew/opt/flac/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/opt/xz/lib", "-L/opt/homebrew/opt/flac/lib"])
            ]
        ),
        .executableTarget(
            name: "romforge-cli",
            dependencies: ["ROMForgeCore"]
        ),
        .testTarget(
            name: "ROMForgeCoreTests",
            dependencies: ["ROMForgeCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
    ]
)
