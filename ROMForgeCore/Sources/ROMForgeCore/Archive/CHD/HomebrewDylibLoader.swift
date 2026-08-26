// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One Homebrew-installed native library ROMForge's own CHD hunk-decode
/// codecs depend on, but never link against directly at build/launch time
/// (see `HomebrewDylibLoader`'s own doc comment for why) — resolved lazily,
/// on demand, via `dlopen`/`dlsym` instead.
public struct HomebrewLibraryDependency: Sendable, Equatable {
    /// The `brew install <formula>` name — what a user actually types.
    public let formula: String
    /// Which CHD codec needs it, for a user-facing message.
    public let neededFor: String
    /// Every path this library might live at, tried in order — both real
    /// Homebrew prefixes (Apple Silicon `/opt/homebrew`, Intel `/usr/local`)
    /// plus a bare filename so `dlopen` also tries dyld's own standard
    /// search (covers a non-default Homebrew `--prefix`, or the library
    /// installed some other way entirely).
    public let candidatePaths: [String]

    public init(formula: String, neededFor: String, dylibNames: [String]) {
        self.formula = formula
        self.neededFor = neededFor
        var paths: [String] = []
        for name in dylibNames {
            paths.append("/opt/homebrew/opt/\(formula)/lib/\(name)")
            paths.append("/usr/local/opt/\(formula)/lib/\(name)")
            paths.append(name)
        }
        self.candidatePaths = paths
    }

    /// The exact dependencies real, currently-linked CHD codecs need —
    /// update this list whenever a new codec starts calling a real function
    /// from a new Homebrew library (adding one here costs nothing until
    /// that actually happens; it's just a name+path list, not a link
    /// dependency). `libFLAC` isn't listed yet: `CFLAC`/a hunk-body FLAC
    /// decompressor don't exist yet (see ROADMAP.md's own CHD hunk-decode
    /// section) — nothing calls a real libFLAC symbol, so there's nothing
    /// to check for until that changes.
    public static let all: [HomebrewLibraryDependency] = [
        HomebrewLibraryDependency(
            formula: "xz",
            neededFor: "CHD hunk decompression (LZMA/CD-LZMA codecs)",
            dylibNames: ["liblzma.5.dylib"]
        ),
    ]
}

/// Resolves a C function from a Homebrew-installed dylib at runtime
/// (`dlopen`/`dlsym`) instead of the linker embedding a hard, always-required
/// dependency on it — real bug found live by jensyleo (2026-08-05): CHD's
/// LZMA codec (`CHDLZMADecompressor`) used to `import CLZMA` with the
/// module's own `link "lzma"` directive, which made liblzma a mandatory
/// dependency for the app to even *launch*, on every machine, regardless of
/// whether any CHD file was ever scanned. `otool -L` on the built app
/// confirmed an absolute, unconditional `LC_LOAD_DYLIB` on
/// `/opt/homebrew/opt/xz/lib/liblzma.5.dylib` — missing that one exact file
/// (no Homebrew, a different prefix, `xz` never installed, an Intel Mac
/// with Homebrew at `/usr/local`) crashed the whole app at startup with a
/// dyld error, never reaching any ROMForge code that could report it
/// clearly. Loading lazily instead means: the app always launches; a
/// missing library only matters if/when a CHD file using that codec is
/// actually scanned, and even then produces a clear, catchable Swift error
/// instead of a process-level crash.
public enum HomebrewDylibLoader {
    public struct LibraryNotAvailable: Error, Equatable {
        public let dependency: HomebrewLibraryDependency
    }

    /// One process-lifetime cache per dependency's `formula`, so a missing
    /// (or found) library is only probed once — `dlopen` itself already
    /// caches per-path opens, but this also avoids repeating the whole
    /// candidate-path loop on every single hunk decode in a large CHD.
    private static let cache = Cache()
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var handles: [String: UnsafeMutableRawPointer] = [:]
        func handle(for formula: String) -> UnsafeMutableRawPointer? {
            lock.lock()
            defer { lock.unlock() }
            return handles[formula]
        }
        func setHandle(_ handle: UnsafeMutableRawPointer, for formula: String) {
            lock.lock()
            defer { lock.unlock() }
            handles[formula] = handle
        }
    }

    /// Loads `symbol` from the dependency's own dylib, trying every
    /// candidate path in order, and binds it to the given C function
    /// pointer type via `unsafeBitCast` — the same cast pattern
    /// `dlsym`-based C interop always requires, since `dlsym` itself has no
    /// way to express a typed function signature.
    public static func loadSymbol<T>(_ dependency: HomebrewLibraryDependency, symbol: String, as type: T.Type) throws -> T {
        let handle: UnsafeMutableRawPointer
        if let cached = cache.handle(for: dependency.formula) {
            handle = cached
        } else {
            guard let opened = dependency.candidatePaths.lazy.compactMap({ dlopen($0, RTLD_NOW | RTLD_LOCAL) }).first else {
                throw LibraryNotAvailable(dependency: dependency)
            }
            cache.setHandle(opened, for: dependency.formula)
            handle = opened
        }
        guard let sym = dlsym(handle, symbol) else {
            throw LibraryNotAvailable(dependency: dependency)
        }
        return unsafeBitCast(sym, to: T.self)
    }

    /// Whether `dependency`'s library can actually be found right now —
    /// for the app to check proactively at launch (before the user ever
    /// tries to scan a CHD) and show a clear "run `brew install …`"
    /// message, rather than only discovering it's missing mid-scan.
    /// Deliberately doesn't cache a *negative* result the way
    /// `loadSymbol` caches a positive one — the whole point of a proactive
    /// launch check is to notice if the user installs the missing formula
    /// and relaunches, without this reporting stale "still missing".
    public static func isAvailable(_ dependency: HomebrewLibraryDependency) -> Bool {
        if cache.handle(for: dependency.formula) != nil { return true }
        guard let handle = dependency.candidatePaths.lazy.compactMap({ dlopen($0, RTLD_NOW | RTLD_LOCAL) }).first else {
            return false
        }
        cache.setHandle(handle, for: dependency.formula)
        return true
    }
}
