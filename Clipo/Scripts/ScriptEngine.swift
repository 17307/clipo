import Foundation
import JavaScriptCore

enum ScriptError: Error, LocalizedError {
    case runtimeError(String)
    case nonStringResult

    var errorDescription: String? {
        switch self {
        case .runtimeError(let msg): return "Script error: \(msg)"
        case .nonStringResult:       return "Script did not produce a string result."
        }
    }
}

enum ScriptEngine {
    /// Evaluates `script.source` in a fresh `JSContext`, passing `input` as a
    /// global variable. Returns the last-expression result as a string.
    static func run(_ script: ClipoScript, input: String) -> Result<String, ScriptError> {
        guard let ctx = JSContext() else {
            return .failure(.runtimeError("Could not create JS context"))
        }

        var jsException: String?
        ctx.exceptionHandler = { _, exception in
            jsException = exception?.toString() ?? "unknown JS exception"
        }

        installHelpers(on: ctx)
        ctx.setObject(input, forKeyedSubscript: "input" as NSString)

        let value = ctx.evaluateScript(script.source)

        if let err = jsException {
            return .failure(.runtimeError(err))
        }

        guard let str = value?.toString(), value?.isUndefined == false, value?.isNull == false else {
            return .failure(.nonStringResult)
        }
        return .success(str)
    }

    private static func installHelpers(on ctx: JSContext) {
        let b64Encode: @convention(block) (String) -> String = { s in
            s.data(using: .utf8)?.base64EncodedString() ?? ""
        }
        let b64Decode: @convention(block) (String) -> String = { s in
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Data(base64Encoded: trimmed) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        let urlEncode: @convention(block) (String) -> String = { s in
            s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        }
        let urlDecode: @convention(block) (String) -> String = { s in
            s.removingPercentEncoding ?? s
        }
        let log: @convention(block) (String) -> Void = { msg in
            ScriptEngine.appendLog(msg)
        }

        ctx.setObject(b64Encode, forKeyedSubscript: "__base64Encode" as NSString)
        ctx.setObject(b64Decode, forKeyedSubscript: "__base64Decode" as NSString)
        ctx.setObject(urlEncode, forKeyedSubscript: "__urlEncode" as NSString)
        ctx.setObject(urlDecode, forKeyedSubscript: "__urlDecode" as NSString)
        ctx.setObject(log,       forKeyedSubscript: "__log" as NSString)

        // Provide a tiny `console` shim so users can call `console.log("...")`.
        _ = ctx.evaluateScript("var console = { log: function(msg) { __log(String(msg)); } };")
    }

    // MARK: - Script log

    static var logURL: URL {
        let base = (try? FileManager.default.url(for: .libraryDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true)) ?? URL(fileURLWithPath: "/tmp")
        let dir = base.appending(path: "Logs/Clipo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "scripts.log")
    }

    private static func appendLog(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: .now)
        let line = "[\(stamp)] \(message)\n"
        let url = logURL
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = line.data(using: .utf8) { try? handle.write(contentsOf: data) }
        } else {
            try? line.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }
}
