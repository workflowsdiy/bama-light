import CoreFoundation
import Foundation

// The agent interface: one list of commands (AgentCommands.swift) that the
// CLI, its help, and the MCP server all read. Commands run inside the app,
// on the main actor, so the window updates live. Undo works only for
// actions that register it with the window's undo manager.

typealias JSONObject = [String: Any]

/// One thing an agent can do. Keep names as "<noun> <verb>": "items add".
struct AgentCommand {
    struct Param {
        enum Kind: String { case string, integer, boolean }
        var name: String
        var kind: Kind = .string
        var required = false
        /// Given without its --name, right after the command: `items show 3f2a`.
        var positional = false
        var help: String
    }

    var name: String
    var summary: String
    var params: [Param] = []
    var example: String
    /// Only reads. Agents may run it without asking.
    var readOnly = false
    /// Can replace or remove existing data (MCP destructiveHint).
    var destructive = false
    /// Without --yes, only reports what it would do.
    var requiresConfirmation = false
    var run: (Args, AppModel) throws -> Any

    var inputParams: [Param] {
        params + (requiresConfirmation ? [.init(name: "yes", kind: .boolean,
                    help: "Do it. Without yes it only shows what it would change.")] : [])
    }
}

/// The values a command was called with, checked against its params.
struct Args {
    let values: JSONObject

    init(_ values: JSONObject, for command: AgentCommand) throws {
        let params = command.inputParams
        if let unknown = values.keys.sorted().first(where: { name in !params.contains { $0.name == name } }) {
            throw AgentError.usage("\(command.name) has no option --\(unknown)")
        }
        for param in params {
            guard let value = values[param.name] else {
                if param.required { throw AgentError.usage("missing --\(param.name). Example: \(command.example)") }
                continue
            }
            let valid: Bool
            switch param.kind {
            case .string:
                valid = (value as? String).map { !param.required || !$0.isEmpty } ?? false
            case .boolean:
                valid = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            case .integer:
                valid = (value as? NSNumber).map {
                    CFGetTypeID($0) != CFBooleanGetTypeID() && $0.decimalValue == Decimal($0.int64Value)
                        && Int(exactly: $0.int64Value) != nil
                } ?? false
            }
            guard valid else { throw AgentError.usage("--\(param.name) must be \(param.kind.rawValue)\(param.required && param.kind == .string ? " and nonempty" : "")") }
        }
        self.values = values
    }

    func string(_ name: String) -> String? { values[name] as? String }

    func required(_ name: String) throws -> String {
        guard let value = string(name), !value.isEmpty else { throw AgentError.usage("missing --\(name)") }
        return value
    }

    func int(_ name: String, default fallback: Int) throws -> Int {
        values[name] as? Int ?? fallback
    }

    func bool(_ name: String) throws -> Bool? {
        values[name] as? Bool
    }

    var confirmed: Bool { (try? bool("yes")) == true }
}

/// An error with a stable code an agent can branch on, a message that says
/// how to fix it, and the exit code the CLI returns.
nonisolated struct AgentError: Error {
    var code: String
    var message: String
    var exit: Int32

    static func usage(_ message: String) -> AgentError { AgentError(code: "usage", message: message, exit: 2) }
    static func notFound(_ message: String) -> AgentError { AgentError(code: "not_found", message: message, exit: 3) }
    static func invalid(_ message: String) -> AgentError { AgentError(code: "invalid", message: message, exit: 1) }
    static func unavailable(_ message: String) -> AgentError { AgentError(code: "app_unavailable", message: message, exit: 4) }

    var json: JSONObject { ["ok": false, "error": ["code": code, "message": message]] }
}

/// Runs requests from the socket inside the app.
enum AgentRouter {
    static var model: AppModel?

    /// A request is {"command": "items add", "args": {"title": "Milk"}}.
    static func handle(_ request: Data) -> Data {
        let reply: JSONObject
        do {
            guard let object = try JSONSerialization.jsonObject(with: request) as? JSONObject,
                  let name = object["command"] as? String else { throw AgentError.usage("bad request") }
            guard let command = AgentCommands.all.first(where: { $0.name == name }) else {
                throw AgentError.usage("unknown command \"\(name)\". Run `__CLI_NAME__ help`")
            }
            guard let model else { throw AgentError.unavailable("the app is still starting. Try again") }
            guard object["args"] == nil || object["args"] is JSONObject else { throw AgentError.usage("args must be an object") }
            let args = try Args(object["args"] as? JSONObject ?? [:], for: command)
            reply = ["ok": true, "result": try command.run(args, model)]
        } catch let error as AgentError {
            reply = error.json
        } catch {
            reply = AgentError.invalid(error.localizedDescription).json
        }
        return JSON.data(reply)
    }
}

nonisolated enum JSON {
    static func data(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    static func string(_ object: Any) -> String {
        String(decoding: data(object), as: UTF8.self)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
