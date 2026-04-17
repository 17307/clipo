import Foundation

extension String {
    func shortened(to length: Int) -> String {
        guard count > length else { return self }
        return String(prefix(length))
    }
}
