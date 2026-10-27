import Foundation
import CoreData

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with realistic items (short and long titles, starred and not).
/// Replace these with your app's own types. Seed only what a person can
/// create in the app, or the snapshots show features no one can use.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        let context = model.context
        guard ((try? context.count(for: Item.all())) ?? 0) == 0 else { return }
        let samples: [(String, Bool)] = [
            ("Book the dentist", false),
            ("Read the article about local-first software and write down three ideas worth trying", true),
            ("Renew passport", false),
            ("Plan the weekend trip", true),
            ("Call Anna", false),
            ("Back up the photo library to the external drive before the trip", false),
            ("Groceries", false),
            ("Draft the quarterly review", true),
        ]
        for (index, sample) in samples.enumerated() {
            let item = Item(context: context, title: sample.0)
            item.isStarred = sample.1
            item.createdAt = Date.now.addingTimeInterval(Double(-index) * 3_600)
        }
        try? context.save()
    }
}
