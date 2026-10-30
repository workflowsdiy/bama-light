import CoreData
import Foundation
import __APP_NAME__Kit

/// Everything an agent can do in __CLI_NAME__. Add a command here and the CLI,
/// `help`, and the MCP tools all get it. Each `run` is on the main actor
/// with the app's model, like a button in the window.
enum AgentCommands {
    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "Show whether the app runs, the open page, and item counts.",
                     example: "__CLI_NAME__ status --json", readOnly: true) { _, model in
            let items = try model.context.fetch(Item.all())
            return ["running": true, "page": model.sidebar?.rawValue ?? "none",
                    "items": items.count, "starred": items.filter(\.isStarred).count]
        },
        AgentCommand(name: "items list", summary: "List items, newest first.",
                     params: [.init(name: "starred", kind: .boolean, help: "only starred items"),
                              .init(name: "search", help: "only items whose title or notes contain this text"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "__CLI_NAME__ items list --starred --limit 10 --json", readOnly: true) { args, model in
            let request = Item.all()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            var items = try model.context.fetch(request)
            if try args.bool("starred") == true { items = items.filter(\.isStarred) }
            if let text = args.string("search") {
                items = items.filter { $0.title.localizedStandardContains(text) || $0.notes.localizedStandardContains(text) }
            }
            let limit = try args.int("limit", default: 50)
            let offset = try args.int("offset", default: 0)
            guard limit >= 0, offset >= 0 else { throw AgentError.usage("--limit and --offset cannot be negative") }
            let page = items.dropFirst(offset).prefix(limit)
            var result: JSONObject = ["items": page.map(\.agentJSON), "total": items.count]
            if offset + page.count < items.count { result["nextOffset"] = offset + page.count }
            return result
        },
        AgentCommand(name: "items show", summary: "Show one item.",
                     params: [.init(name: "id", required: true, positional: true, help: "the item's full id or a unique prefix")],
                     example: "__CLI_NAME__ items show 3f2a9c1e --json", readOnly: true) { args, model in
            try find(try args.required("id"), in: model).agentJSON
        },
        AgentCommand(name: "items add", summary: "Add an item and select it in the window.",
                     params: [.init(name: "title", required: true, help: "the title"),
                              .init(name: "notes", help: "notes under the title"),
                              .init(name: "starred", kind: .boolean, help: "star it")],
                     example: "__CLI_NAME__ items add --title \"Buy milk\" --starred --json") { args, model in
            // Read every option before inserting: the app saves each change.
            let title = ItemTitle.clean(try args.required("title"))
            let notes = args.string("notes") ?? ""
            let starred = try args.bool("starred") ?? false
            let item = Item(context: model.context, title: title)
            item.notes = notes
            item.isStarred = starred
            try model.save()
            model.selection = item.objectID
            return item.agentJSON
        },
        AgentCommand(name: "items update", summary: "Change an item. Only the options you give change.",
                     params: [.init(name: "id", required: true, positional: true, help: "the item's id"),
                              .init(name: "title", help: "new title"),
                              .init(name: "notes", help: "new notes"),
                              .init(name: "starred", kind: .boolean, help: "true or false")],
                     example: "__CLI_NAME__ items update 3f2a9c1e --starred false --json", destructive: true) { args, model in
            let item = try find(try args.required("id"), in: model)
            let title = args.string("title").map(ItemTitle.clean)
            let notes = args.string("notes")
            let starred = try args.bool("starred")
            if let title { item.title = title }
            if let notes { item.notes = notes }
            if let starred { item.isStarred = starred }
            try model.save()
            return item.agentJSON
        },
        AgentCommand(name: "items delete", summary: "Delete an item.",
                     params: [.init(name: "id", required: true, positional: true, help: "the item's id")],
                     example: "__CLI_NAME__ items delete 3f2a9c1e --yes --json", destructive: true, requiresConfirmation: true) { args, model in
            let item = try find(try args.required("id"), in: model)
            let shown = item.agentJSON
            guard args.confirmed else { return ["deleted": false, "wouldDelete": shown, "hint": "add --yes to delete it"] }
            // The window may show this item: clear the selection before it goes.
            if model.selection == item.objectID { model.selection = nil }
            model.context.delete(item)
            try model.save()
            return ["deleted": true, "item": shown]
        },
        AgentCommand(name: "open", summary: "Show a sidebar page in the window.",
                     params: [.init(name: "page", required: true, positional: true,
                                    help: SidebarItem.allCases.map(\.rawValue).joined(separator: ", "))],
                     example: "__CLI_NAME__ open starred") { args, model in
            let name = try args.required("page")
            guard let page = SidebarItem(rawValue: name) else {
                throw AgentError.usage("no page \"\(name)\". Pages: \(SidebarItem.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            model.sidebar = page
            return ["page": page.rawValue]
        },
    ]

    /// An item by its id, or the start of it.
    static func find(_ id: String, in model: AppModel) throws -> Item {
        let items = try model.context.fetch(Item.all())
        let prefix = id.lowercased().replacingOccurrences(of: "-", with: "")
        let matches = items.filter { $0.agentID.replacingOccurrences(of: "-", with: "").hasPrefix(prefix) }
        guard let item = matches.first else { throw AgentError.notFound("no item with id \(id). Run `__CLI_NAME__ items list`") }
        guard matches.count == 1 else { throw AgentError.usage("\(matches.count) items start with \(id). Give more characters") }
        return item
    }
}

extension Item {
    /// The full canonical id; unique prefixes are accepted for convenience.
    var agentID: String { uuid.uuidString.lowercased() }

    var agentJSON: JSONObject {
        ["id": agentID, "shortId": String(agentID.prefix(8)), "title": title, "notes": notes, "starred": isStarred,
         "createdAt": JSON.date(createdAt)]
    }
}
