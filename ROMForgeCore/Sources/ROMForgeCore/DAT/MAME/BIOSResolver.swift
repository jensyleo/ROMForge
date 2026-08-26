// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

public enum BIOSResolutionError: Error, Equatable, CustomStringConvertible {
    case machineNotFound(String)
    case circularReference([String])

    public var description: String {
        switch self {
        case .machineNotFound(let name):
            return "Machine \"\(name)\" was not found in the dataset"
        case .circularReference(let chain):
            return "Circular romof reference: \(chain.joined(separator: " -> "))"
        }
    }
}

/// Resolves what a machine needs beyond its own ROMs — its BIOS and/or
/// parent set — by following `romof` links. The same mechanism serves both
/// "parent/clone sets" and "missing BIOS" from the roadmap: a clone's
/// `romof` usually points at its parent, and a BIOS-dependent game's `romof`
/// points at the BIOS machine (e.g. `neogeo`).
public enum BIOSResolver {
    /// Returns `machineName` plus every ancestor reachable via `romof`, in
    /// dependency order: the furthest ancestor first, `machineName` last.
    public static func resolveDependencies(of machineName: String, in dataset: MAMEDataset) throws -> [MAMEMachine] {
        var chain: [MAMEMachine] = []
        var seen: Set<String> = []
        var currentName: String? = machineName

        while let name = currentName {
            guard !seen.contains(name) else {
                throw BIOSResolutionError.circularReference(chain.map(\.name) + [name])
            }
            guard let machine = dataset.machine(named: name) else {
                throw BIOSResolutionError.machineNotFound(name)
            }
            seen.insert(name)
            chain.append(machine)
            currentName = machine.romOf
        }

        return chain.reversed()
    }
}
