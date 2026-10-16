import Cocoa

// MARK: - MultitouchSupport private API
// The real Swish reads gesture deltas the same way: raw contact frames from
// the private framework, pinch computed from contact span deltas.

private typealias MTDeviceRef = UnsafeMutableRawPointer
private typealias MTContactCallback = @convention(c) (
    Int32, UnsafeMutableRawPointer?, Int32, Double, Int32, UnsafeMutableRawPointer?
) -> Int32

@_silgen_name("MTDeviceCreateDefault")
private func MTDeviceCreateDefault() -> Unmanaged<AnyObject>?

@_silgen_name("MTRegisterContactFrameCallback")
private func MTRegisterContactFrameCallback(_ device: MTDeviceRef?, _ callback: MTContactCallback)

@_silgen_name("MTDeviceStart")
private func MTDeviceStart(_ device: MTDeviceRef?, _ run: Int32)

// 40-byte record (measured live on this machine):
//   w0 frame counter · w1 ? · w2 identifier · w3 timestamp
//   w4 state · w5 fingerID · w6 handID · w7 ? · w8 pos.x · w9 pos.y
private struct MTTouchC {
    var w0: Int32; var w1: Int32; var w2: Int32; var w3: UInt32
    var w4: Int32; var w5: Int32; var w6: Int32; var w7: Int32
    var px: Float;  var py: Float
}

final class Multitouch: @unchecked Sendable {
    static let shared = Multitouch()

    @MainActor var onPinch: ((Double) -> Void)?
    @MainActor var onTouchEnd: (() -> Void)?

    private var device: MTDeviceRef?
    /// Live contacts keyed by identifier — each callback carries one contact;
    /// consecutive callbacks in the same frame stream build the full set.
    private var live: [Int32: CGPoint] = [:]
    private var lastSpan: Float = 0

    private init() {}

    func start() {
        guard device == nil else { return }
        guard let dev = MTDeviceCreateDefault() else {
            fputs("[swishlite] MTDeviceCreateDefault failed\n", stderr)
            return
        }
        device = Unmanaged.passUnretained(dev.takeUnretainedValue()).toOpaque()
        let cb: MTContactCallback = { _, t, n, _, _, _ -> Int32 in
            guard let t else { return 0 }
            Multitouch.shared.ingest(t: t.assumingMemoryBound(to: MTTouchC.self), n: Int(n))
            return 0
        }
        MTRegisterContactFrameCallback(device, cb)
        MTDeviceStart(device, 0)
        fputs("[swishlite] multitouch device listening\n", stderr)
    }

    private func ingest(t: UnsafeMutablePointer<MTTouchC>, n: Int) {
        for i in 0..<n {
            let c = t[i]
            live[c.w2] = CGPoint(x: CGFloat(c.px), y: CGFloat(c.py))
        }
        if n == 0 && (!live.isEmpty || lastSpan != 0) {
            live.removeAll(); lastSpan = 0
            Task { @MainActor [weak self] in self?.onTouchEnd?() }
            return
        }
        computePinch()
    }

    // Main-hop coalescing: deltas accumulate on the callback thread and flush
    // once per pending Task instead of allocating one Task per contact frame
    // (touch reports arrive at ~125Hz).
    private var pendingDelta = 0.0
    private var hopPending = false

    private func computePinch() {
        guard live.count == 2 else { lastSpan = 0; return }
        // Two contacts only — read them without allocating an Array.
        var it = live.values.makeIterator()
        guard let a = it.next(), let b = it.next() else { return }
        let span = Float(hypot(a.x - b.x, a.y - b.y))
        defer { lastSpan = span }
        guard lastSpan > 0 else { return }
        let d = Double(span - lastSpan)
        guard abs(d) > 0.003 else { return }

        pendingDelta += d
        guard !hopPending else { return }
        hopPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let d = self.pendingDelta
            self.pendingDelta = 0
            self.hopPending = false
            self.onPinch?(d)
        }
    }
}
