// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

import Darwin

/// Counts heap allocations made on the main thread through libmalloc's `malloc_logger` hook,
/// the one Malloc Stack Logging uses, and records the call stack of each one for attribution.
/// The hook itself never allocates: counts and stacks go into preallocated storage, only the
/// main thread writes them (so no atomics are needed), and a reentrancy flag guards the
/// stack walk. Any logger already installed is chained and restored afterwards.
enum AllocationCounter {
  typealias Logger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

  static let depth = 24
  static let capacity = 8192

  private static let state: UnsafeMutablePointer<Int> = {
    // [0] count, [1] recorded stacks, [2] reentrancy flag
    let pointer = UnsafeMutablePointer<Int>.allocate(capacity: 3)
    pointer.initialize(repeating: 0, count: 3)
    return pointer
  }()
  private static let stacks: UnsafeMutablePointer<UnsafeMutableRawPointer?> = {
    let pointer = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(
      capacity: capacity * depth)
    pointer.initialize(repeating: nil, count: capacity * depth)
    return pointer
  }()
  private static let previous: UnsafeMutablePointer<Logger?> = {
    let pointer = UnsafeMutablePointer<Logger?>.allocate(capacity: 1)
    pointer.initialize(to: nil)
    return pointer
  }()

  struct Result {
    let count: Int
    /// The most frequent allocating call sites, as (symbol, allocations).
    let sites: [(String, Int)]
  }

  /// nil when the hook is unavailable.
  static func measure(_ body: () -> Void) -> Result? {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else {
      return nil
    }
    let slot = symbol.assumingMemoryBound(to: Logger?.self)
    let state = Self.state
    let stacks = Self.stacks
    state[0] = 0
    state[1] = 0
    state[2] = 0
    Self.previous.pointee = slot.pointee
    // MALLOC_LOG_TYPE_ALLOCATE is 2.
    let logger: Logger = { type, a1, a2, a3, result, skip in
      AllocationCounter.previous.pointee?(type, a1, a2, a3, result, skip)
      guard type & 2 != 0, pthread_main_np() != 0 else { return }
      let state = AllocationCounter.state
      state[0] += 1
      guard state[2] == 0, state[1] < AllocationCounter.capacity else { return }
      state[2] = 1
      let base = AllocationCounter.stacks + state[1] * AllocationCounter.depth
      _ = backtrace(base, Int32(AllocationCounter.depth))
      state[1] += 1
      state[2] = 0
    }
    slot.pointee = logger
    body()
    slot.pointee = Self.previous.pointee
    return Result(count: state[0], sites: attribute(stacks: stacks, recorded: state[1]))
  }

  // The first frame of each stack that is not the allocator, the logger, or the runtime's
  // own allocation entry points names the allocating call site.
  private static func attribute(
    stacks: UnsafeMutablePointer<UnsafeMutableRawPointer?>, recorded: Int
  )
    -> [(String, Int)]
  {
    let skipped = [
      "malloc", "calloc", "realloc", "_malloc", "swift_slowAlloc", "swift_allocObject",
      "AllocationCounter", "backtrace", "objc_alloc", "_objc_rootAlloc", "class_createInstance",
      "_CFRuntimeCreateInstance", "operator new", "_Znwm", "allocWithZone", "_nanov2",
      "szone_", "nano_", "_os_", "xzm_", "objc_opt_new", "_swift_allocObject",
    ]
    // Low-level libraries say what allocated; the first frame in the HUD's own code, AppKit,
    // or QuartzCore says why.
    let lowLevel = [
      "libsystem", "libc++", "libswiftCore", "CoreFoundation", "libobjc", "libdispatch",
    ]
    var counts: [String: Int] = [:]
    for index in 0..<recorded {
      var site = "unknown"
      var caller = ""
      for frame in 0..<depth {
        guard let address = stacks[index * depth + frame] else { break }
        var info = Dl_info()
        guard dladdr(address, &info) != 0, let name = info.dli_sname else { continue }
        let symbol = String(cString: name)
        if skipped.contains(where: { symbol.contains($0) }) { continue }
        let image =
          info.dli_fname.map { String(cString: $0).split(separator: "/").last ?? "" } ?? ""
        if site == "unknown" {
          site = "\(image): \(symbol)"
          if !lowLevel.contains(where: { image.hasPrefix($0) }) { break }
        } else if !lowLevel.contains(where: { image.hasPrefix($0) }) {
          caller = " <- \(image): \(symbol)"
          break
        }
      }
      counts[site + caller, default: 0] += 1
    }
    return counts.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }
  }
}
