//
//  clipocli — command-line companion for Clipo.
//
//  Talks to the running Clipo.app via a UNIX domain socket at
//  ~/Library/Application Support/Clipo/clipo.sock using the same framed
//  JSON protocol (4-byte big-endian length + UTF-8 JSON payload).
//
//  Commands:
//    clipocli health
//    clipocli read   [--limit N] [--filter history|images|files]
//    clipocli write  "text"           (or `-` to read from stdin)
//
//  Exit codes:
//    0  success
//    1  Clipo is not running / connection refused
//    2  usage error / invalid arguments
//    3  server returned ok=false
//

import Darwin
import Foundation

// MARK: - Constants

let socketPath: String = {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    return "\(home)/Library/Application Support/Clipo/clipo.sock"
}()

// MARK: - Usage

func printUsage(to stream: FileHandle = FileHandle.standardError) {
    let text = """
        clipocli — command-line companion for Clipo

        USAGE:
          clipocli health
          clipocli read [--limit N] [--filter history|images|files]
          clipocli write <text>
          clipocli write -                 # read text from stdin

        EXIT CODES:
          0  success
          1  Clipo is not running
          2  usage / invalid arguments
          3  server returned an error
        """
    stream.write(Data((text + "\n").utf8))
}

func die(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

// MARK: - Socket client

func connectToClipo() -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 { die("socket() failed", code: 1) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8
    guard pathBytes.count < 104 else {
        die("socket path too long: \(socketPath)", code: 1)
    }
    withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
        tuplePtr.withMemoryRebound(to: CChar.self, capacity: 104) { cPtr in
            _ = socketPath.withCString { src in
                strncpy(cPtr, src, 104)
            }
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { addrPtr in
        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    if connectResult < 0 {
        close(fd)
        die("Cannot connect to Clipo (\(socketPath)). Is the app running?", code: 1)
    }
    return fd
}

func writeFrame(fd: Int32, payload: Data) {
    let len = UInt32(payload.count).bigEndian
    var hdr = len
    let hdrBytes = withUnsafeBytes(of: &hdr) { Data($0) }
    _ = hdrBytes.withUnsafeBytes { write(fd, $0.baseAddress, 4) }
    payload.withUnsafeBytes { body in
        _ = write(fd, body.baseAddress, payload.count)
    }
}

func readFrame(fd: Int32) -> Data? {
    var lenBuf = [UInt8](repeating: 0, count: 4)
    guard readExact(fd: fd, into: &lenBuf, count: 4) else { return nil }
    let len = (UInt32(lenBuf[0]) << 24)
        | (UInt32(lenBuf[1]) << 16)
        | (UInt32(lenBuf[2]) << 8)
        | UInt32(lenBuf[3])
    guard len > 0, len <= 16 * 1024 * 1024 else { return nil }
    var buf = [UInt8](repeating: 0, count: Int(len))
    guard readExact(fd: fd, into: &buf, count: Int(len)) else { return nil }
    return Data(buf)
}

func readExact(fd: Int32, into buffer: inout [UInt8], count: Int) -> Bool {
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

// MARK: - Request / response

func sendRequest(_ request: [String: Any]) -> [String: Any] {
    let fd = connectToClipo()
    defer { close(fd) }

    guard let payload = try? JSONSerialization.data(withJSONObject: request) else {
        die("internal: could not encode request", code: 2)
    }
    writeFrame(fd: fd, payload: payload)

    guard let responseData = readFrame(fd: fd) else {
        die("no response from Clipo", code: 1)
    }
    guard let obj = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
        die("server returned invalid JSON", code: 3)
    }
    return obj
}

func printResponse(_ response: [String: Any], pretty: Bool = true) {
    let ok = response["ok"] as? Bool ?? false
    if !ok {
        if let err = response["error"] as? [String: Any] {
            let code = err["code"] as? String ?? "error"
            let msg = err["message"] as? String ?? ""
            die("[\(code)] \(msg)", code: 3)
        }
        die("server returned an error", code: 3)
    }
    let options: JSONSerialization.WritingOptions = pretty
        ? [.prettyPrinted, .sortedKeys]
        : []
    if let data = try? JSONSerialization.data(withJSONObject: response, options: options),
       let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

// MARK: - Command parsing

func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let cmd = args.first else {
        printUsage()
        exit(2)
    }
    let rest = Array(args.dropFirst())

    switch cmd {
    case "health", "h":
        let resp = sendRequest(["cmd": "health"])
        printResponse(resp)

    case "read", "r":
        var limit = 10
        var filter = "history"
        var i = 0
        while i < rest.count {
            let arg = rest[i]
            switch arg {
            case "--limit", "-n":
                guard i + 1 < rest.count, let n = Int(rest[i + 1]) else {
                    die("--limit requires an integer")
                }
                limit = n
                i += 2
            case "--filter", "-f":
                guard i + 1 < rest.count else { die("--filter requires a value") }
                filter = rest[i + 1]
                i += 2
            case "--help", "-h":
                printUsage(to: FileHandle.standardOutput); exit(0)
            default:
                die("unknown flag: \(arg)")
            }
        }
        let resp = sendRequest(["cmd": "read", "args": ["limit": limit, "filter": filter]])
        printResponse(resp)

    case "write", "w":
        let text: String
        if rest.isEmpty || rest.first == "-" {
            text = String(
                data: FileHandle.standardInput.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        } else {
            text = rest.joined(separator: " ")
        }
        if text.isEmpty { die("no text provided") }
        let resp = sendRequest(["cmd": "write", "args": ["text": text]])
        printResponse(resp)

    case "--help", "-h", "help":
        printUsage(to: FileHandle.standardOutput)
        exit(0)

    default:
        FileHandle.standardError.write(Data("unknown command: \(cmd)\n".utf8))
        printUsage()
        exit(2)
    }
}

main()
