import AppKit
import CoreData
import Foundation
import __APP_NAME__Kit

/// One saved item. Core Data with the model defined in code (Store.model),
/// so it builds with the Command Line Tools alone: no macros, no .xcdatamodeld.
@objc(Item)
final class Item: NSManagedObject, Identifiable {
    @NSManaged var title: String
    @NSManaged var notes: String
    @NSManaged var isStarred: Bool
    @NSManaged var createdAt: Date
    /// A stable id for links, sync, and the agent CLI.
    @NSManaged var uuid: UUID

    convenience init(context: NSManagedObjectContext, title: String) {
        self.init(entity: Store.model.entitiesByName["Item"]!, insertInto: context)
        self.title = title
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        setPrimitiveValue("", forKey: "notes")
        setPrimitiveValue(false, forKey: "isStarred")
        setPrimitiveValue(Date.now, forKey: "createdAt")
        setPrimitiveValue(UUID(), forKey: "uuid")
    }

    /// Deleted from the store (by another command or an undo). Views check this before
    /// reading attributes: a deleted object traps when one is read.
    var isGone: Bool { isDeleted || managedObjectContext == nil }

    static func all() -> NSFetchRequest<Item> { NSFetchRequest<Item>(entityName: "Item") }
}

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case all, starred

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Items"
        case .starred: "Starred"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray"
        case .starred: "star"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: NSPersistentContainer
    var sidebar: SidebarItem? = .all
    var selection: NSManagedObjectID?
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: Store.defaults.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { Store.defaults.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    var context: NSManagedObjectContext { container.viewContext }

    init(container: NSPersistentContainer) {
        self.container = container
        // Save every change on the next run loop turn, so views never call save(),
        // and once more on quit.
        let center = NotificationCenter.default
        center.addObserver(forName: .NSManagedObjectContextObjectsDidChange, object: container.viewContext,
                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSave() }
        }
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveOrReport() }
        }
    }

    private var saveScheduled = false
    private var saving = false

    /// Saving posts the same change notification, so the observer only
    /// schedules one save for the next run loop turn.
    private func scheduleSave() {
        guard !saveScheduled, !saving else { return }
        saveScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.saveScheduled = false
            self?.saveOrReport()
        }
    }

    /// Saves, or undoes the unsaved changes and throws, so a failed command
    /// leaves nothing half-written behind.
    func save() throws {
        guard context.hasChanges, !saving else { return }
        saving = true
        defer { saving = false }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// For changes made in the window: a failed save shows an alert.
    func saveOrReport() {
        do { try save() } catch { NSAlert(error: error).runModal() }
    }

    /// The newest item on a page. Snapshots select it, so the detail pane
    /// shows up filled in. Change it when the pages filter differently.
    func firstItem(on page: SidebarItem) -> NSManagedObjectID? {
        let request = Item.all()
        if page == .starred { request.predicate = NSPredicate(format: "isStarred == YES") }
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first?.objectID
    }

    /// Deletes an item with Undo, which puts back a copy with the same values
    /// (and Redo deletes it again).
    func delete(_ item: Item, undoManager: UndoManager? = NSApp.keyWindow?.undoManager) {
        let title = item.title, notes = item.notes, starred = item.isStarred
        let created = item.createdAt, uuid = item.uuid
        if selection == item.objectID { selection = nil }
        context.delete(item)
        do { try save() } catch { NSAlert(error: error).runModal(); return }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                let copy = Item(context: model.context, title: title)
                copy.notes = notes
                copy.isStarred = starred
                copy.createdAt = created
                copy.uuid = uuid
                model.saveOrReport()
                model.selection = copy.objectID
                undoManager?.registerUndo(withTarget: model) { model in
                    MainActor.assumeIsolated { model.delete(copy, undoManager: undoManager) }
                }
            }
        }
        undoManager?.setActionName("Delete Item")
    }

    func addItem() {
        let item = Item(context: context, title: "")
        if sidebar == .starred { item.isStarred = true }
        saveOrReport()
        selection = item.isGone ? nil : item.objectID
    }
}
