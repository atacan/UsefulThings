import Foundation

public struct EquatableError: Error, Equatable, CustomStringConvertible, LocalizedError {
    let base: Error
    private let equals: (Error) -> Bool

    init(_ base: some Error) {
        self.base = base
        self.equals = { String(reflecting: $0) == String(reflecting: base) }
    }

    init<Base: Error & Equatable>(_ base: Base) {
        self.base = base
        self.equals = { ($0 as? Base) == base }
    }

    public static func == (lhs: EquatableError, rhs: EquatableError) -> Bool {
        lhs.equals(rhs.base)
    }

    public var description: String {
        "\(base)"
    }

    func asError<Base: Error>(type: Base.Type) -> Base? {
        base as? Base
    }

    var localizedDescription: String {
        base.localizedDescription
    }

    public var errorDescription: String? {
        base.localizedDescription
    }
}

extension Error where Self: Equatable {
    public func toEquatableError() -> EquatableError {
        EquatableError(self)
    }
}

extension Error {
    public func toEquatableError() -> EquatableError {
        EquatableError(self)
    }
}
