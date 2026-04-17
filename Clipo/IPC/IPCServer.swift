import AppKit
import Darwin
import Foundation

/// A local IPC server for Clipo that talks over a UNIX domain socket.
///
/// Wire format (big-endian length-prefixed JSON):
/// ```
/// ┌──────────────┬────────────────────────┐
/// │ Length (4B)  │  JSON Payload          │
/// │ big-endian   │  UTF-8 encoded         │
/// └──────────────┴────────────────────────┘
/// ```
///
/// Commands supported:
///   - `health`  →  version / uptime / item count / permission status
///   - `read`    →  list recent items with optional filter + limit
///   - `write`   →  write text to the system clipboard (ingested by engine)
///
/// Security: the socket is chmod'd to 0600 so only the running user can
/// connect. No auth token is exchanged — Clipo runs unsandboxed and the
/// socket lives in the user's Application Support directory.
final class IPCServer: @unchecked Sendable {
    static let shared = IPCServer()

    /// Accept loop runs exclusively on this serial queue.
    private let acceptQueue = DispatchQueue(label: "com.ymoon.clipo.ipc.accept", qos: .utility)
    /// Each client is handled on a concurrent queue so the accept loop
    /// never blocks waiting for a request/response to complete.
    private let clientQueue = DispatchQueue(
        label: "com.ymoon.clipo.ipc.clients",
        qos: .utility,
        attributes: .concurrent
    )
    private var listenerFD: Int32 = -1
    private let startedAt = Date()

    var socketPath: String {
        IPCServer.defaultSocketPath
    }

    static var defaultSocketPath: String {
        let dir = URL.applicationSupportDirectory.appending(path: "Clipo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "clipo.sock").path
    }

    func start() {
        acceptQueue.async { [weak self] in
            self?.runListener()
        }
    }

    func stop() {
        if listenerFD >= 0 {
            close(listenerFD)
            listenerFD = -1
        }
        unlink(socketPath)
    }

    // MARK: - Listener

    private func runListener() {
        // Remove any stale socket file from a previous run.
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            log("socket() failed: errno=\(errno)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        // Copy path into sun_path (bounded to 104 bytes incl. terminator).
        let pathBytes = socketPath.utf8
        guard pathBytes.count < 104 else {
            log("socket path too long: \(socketPath)")
            close(fd)
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: 104) { cPtr in
                _ = socketPath.withCString { src in
                    strncpy(cPtr, src, 104)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if bindResult < 0 {
            log("bind() failed: errno=\(errno)")
            close(fd)
            return
        }

        // User-only permissions on the socket — no group/other access.
        chmod(socketPath, 0o600)

        if listen(fd, 8) < 0 {
            log("listen() failed: errno=\(errno)")
            close(fd)
            return
        }

        listenerFD = fd
        log("IPC listening on \(socketPath)")

        while true {
            let clientFD = accept(fd, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                break
            }
            clientQueue.async { [weak self] in
                self?.handleClient(fd: clientFD)
            }
        }
    }

    // MARK: - Per-connection handling

    private func handleClient(fd: Int32) {
        defer { close(fd) }
        guard let payload = readFrame(fd: fd) else {
            writeError(fd: fd, code: "bad_frame", message: "could not read request frame")
            return
        }

        let request: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                writeError(fd: fd, code: "bad_json", message: "request is not a JSON object")
                return
            }
            request = obj
        } catch {
            writeError(fd: fd, code: "bad_json", message: "\(error)")
            return
        }

        guard let cmd = request["cmd"] as? String else {
            writeError(fd: fd, code: "missing_cmd", message: "`cmd` field is required")
            return
        }
        let args = request["args"] as? [String: Any] ?? [:]

        // Dispatch onto the main actor — SwiftData context + AppState are
        // main-isolated.
        let response: [String: Any] = DispatchQueue.main.sync {
            IPCServer.dispatch(cmd: cmd, args: args, startedAt: self.startedAt)
        }

        writeResponse(fd: fd, response: response)
    }

    // MARK: - Command dispatch

    @MainActor
    private static func dispatch(
        cmd: String,
        args: [String: Any],
        startedAt: Date
    ) -> [String: Any] {
        switch cmd {
        case "health":
            return handleHealth(startedAt: startedAt)
        case "read":
            return handleRead(args: args)
        case "write":
            return handleWrite(args: args)
        default:
            return errorDict(code: "unknown_cmd", message: "unknown command: \(cmd)")
        }
    }

    @MainActor
    private static func handleHealth(startedAt: Date) -> [String: Any] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let data: [String: Any] = [
            "version": version,
            "uptime_seconds": Int(Date().timeIntervalSince(startedAt)),
            "history_count": AppState.shared.items.count,
            "accessibility_granted": Accessibility.isTrusted(prompt: false),
            "panel_open": AppState.shared.appDelegate?.panelIsPresented ?? false,
        ]
        return ["ok": true, "data": data]
    }

    @MainActor
    private static func handleRead(args: [String: Any]) -> [String: Any] {
        let limit = (args["limit"] as? Int) ?? 10
        let filterString = (args["filter"] as? String) ?? "history"
        let iso = ISO8601DateFormatter()

        let targetItems: [ClipItem] = {
            switch filterString {
            case "history":
                return AppState.shared.items
            case "images":
                return AppState.shared.items.filter { $0.primaryKind == .image }
            case "files":
                return AppState.shared.items.filter { $0.primaryKind == .file }
            default:
                return AppState.shared.items
            }
        }()

        let sliced = Array(targetItems.prefix(max(0, limit)))
        let encoded: [[String: Any]] = sliced.map { item in
            var dict: [String: Any] = [
                "id": item.id.uuidString,
                "kind": String(describing: item.primaryKind),
                "first_copied_at": iso.string(from: item.firstCopiedAt),
                "last_copied_at": iso.string(from: item.lastCopiedAt),
                "number_of_copies": item.numberOfCopies,
            ]
            if let t = item.text { dict["text"] = String(t.prefix(10_000)) }
            if let app = item.sourceAppBundleID { dict["source_app"] = app }
            if let pb = item.pinboard?.name { dict["pinboard"] = pb }
            return dict
        }

        return ["ok": true, "data": ["items": encoded]]
    }

    @MainActor
    private static func handleWrite(args: [String: Any]) -> [String: Any] {
        guard let text = args["text"] as? String, !text.isEmpty else {
            return errorDict(code: "missing_text", message: "`args.text` is required and non-empty")
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return ["ok": true, "data": [
            "length": text.count,
            "wrote_at": ISO8601DateFormatter().string(from: .now),
        ]]
    }

    private static func errorDict(code: String, message: String) -> [String: Any] {
        ["ok": false, "error": ["code": code, "message": message]]
    }

    // MARK: - Framing I/O

    private func readFrame(fd: Int32) -> Data? {
        var lenBuf = [UInt8](repeating: 0, count: 4)
        guard readExact(fd: fd, buffer: &lenBuf, count: 4) else { return nil }
        let len = (UInt32(lenBuf[0]) << 24)
            | (UInt32(lenBuf[1]) << 16)
            | (UInt32(lenBuf[2]) << 8)
            | UInt32(lenBuf[3])
        guard len > 0, len <= 16 * 1024 * 1024 else { return nil }

        var payload = [UInt8](repeating: 0, count: Int(len))
        guard readExact(fd: fd, buffer: &payload, count: Int(len)) else { return nil }
        return Data(payload)
    }

    private func writeResponse(fd: Int32, response: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }
        writeFrame(fd: fd, payload: data)
    }

    private func writeError(fd: Int32, code: String, message: String) {
        writeResponse(fd: fd, response: IPCServer.errorDict(code: code, message: message))
    }

    private func writeFrame(fd: Int32, payload: Data) {
        let len = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: len) { headerPtr in
            _ = write(fd, headerPtr.baseAddress, 4)
        }
        payload.withUnsafeBytes { bodyPtr in
            _ = write(fd, bodyPtr.baseAddress, payload.count)
        }
    }

    private func readExact(fd: Int32, buffer: inout [UInt8], count: Int) -> Bool {
        var total = 0
        while total < count {
            let n = buffer.withUnsafeMutableBufferPointer { bp -> Int in
                read(fd, bp.baseAddress?.advanced(by: total), count - total)
            }
            if n <= 0 { return false }
            total += n
        }
        return true
    }

    private func log(_ message: String) {
        NSLog("[Clipo IPC] %@", message)
    }
}
