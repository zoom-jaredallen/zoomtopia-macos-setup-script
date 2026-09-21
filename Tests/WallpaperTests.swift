import Foundation

@main
struct WallpaperTests {
    @MainActor static func main() async throws {
        var reads = 0
        let eventually = try await Wallpaper.waitForConfirmation(attempts: 5, interval: 1) {
            reads += 1
            return reads == 3
        }
        precondition(eventually && reads == 3, "Delayed readback should succeed without reapplying wallpaper")
        reads = 0
        let timeout = try await Wallpaper.waitForConfirmation(attempts: 3, interval: 1) {
            reads += 1; return false
        }
        precondition(!timeout && reads == 3, "Unconfirmed wallpaper must fail after a bounded number of reads")
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Wallpaper.waitForConfirmation(attempts: 3, interval: 1) { true }
        }
        do { _ = try await task.value; fatalError("Cancelled checks must not report success") }
        catch is CancellationError { }
        print("PASS: wallpaper delayed readback, timeout and cancellation")
    }
}
