import Foundation

/// Log tylko w buildzie DEBUG. W Release nic nie trafia do unified log —
/// identyfikatory konta i domu nie mają czego szukać w Console.app.
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
