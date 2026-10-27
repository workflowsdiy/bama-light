import CoreData
import SwiftUI
import __APP_NAME__Kit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            ItemList(page: model.sidebar ?? .all)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            ItemDetail()
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(SidebarItem.allCases, selection: $model.sidebar) { page in
            Label(page.title, systemImage: page.symbol)
                .tag(page)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 212)
    }
}

struct ItemList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @FetchRequest(sortDescriptors: [SortDescriptor(\Item.createdAt, order: .reverse)]) private var items: FetchedResults<Item>
    @AppStorage("confirmDelete", store: Store.defaults) private var confirmDelete = false
    @State private var pendingDelete: Item?
    let page: SidebarItem

    private var visible: [Item] {
        page == .starred ? items.filter(\.isStarred) : Array(items)
    }

    var body: some View {
        @Bindable var model = model
        List(visible, selection: $model.selection) { item in
            Label(item.title, systemImage: item.isStarred ? "star.fill" : "circle")
                .tag(item.objectID)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        if confirmDelete { pendingDelete = item } else { model.delete(item, undoManager: undoManager) }
                    }
                }
        }
        // Edit > Delete and the Delete key, only while the list has focus.
        .onDeleteCommand {
            guard let id = model.selection, let item = try? model.context.existingObject(with: id) as? Item else { return }
            if confirmDelete { pendingDelete = item } else { model.delete(item, undoManager: undoManager) }
        }
        .confirmationDialog("Delete \"\(pendingDelete?.title ?? "")\"?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let item = pendingDelete { model.delete(item, undoManager: undoManager) }
            }
        } message: {
            Text("Edit > Undo brings it back.")
        }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: page.symbol,
                    description: Text("Press Command-N to add one.")
                )
            }
        }
        .navigationTitle(page.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Item", systemImage: "plus") { model.addItem() }
                    .help("Add an item (Command-N)")
            }
        }
    }
}

struct ItemDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        if let id = model.selection, let item = try? context.existingObject(with: id) as? Item, !item.isGone {
            ItemForm(item: item)
        } else {
            // An empty grouped Form keeps the detail column's soft toolbar edge, and
            // the spacer keeps the content column's New button from moving over it.
            Form {}
                .formStyle(.grouped)
                .overlay { ContentUnavailableView("No Selection", systemImage: "sidebar.right") }
                .toolbar { ToolbarSpacer(.flexible) }
        }
    }
}

struct ItemForm: View {
    @ObservedObject var item: Item

    var body: some View {
        // Still observed after a delete from elsewhere: draw nothing rather than read it.
        if item.isGone {
            EmptyView()
        } else {
            Form {
                TextField("Title", text: $item.title)
                    // Return tidies the title (spaces, line breaks, an empty title becomes "New Item").
                    .onSubmit { item.title = ItemTitle.clean(item.title) }
                Toggle("Starred", isOn: $item.isStarred)
                TextField("Notes", text: $item.notes, axis: .vertical)
                    .lineLimit(4...)
            }
            .formStyle(.grouped)
        }
    }
}
