import Foundation

/// A small MCP server over stdin and stdout (JSON-RPC, one message per line).
/// Every AgentCommand becomes a tool ("items add" -> "items_add"), and each
/// call goes to the running app, like the CLI. Register it once:
///   claude mcp add --scope user __CLI_NAME__ -- ~/Applications/__APP_NAME__.app/Contents/MacOS/__APP_NAME__ mcp
/// Optional: Claude Code drives the CLI fine without it. Use it for Claude
/// Desktop and other clients that have no shell.
enum AgentMCP {
    static let protocolVersion = "2025-06-18"

    static func serve() {
        while let line = readLine(strippingNewline: true) {
            guard let reply = response(to: line) else { continue }
            print(JSON.string(reply))
            fflush(stdout)
        }
    }

    static func response(to line: String) -> JSONObject? {
        let value: Any
        do { value = try JSONSerialization.jsonObject(with: Data(line.utf8), options: .fragmentsAllowed) }
        catch { return Self.error(-32700, "Parse error") }
        guard let message = value as? JSONObject, message["jsonrpc"] as? String == "2.0",
              let method = message["method"] as? String, !method.isEmpty,
              message["result"] == nil, message["error"] == nil else { return error(-32600, "Invalid request") }
        let id = message["id"]
        if let id, !(id is String) {
            guard let number = id as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.decimalValue == Decimal(number.int64Value) else { return error(-32600, "Invalid request id") }
        }
        // Valid notifications never get an answer or invoke a tool.
        guard let id else { return nil }
        guard message["params"] == nil || message["params"] is JSONObject else {
            return error(-32602, "params must be an object", id: id)
        }
        let params = message["params"] as? JSONObject ?? [:]
        var reply: JSONObject = ["jsonrpc": "2.0", "id": id]
        switch method {
        case "initialize":
            guard params["protocolVersion"] is String, params["capabilities"] is JSONObject,
                  let client = params["clientInfo"] as? JSONObject,
                  client["name"] is String, client["version"] is String else {
                return error(-32602, "initialize requires protocolVersion, capabilities and clientInfo", id: id)
            }
            reply["result"] = [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "__CLI_NAME__", "version": "1.0"],
                "instructions": "Tools that drive the __APP_NAME__ app on this Mac. Tools with a yes parameter only preview changes unless yes is true.",
            ]
        case "ping": reply["result"] = [:] as JSONObject
        case "tools/list": reply["result"] = ["tools": AgentCommands.all.map(tool)]
        case "tools/call":
            guard let name = params["name"] as? String,
                  let command = AgentCommands.all.first(where: { $0.name.replacingOccurrences(of: " ", with: "_") == name }) else {
                return error(-32602, "Unknown tool", id: id)
            }
            guard params["arguments"] == nil || params["arguments"] is JSONObject else {
                return error(-32602, "arguments must be an object", id: id)
            }
            let arguments = params["arguments"] as? JSONObject ?? [:]
            do { _ = try Args(arguments, for: command) }
            catch {
                return Self.error(-32602, (error as? AgentError)?.message ?? error.localizedDescription, id: id)
            }
            reply["result"] = call(command, arguments: arguments)
        default: return error(-32601, "Unknown method \(method)", id: id)
        }
        return reply
    }

    private static func error(_ code: Int, _ message: String, id: Any = NSNull()) -> JSONObject {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private static func tool(_ command: AgentCommand) -> JSONObject {
        var schema = AgentCLI.schema(command)
        schema["name"] = command.name.replacingOccurrences(of: " ", with: "_")
        schema["annotations"] = ["readOnlyHint": command.readOnly, "destructiveHint": command.destructive]
        schema["readOnly"] = nil
        schema["destructive"] = nil
        schema["requiresConfirmation"] = nil
        return schema
    }

    private static func call(_ command: AgentCommand, arguments: JSONObject) -> JSONObject {
        do {
            let reply = try AgentSocket.send(JSON.data(["command": command.name, "args": arguments]), launch: true)
            guard let object = try JSONSerialization.jsonObject(with: reply) as? JSONObject else {
                throw AgentError.invalid("the app sent no answer")
            }
            let ok = object["ok"] as? Bool == true
            return ["content": [["type": "text", "text": JSON.string(ok ? object["result"] ?? [:] : object["error"] ?? [:])]],
                    "isError": !ok]
        } catch let error as AgentError {
            return ["content": [["type": "text", "text": JSON.string(error.json)]], "isError": true]
        } catch {
            return ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]
        }
    }
}
