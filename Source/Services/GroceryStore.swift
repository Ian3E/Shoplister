import Foundation
import UIKit

/// Slight haptic for shopping list add / toggle / remove. Centralized for consistent feel.
@MainActor
private enum ShoppingListHaptics {
    static func playLight() {
        AppHaptics.impact(.light, intensity: 0.85)
    }
}

/// One language's catalog, tags, and shopping list (stored independently per language).
private struct V3Bundle: Codable, Equatable {
    var catalog: [GroceryItem] = []
    var inventoryTags: [Tag] = []
    var shoppingTags: [Tag] = []
    var shopping: [ShoppingEntry] = []
    var recipes: [Recipe] = []
    static let empty = V3Bundle()
}

@MainActor
final class GroceryStore: ObservableObject {
    @Published private(set) var catalog: [GroceryItem] = []
    @Published private(set) var shopping: [ShoppingEntry] = []
    @Published private(set) var inventoryTags: [Tag] = []
    @Published private(set) var shoppingTags: [Tag] = []
    @Published private(set) var recipes: [Recipe] = []

    private var english = V3Bundle.empty
    private var hebrew = V3Bundle.empty

    private var undoClearListSnapshot: [ShoppingEntry]?
    private var undoClearCheckedSnapshot: [ShoppingEntry]?
    @Published private(set) var canUndoClearShoppingList = false
    @Published private(set) var canUndoClearChecked = false

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let v3EnglishKey = "grocery.v3.english"
    private static let v3HebrewKey = "grocery.v3.hebrew"
    // Legacy (single shared catalog) — load once into the English side.
    private static let legacyCatalogKey = "grocery.catalog.v2"
    private static let legacyShoppingKey = "grocery.shopping.v1"
    private static let legacyInventoryTagsKey = "grocery.tags.inventory.v1"
    private static let legacyShoppingTagsKey = "grocery.tags.shopping.v1"

    init() {
        encoder.outputFormatting = [.sortedKeys]
        loadFromDiskOrLegacy()
        // Must run **before** `normalizeAndMigrateBothSides()`: that path calls `ensureUnsortedInSide`, which
        // adds only the “Undefined” tag when arrays are empty. If that runs first, `inventoryTags` is non-empty
        // and `ensureDefaultTags*` incorrectly skips creating Kitchen / Store sections — seed maps everything
        // to unsorted (no real Home/Store sections on fresh install).
        ensureDefaultTagsForEnglishIfNeeded()
        ensureDefaultTagsForHebrewIfNeeded()
        normalizeAndMigrateBothSides()
        migrateV1CatalogIfNeededForEnglish()
        if english.catalog.isEmpty {
            seedEnglishCatalog()
        } else {
            repairOrphanedTagIds(in: &english)
            sortCatalog(for: .english)
        }
        if hebrew.catalog.isEmpty {
            seedHebrewCatalog()
        } else {
            repairOrphanedTagIds(in: &hebrew)
            sortCatalog(for: .hebrew)
        }
        saveAllToDisk()
        removeLegacyUserDefaultsKeysIfMigrated()
        syncPublishedFromActiveContentLanguage()
        _ = ShareExtensionAppGroupSupport.mergePendingShoppingOpsFromAppGroup(into: self)
    }

    // MARK: - User switches catalog language in Settings (UserDefaults) — re-bind active arrays.

    func applyContentLanguageFromUserDefaults() {
        invalidateShoppingListUndo()
        syncPublishedFromActiveContentLanguage()
        ShareExtensionAppGroupSupport.mirrorCatalogLanguagePreferenceToSuite()
        _ = ShareExtensionAppGroupSupport.mergePendingShoppingOpsFromAppGroup(into: self)
    }

    /// Call when the host app may have been opened after the share extension wrote pending shopping ops.
    func mergeShareExtensionShoppingOpsIfNeeded() {
        _ = ShareExtensionAppGroupSupport.mergePendingShoppingOpsFromAppGroup(into: self)
    }

    // MARK: - Catalog (Inventory)

    func addCatalogItem(
        name: String,
        inventoryTagID: UUID,
        shoppingTagID: UUID,
        id: UUID = UUID(),
        image: UIImage? = nil
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = nextSortOrderForNewItem(inventoryTagID: inventoryTagID)
        var hasImage = false
        if let image {
            try? ItemImageStore.save(image, forItemID: id)
            hasImage = ItemImageStore.fileExists(forItemID: id)
        }
        let newItem = GroceryItem(
            id: id,
            name: trimmed,
            inventoryTagID: inventoryTagID,
            shoppingTagID: shoppingTagID,
            sortOrder: nextOrder,
            hasImage: hasImage
        )
        mutateActive { bundle in
            bundle.catalog.append(newItem)
        }
        sortCatalog(for: currentContentLanguage())
        saveAndPublish()
    }

    func updateCatalogItem(_ item: GroceryItem) {
        guard let idx = activeCatalogIndex(of: item.id) else { return }
        let previous = activeCatalog[idx]
        var updated = item
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { return }
        if previous.hasImage, !updated.hasImage {
            ItemImageStore.delete(forItemID: item.id)
        }
        let movesGroup = previous.inventoryTagID != updated.inventoryTagID
        if movesGroup {
            // Moving between inventory groups: append to the end of the new group.
            updated.sortOrder = nextSortOrderForNewItem(inventoryTagID: updated.inventoryTagID)
        }
        mutateActive { bundle in
            if movesGroup {
                // Re-compact the old group (same order as before: before the item leaves it).
                compactCatalogSortOrders(inInventoryTagID: previous.inventoryTagID, bundle: &bundle)
            }
            bundle.catalog[idx] = updated
            compactCatalogSortOrders(inInventoryTagID: updated.inventoryTagID, bundle: &bundle)
        }
        sortCatalog(for: currentContentLanguage())
        saveAndPublish()
    }

    // Archive/restore removed: this app no longer uses an archive state for inventory items.

    func deleteCatalogItem(_ id: UUID) {
        let removedShoppingLine = mutateActiveReturning { (bundle: inout V3Bundle) -> Bool in
            let removedInventoryTagID = bundle.catalog.first(where: { $0.id == id })?.inventoryTagID
            let hadShoppingLine = bundle.shopping.contains { $0.itemID == id }
            bundle.catalog.removeAll { $0.id == id }
            bundle.shopping.removeAll { $0.itemID == id }
            pruneRecipeLinesInBundle(referencingItemID: id, bundle: &bundle)
            if let removedInventoryTagID {
                compactCatalogSortOrders(inInventoryTagID: removedInventoryTagID, bundle: &bundle)
            }
            return hadShoppingLine
        }
        ItemImageStore.delete(forItemID: id)
        if removedShoppingLine {
            ShoppingListHaptics.playLight()
        }
        saveAndPublish()
    }

    // MARK: - Tags

    var defaultInventoryTagID: UUID {
        unsortedInventoryTagID ?? inventoryTags.first?.id ?? UUID()
    }

    var defaultShoppingTagID: UUID {
        unsortedShoppingTagID ?? shoppingTags.first?.id ?? UUID()
    }

    private var unsortedInventoryTagID: UUID? {
        inventoryTags.first(where: { Tag.isUnsortedBucket($0) })?.id
    }

    private var unsortedShoppingTagID: UUID? {
        shoppingTags.first(where: { Tag.isUnsortedBucket($0) })?.id
    }

    @discardableResult
    func addTag(kind: Tag.Kind, title: String) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !Tag.isUnsortedCanonicalTitle(trimmed) else { return nil }

        let tag = mutateActiveReturning { (bundle: inout V3Bundle) -> Tag in
            switch kind {
            case .inventory:
                let next = (bundle.inventoryTags.map(\.sortOrder).max() ?? -1) + 1
                let newTag = Tag(kind: .inventory, title: trimmed, sortOrder: next)
                bundle.inventoryTags.append(newTag)
                return newTag
            case .shopping:
                let next = (bundle.shoppingTags.map(\.sortOrder).max() ?? -1) + 1
                let newTag = Tag(kind: .shopping, title: trimmed, sortOrder: next)
                bundle.shoppingTags.append(newTag)
                return newTag
            }
        }
        sortActiveTagsInPlace()
        saveAndPublish()
        return tag.id
    }

    func moveUserInventoryTags(fromOffsets source: IndexSet, toOffset destination: Int) {
        mutateActive { bundle in
            var user = bundle.inventoryTags.filter { !Tag.isUnsortedBucket($0) }
            let unsorted = bundle.inventoryTags.filter { Tag.isUnsortedBucket($0) }
            user.move(fromOffsets: source, toOffset: destination)
            bundle.inventoryTags = user + unsorted
            compactSortOrders(&bundle.inventoryTags)
        }
        saveAndPublish()
    }

    func moveUserShoppingTags(fromOffsets source: IndexSet, toOffset destination: Int) {
        mutateActive { bundle in
            var user = bundle.shoppingTags.filter { !Tag.isUnsortedBucket($0) }
            let unsorted = bundle.shoppingTags.filter { Tag.isUnsortedBucket($0) }
            user.move(fromOffsets: source, toOffset: destination)
            bundle.shoppingTags = user + unsorted
            compactSortOrders(&bundle.shoppingTags)
        }
        saveAndPublish()
    }

    func renameTag(kind: Tag.Kind, tagID: UUID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !Tag.isUnsortedCanonicalTitle(trimmed) else { return }
        let renamed = mutateActiveReturning { (bundle: inout V3Bundle) -> Bool in
            switch kind {
            case .inventory:
                guard let idx = bundle.inventoryTags.firstIndex(where: { $0.id == tagID }) else { return false }
                guard !Tag.isUnsortedBucket(bundle.inventoryTags[idx]) else { return false }
                bundle.inventoryTags[idx].title = trimmed
            case .shopping:
                guard let idx = bundle.shoppingTags.firstIndex(where: { $0.id == tagID }) else { return false }
                guard !Tag.isUnsortedBucket(bundle.shoppingTags[idx]) else { return false }
                bundle.shoppingTags[idx].title = trimmed
            }
            return true
        }
        guard renamed else { return }
        sortActiveTagsInPlace()
        saveAndPublish()
    }

    func deleteTag(kind: Tag.Kind, tagID: UUID) {
        let deleted = mutateActiveReturning { (bundle: inout V3Bundle) -> Bool in
            switch kind {
            case .inventory:
                guard let victim = bundle.inventoryTags.first(where: { $0.id == tagID }) else { return false }
                guard !Tag.isUnsortedBucket(victim) else { return false }
                guard bundle.inventoryTags.count > 1 else { return false }
                guard let fallback = bundle.inventoryTags.first(where: { Tag.isUnsortedBucket($0) })?.id else { return false }
                bundle.inventoryTags.removeAll { $0.id == tagID }
                compactSortOrders(&bundle.inventoryTags)
                for i in bundle.catalog.indices
                    where bundle.catalog[i].inventoryTagID == tagID
                {
                    bundle.catalog[i].inventoryTagID = fallback
                }
            case .shopping:
                guard let victim = bundle.shoppingTags.first(where: { $0.id == tagID }) else { return false }
                guard !Tag.isUnsortedBucket(victim) else { return false }
                guard bundle.shoppingTags.count > 1 else { return false }
                guard let fallback = bundle.shoppingTags.first(where: { Tag.isUnsortedBucket($0) })?.id else { return false }
                bundle.shoppingTags.removeAll { $0.id == tagID }
                compactSortOrders(&bundle.shoppingTags)
                for i in bundle.catalog.indices
                    where bundle.catalog[i].shoppingTagID == tagID
                {
                    bundle.catalog[i].shoppingTagID = fallback
                }
            }
            return true
        }
        guard deleted else { return }
        sortActiveTagsInPlace()
        sortCatalog(for: currentContentLanguage())
        saveAndPublish()
    }

    private var englishUnsortedInventoryID: UUID? {
        english.inventoryTags.first(where: { Tag.isUnsortedBucket($0) })?.id
    }

    private var englishUnsortedShoppingID: UUID? {
        english.shoppingTags.first(where: { Tag.isUnsortedBucket($0) })?.id
    }

    private var hebrewUnsortedInventoryID: UUID? {
        hebrew.inventoryTags.first(where: { Tag.isUnsortedBucket($0) })?.id
    }

    private var hebrewUnsortedShoppingID: UUID? {
        hebrew.shoppingTags.first(where: { Tag.isUnsortedBucket($0) })?.id
    }

    // MARK: - Shopping

    func addToShopping(itemID: UUID, quantity: Int, playHaptic: Bool = true) {
        invalidateShoppingListUndo()
        let qty = max(1, quantity)
        mutateActive { bundle in
            if let idx = bundle.shopping.firstIndexForQuantityUpdate(itemID: itemID) {
                bundle.shopping[idx].quantity += qty
            } else {
                bundle.shopping.append(.init(itemID: itemID, quantity: qty))
            }
        }
        sortShoppingInPlace()
        if playHaptic {
            ShoppingListHaptics.playLight()
        }
        saveAndPublish()
    }

    func incrementUncheckedShoppingQuantity(itemID: UUID, delta: Int = 1, playHaptic: Bool = true) {
        invalidateShoppingListUndo()
        let d = max(1, delta)
        mutateActive { bundle in
            if let idx = bundle.shopping.firstIndexForQuantityUpdate(itemID: itemID) {
                bundle.shopping[idx].quantity += d
            } else {
                bundle.shopping.append(.init(itemID: itemID, quantity: d))
            }
        }
        sortShoppingInPlace()
        if playHaptic {
            ShoppingListHaptics.playLight()
        }
        saveAndPublish()
    }

    func adjustUncheckedShoppingQuantity(itemID: UUID, delta: Int, playHaptic: Bool = true) {
        guard delta != 0 else { return }
        invalidateShoppingListUndo()
        let adjusted = mutateActiveReturning { (bundle: inout V3Bundle) -> Bool in
            guard let idx = bundle.shopping.firstIndexForQuantityUpdate(itemID: itemID) else { return false }
            let newQuantity = bundle.shopping[idx].quantity + delta
            guard newQuantity >= 1 else { return false }
            bundle.shopping[idx].quantity = newQuantity
            return true
        }
        guard adjusted else { return }
        if playHaptic {
            ShoppingListHaptics.playLight()
        }
        saveAndPublish()
    }

    func shoppingListQuantity(for itemID: UUID) -> Int {
        activeShopping
            .filter { $0.itemID == itemID }
            .map(\.quantity)
            .reduce(0, +)
    }

    func toggleChecked(entryID: UUID) {
        invalidateShoppingListUndo()
        let toggled = mutateActiveReturning { (bundle: inout V3Bundle) -> Bool in
            guard let idx = bundle.shopping.firstIndex(where: { $0.id == entryID }) else { return false }
            bundle.shopping[idx].isChecked.toggle()
            return true
        }
        if toggled {
            ShoppingListHaptics.playLight()
        }
        saveAndPublish()
    }

    func setQuantity(entryID: UUID, quantity: Int) {
        invalidateShoppingListUndo()
        mutateActive { bundle in
            if let idx = bundle.shopping.firstIndex(where: { $0.id == entryID }) {
                bundle.shopping[idx].quantity = max(1, quantity)
            }
        }
        saveAndPublish()
    }

    func adjustShoppingEntryQuantity(entryID: UUID, delta: Int, playHaptic: Bool = true) {
        guard delta != 0 else { return }
        invalidateShoppingListUndo()
        let adjusted = mutateActiveReturning { (bundle: inout V3Bundle) -> Bool in
            guard let idx = bundle.shopping.firstIndex(where: { $0.id == entryID }) else { return false }
            let newQuantity = bundle.shopping[idx].quantity + delta
            guard newQuantity >= 1 else { return false }
            bundle.shopping[idx].quantity = newQuantity
            return true
        }
        guard adjusted else { return }
        if playHaptic {
            ShoppingListHaptics.playLight()
        }
        saveAndPublish()
    }

    func removeEntry(entryID: UUID) {
        invalidateShoppingListUndo()
        let removed = mutateActiveReturning { (bundle: inout V3Bundle) -> Bool in
            guard bundle.shopping.contains(where: { $0.id == entryID }) else { return false }
            bundle.shopping.removeAll { $0.id == entryID }
            return true
        }
        if removed {
            ShoppingListHaptics.playLight()
        }
        saveAndPublish()
    }

    func removeFromShopping(itemID: UUID) {
        invalidateShoppingListUndo()
        let removed = mutateActiveReturning { (bundle: inout V3Bundle) -> Bool in
            guard bundle.shopping.contains(where: { $0.itemID == itemID }) else { return false }
            bundle.shopping.removeAll { $0.itemID == itemID }
            return true
        }
        if removed {
            ShoppingListHaptics.playLight()
        }
        saveAndPublish()
    }

    func clearChecked() {
        let checkedSnapshot = activeShopping.filter(\.isChecked)
        guard !checkedSnapshot.isEmpty else { return }
        captureUndoClearChecked(checkedSnapshot)
        mutateActive { bundle in
            bundle.shopping.removeAll { $0.isChecked }
        }
        ShoppingListHaptics.playLight()
        saveAndPublish()
    }

    func clearShoppingList() {
        guard !activeShopping.isEmpty else { return }
        captureUndoClearList(activeShopping)
        mutateActive { bundle in
            bundle.shopping.removeAll()
        }
        ShoppingListHaptics.playLight()
        saveAndPublish()
    }

    func undoClearShoppingList() {
        guard let snapshot = undoClearListSnapshot else { return }
        invalidateShoppingListUndo()
        mutateActive { bundle in
            bundle.shopping = snapshot
        }
        sortShoppingInPlace()
        ShoppingListHaptics.playLight()
        saveAndPublish()
    }

    func undoClearChecked() {
        guard let snapshot = undoClearCheckedSnapshot else { return }
        invalidateShoppingListUndo()
        mutateActive { bundle in
            bundle.shopping.append(contentsOf: snapshot)
        }
        sortShoppingInPlace()
        ShoppingListHaptics.playLight()
        saveAndPublish()
    }

    private func captureUndoClearList(_ snapshot: [ShoppingEntry]) {
        undoClearListSnapshot = snapshot
        undoClearCheckedSnapshot = nil
        canUndoClearShoppingList = true
        canUndoClearChecked = false
    }

    private func captureUndoClearChecked(_ snapshot: [ShoppingEntry]) {
        undoClearCheckedSnapshot = snapshot
        undoClearListSnapshot = nil
        canUndoClearChecked = true
        canUndoClearShoppingList = false
    }

    private func invalidateShoppingListUndo() {
        undoClearListSnapshot = nil
        undoClearCheckedSnapshot = nil
        canUndoClearShoppingList = false
        canUndoClearChecked = false
    }

    func resetLibraryToInitialSeed() {
        ItemImageStore.deleteAllStoredImages()
        english = .empty
        hebrew = .empty
        ensureDefaultTagsForEnglishIfNeeded()
        ensureDefaultTagsForHebrewIfNeeded()
        seedEnglishCatalog()
        seedHebrewCatalog()
        UserDefaults.standard.removeObject(forKey: "grocery.catalog.v1.backup")
        saveAllToDisk()
        syncPublishedFromActiveContentLanguage()
    }

    func clearLibrary(for language: AppContentLanguage) {
        switch language {
        case .hebrew:
            clearLibraryContents(in: &hebrew, hebrew: true)
        case .english:
            clearLibraryContents(in: &english, hebrew: false)
        }
        saveAllToDisk()
        syncPublishedFromActiveContentLanguage()
    }

    private func clearLibraryContents(in bundle: inout V3Bundle, hebrew: Bool) {
        for id in bundle.catalog.map(\.id) {
            ItemImageStore.delete(forItemID: id)
        }
        bundle.catalog.removeAll()
        bundle.shopping.removeAll()
        bundle.recipes.removeAll()
        bundle.inventoryTags.removeAll { !Tag.isUnsortedBucket($0) }
        bundle.shoppingTags.removeAll { !Tag.isUnsortedBucket($0) }
        ensureUnsortedInSide(&bundle, hebrew: hebrew)
        compactSortOrders(&bundle.inventoryTags)
        compactSortOrders(&bundle.shoppingTags)
    }

    // MARK: - Lookups

    func item(for id: UUID) -> GroceryItem? {
        activeCatalog.first { $0.id == id }
    }

    func inventoryTagTitle(for id: UUID) -> String {
        inventoryTags.first { $0.id == id }?.title
            ?? (currentContentLanguage() == .hebrew ? Tag.unsortedHebrewTitle : Tag.unsortedCanonicalTitle)
    }

    func shoppingTagTitle(for id: UUID) -> String {
        shoppingTags.first { $0.id == id }?.title
            ?? (currentContentLanguage() == .hebrew ? Tag.unsortedHebrewTitle : Tag.unsortedCanonicalTitle)
    }

    func recipe(for id: UUID) -> Recipe? {
        activeRecipes.first { $0.id == id }
    }

    // MARK: - Recipes

    @discardableResult
    func createRecipeFromUncheckedShoppingList(name: String) -> UUID? {
        let lines: [RecipeLine] = shopping.compactMap { entry in
            guard !entry.isChecked, item(for: entry.itemID) != nil else { return nil }
            return RecipeLine(id: UUID(), itemID: entry.itemID, quantity: entry.quantity)
        }
        return addRecipe(name: name, lines: lines)
    }

    @discardableResult
    private func addRecipe(name: String, lines: [RecipeLine]) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !lines.isEmpty else { return nil }
        let nextOrder = (activeRecipes.map(\.sortOrder).max() ?? -1) + 1
        let recipe = Recipe(id: UUID(), name: trimmed, sortOrder: nextOrder, lines: lines)
        mutateActive { bundle in
            bundle.recipes.append(recipe)
        }
        sortRecipesInActiveBundle()
        saveAndPublish()
        ShoppingListHaptics.playLight()
        return recipe.id
    }

    func updateRecipe(_ recipe: Recipe) {
        var updated = recipe
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { return }
        updated.lines = updated.lines.map { line in
            var next = line
            next.quantity = max(1, next.quantity)
            return next
        }
        guard let idx = activeRecipeIndex(of: updated.id) else { return }
        mutateActive { bundle in
            bundle.recipes[idx] = updated
        }
        sortRecipesInActiveBundle()
        saveAndPublish()
    }

    func deleteRecipe(id: UUID) {
        mutateActive { bundle in
            bundle.recipes.removeAll { $0.id == id }
        }
        saveAndPublish()
    }

    func moveRecipes(fromOffsets source: IndexSet, toOffset destination: Int) {
        mutateActive { bundle in
            bundle.recipes.move(fromOffsets: source, toOffset: destination)
            compactRecipeSortOrders(in: &bundle.recipes)
        }
        saveAndPublish()
    }

    func addRecipeToShopping(recipeID: UUID, lineIDs: Set<UUID>, playHaptic: Bool = true) {
        guard let recipe = activeRecipes.first(where: { $0.id == recipeID }) else { return }
        let selected = recipe.lines.filter { lineIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        for line in selected {
            guard item(for: line.itemID) != nil else { continue }
            addToShopping(itemID: line.itemID, quantity: line.quantity, playHaptic: false)
        }
        if playHaptic {
            ShoppingListHaptics.playLight()
        }
    }

    private func pruneRecipeLinesInBundle(referencingItemID itemID: UUID, bundle: inout V3Bundle) {
        for i in bundle.recipes.indices {
            bundle.recipes[i].lines.removeAll { $0.itemID == itemID }
        }
        bundle.recipes.removeAll { $0.lines.isEmpty }
    }

    private func activeRecipeIndex(of id: UUID) -> Int? {
        activeRecipes.firstIndex { $0.id == id }
    }

    private var activeRecipes: [Recipe] {
        activeBundle.recipes
    }

    private func sortRecipesInActiveBundle() {
        mutateActive { bundle in
            bundle.recipes.sort(by: recipeSortPredicate)
        }
    }

    private func compactRecipeSortOrders(in recipes: inout [Recipe]) {
        for i in recipes.indices {
            recipes[i].sortOrder = i
        }
    }

    private func recipeSortPredicate(_ a: Recipe, _ b: Recipe) -> Bool {
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    // MARK: - Content language (catalog data)

    private func currentContentLanguage() -> AppContentLanguage {
        let raw = UserDefaults.standard.string(forKey: AppContentLanguage.storageKey)
        return AppContentLanguage(rawValue: raw ?? "") ?? .english
    }

    /// The active language's library (read-only copy). To change it, use `mutateActive`.
    private var activeBundle: V3Bundle {
        currentContentLanguage() == .hebrew ? hebrew : english
    }

    /// Edits the active language's library in place — the one path every user action goes through
    /// (Phase 0b; sync will hook in here). `body` must only use the `bundle` it's given: reading
    /// `english` / `hebrew` / `activeBundle` (or anything built on them) inside it is an overlapping
    /// access Swift traps on at runtime.
    private func mutateActive(_ body: (inout V3Bundle) -> Void) {
        if currentContentLanguage() == .hebrew {
            body(&hebrew)
        } else {
            body(&english)
        }
    }

    /// `mutateActive` that returns a value (e.g. whether anything changed).
    private func mutateActiveReturning<T>(_ body: (inout V3Bundle) -> T) -> T {
        if currentContentLanguage() == .hebrew {
            return body(&hebrew)
        } else {
            return body(&english)
        }
    }

    /// Saves both libraries and republishes the active one to the UI.
    private func saveAndPublish() {
        saveAllToDisk()
        syncPublishedFromActiveContentLanguage()
    }

    private var activeCatalog: [GroceryItem] {
        activeBundle.catalog
    }

    private var activeShopping: [ShoppingEntry] {
        activeBundle.shopping
    }

    private func activeCatalogIndex(of id: UUID) -> Int? {
        activeCatalog.firstIndex { $0.id == id }
    }

    private func syncPublishedFromActiveContentLanguage() {
        let bundle = activeBundle
        catalog = bundle.catalog
        shopping = bundle.shopping
        inventoryTags = bundle.inventoryTags
        shoppingTags = bundle.shoppingTags
        recipes = bundle.recipes
    }

    // MARK: - Sorting

    private func sortCatalog(for language: AppContentLanguage) {
        if language == .hebrew {
            GroceryStore.sort(
                catalog: &hebrew.catalog,
                usingInventoryTagOrder: hebrew.inventoryTags
            )
        } else {
            GroceryStore.sort(
                catalog: &english.catalog,
                usingInventoryTagOrder: english.inventoryTags
            )
        }
    }

    private static func sort(
        catalog: inout [GroceryItem],
        usingInventoryTagOrder invTags: [Tag]
    ) {
        let invRank = Dictionary(uniqueKeysWithValues: invTags.enumerated().map { ($0.element.id, $0.offset) }
        )
        catalog.sort {
            let ra = invRank[$0.inventoryTagID] ?? Int.max
            let rb = invRank[$1.inventoryTagID] ?? Int.max
            if ra != rb { return ra < rb }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func sortActiveTagsInPlace() {
        mutateActive { bundle in
            bundle.inventoryTags.sort(by: tagSortPredicate)
            bundle.shoppingTags.sort(by: tagSortPredicate)
        }
    }

    private func tagSortPredicate(_ a: Tag, _ b: Tag) -> Bool {
        let aUn = Tag.isUnsortedBucket(a)
        let bUn = Tag.isUnsortedBucket(b)
        if aUn != bUn { return !aUn }
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    private func sortShoppingInPlace() {
        mutateActive { bundle in
            bundle.shopping.sort { $0.addedAt > $1.addedAt }
        }
    }

    // MARK: - Post-load (both sides)

    private func normalizeAndMigrateBothSides() {
        normalizeTagArrayInBundle(&english)
        normalizeTagArrayInBundle(&hebrew)
        migrateUnsortedOnSide(&english, hebrew: false)
        migrateUnsortedOnSide(&hebrew, hebrew: true)
        ensureUnsortedInSide(&english, hebrew: false)
        ensureUnsortedInSide(&hebrew, hebrew: true)
        normalizeCatalogSortOrders(in: &english)
        normalizeCatalogSortOrders(in: &hebrew)
        normalizeItemImages(in: &english)
        normalizeItemImages(in: &hebrew)
    }

    /// Ensures `sortOrder` is compact and stable *within each inventory tag*.
    /// For legacy catalogs (missing `sortOrder`), this preserves the previous “sorted by name” feel.
    private func normalizeCatalogSortOrders(in bundle: inout V3Bundle) {
        let tagIDs = Set(bundle.catalog.map(\.inventoryTagID))
        for tagID in tagIDs {
            var indices: [Int] = []
            indices.reserveCapacity(bundle.catalog.count)
            for i in bundle.catalog.indices where bundle.catalog[i].inventoryTagID == tagID {
                indices.append(i)
            }
            if indices.isEmpty { continue }
            indices.sort { a, b in
                let ia = bundle.catalog[a]
                let ib = bundle.catalog[b]
                if ia.sortOrder != ib.sortOrder { return ia.sortOrder < ib.sortOrder }
                return ia.name.localizedCaseInsensitiveCompare(ib.name) == .orderedAscending
            }
            for (order, idx) in indices.enumerated() {
                bundle.catalog[idx].sortOrder = order
            }
        }
    }

    private func compactCatalogSortOrders(inInventoryTagID tagID: UUID, bundle: inout V3Bundle) {
        var indices: [Int] = []
        indices.reserveCapacity(bundle.catalog.count)
        for i in bundle.catalog.indices where bundle.catalog[i].inventoryTagID == tagID {
            indices.append(i)
        }
        if indices.isEmpty { return }
        indices.sort { bundle.catalog[$0].sortOrder < bundle.catalog[$1].sortOrder }
        for (order, idx) in indices.enumerated() {
            bundle.catalog[idx].sortOrder = order
        }
    }

    private func nextSortOrderForNewItem(inventoryTagID: UUID) -> Int {
        let items = activeCatalog.filter { $0.inventoryTagID == inventoryTagID }
        return (items.map(\.sortOrder).max() ?? -1) + 1
    }

    // MARK: - Inventory reordering (within group)

    /// Reorders catalog items **within a single inventory group** for the rows currently shown
    /// (full group or search-filtered). Items in the group that are not shown keep their slots.
    func moveCatalogItems(
        withinInventoryTagID tagID: UUID,
        displayedItemIDs: [UUID],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        guard !displayedItemIDs.isEmpty else { return }

        var reorderedVisible = displayedItemIDs
        reorderedVisible.move(fromOffsets: source, toOffset: destination)

        let lang = currentContentLanguage()

        func move(in bundle: inout V3Bundle) {
            var indices: [Int] = []
            for i in bundle.catalog.indices where bundle.catalog[i].inventoryTagID == tagID {
                indices.append(i)
            }
            guard !indices.isEmpty else { return }

            let fullOrderedIDs = indices
                .sorted { bundle.catalog[$0].sortOrder < bundle.catalog[$1].sortOrder }
                .map { bundle.catalog[$0].id }

            let mergedIDs = Self.mergeVisibleReorderIntoTagOrder(
                fullOrderedIDs: fullOrderedIDs,
                reorderedVisibleIDs: reorderedVisible
            )

            let rank = Dictionary(uniqueKeysWithValues: mergedIDs.enumerated().map { ($0.element, $0.offset) })
            for i in bundle.catalog.indices where bundle.catalog[i].inventoryTagID == tagID {
                bundle.catalog[i].sortOrder = rank[bundle.catalog[i].id] ?? bundle.catalog[i].sortOrder
            }
            compactCatalogSortOrders(inInventoryTagID: tagID, bundle: &bundle)
        }

        mutateActive { bundle in
            move(in: &bundle)
        }

        sortCatalog(for: lang)
        saveAndPublish()
    }

    /// Replaces visible slots in tag order with `reorderedVisibleIDs` (same multiset); hidden IDs unchanged in place.
    private static func mergeVisibleReorderIntoTagOrder(
        fullOrderedIDs: [UUID],
        reorderedVisibleIDs: [UUID]
    ) -> [UUID] {
        let visibleSet = Set(reorderedVisibleIDs)
        var visibleQueue = reorderedVisibleIDs
        return fullOrderedIDs.map { id in
            guard visibleSet.contains(id) else { return id }
            return visibleQueue.removeFirst()
        }
    }

    private func normalizeItemImages(in bundle: inout V3Bundle) {
        for i in bundle.catalog.indices {
            let id = bundle.catalog[i].id
            let fileOK = ItemImageStore.fileExists(forItemID: id)
            if bundle.catalog[i].hasImage, !fileOK {
                bundle.catalog[i].hasImage = false
            } else if !bundle.catalog[i].hasImage, fileOK {
                bundle.catalog[i].hasImage = true
            }
        }
    }

    private func normalizeTagArrayInBundle(_ s: inout V3Bundle) {
        if !s.inventoryTags.isEmpty {
            normalizeOneTagArrayInPlace(&s.inventoryTags)
        }
        if !s.shoppingTags.isEmpty {
            normalizeOneTagArrayInPlace(&s.shoppingTags)
        }
    }

    private func normalizeOneTagArrayInPlace(_ tags: inout [Tag]) {
        guard !tags.isEmpty else { return }
        if tags.allSatisfy({ $0.sortOrder == 0 }) {
            for i in tags.indices {
                tags[i].sortOrder = i
            }
        } else {
            tags.sort {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            for i in tags.indices {
                tags[i].sortOrder = i
            }
        }
    }

    private func migrateUnsortedOnSide(_ s: inout V3Bundle, hebrew: Bool) {
        var changed = false
        for i in s.inventoryTags.indices {
            let t = s.inventoryTags[i].title.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.caseInsensitiveCompare("Unsorted") == .orderedSame {
                s.inventoryTags[i].title = hebrew ? Tag.unsortedHebrewTitle : Tag.unsortedCanonicalTitle
                changed = true
            }
        }
        for i in s.shoppingTags.indices {
            let t = s.shoppingTags[i].title.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.caseInsensitiveCompare("Unsorted") == .orderedSame {
                s.shoppingTags[i].title = hebrew ? Tag.unsortedHebrewTitle : Tag.unsortedCanonicalTitle
                changed = true
            }
        }
        if changed {
            sortHebrewTagIfNeeded(&s, hebrew: hebrew)
        }
    }

    private func sortHebrewTagIfNeeded(_ s: inout V3Bundle, hebrew: Bool) {
        _ = hebrew
        s.inventoryTags.sort(by: tagSortPredicate)
        s.shoppingTags.sort(by: tagSortPredicate)
    }

    private func ensureUnsortedInSide(_ s: inout V3Bundle, hebrew: Bool) {
        if !s.inventoryTags.contains(where: { Tag.isUnsortedBucket($0) }) {
            let next = (s.inventoryTags.map(\.sortOrder).max() ?? -1) + 1
            s.inventoryTags.append(
                .init(
                    kind: .inventory,
                    title: hebrew ? Tag.unsortedHebrewTitle : Tag.unsortedCanonicalTitle,
                    sortOrder: next
                )
            )
        }
        if !s.shoppingTags.contains(where: { Tag.isUnsortedBucket($0) }) {
            let next = (s.shoppingTags.map(\.sortOrder).max() ?? -1) + 1
            s.shoppingTags.append(
                .init(
                    kind: .shopping,
                    title: hebrew ? Tag.unsortedHebrewTitle : Tag.unsortedCanonicalTitle,
                    sortOrder: next
                )
            )
        }
    }

    private func compactSortOrders(_ tags: inout [Tag]) {
        for i in tags.indices {
            tags[i].sortOrder = i
        }
    }

    // MARK: - v1 → English catalog

    private func repairOrphanedTagIds(in s: inout V3Bundle) {
        let defInv = s.inventoryTags.first(where: { Tag.isUnsortedBucket($0) })?.id
            ?? s.inventoryTags.first?.id
        let defShop = s.shoppingTags.first(where: { Tag.isUnsortedBucket($0) })?.id
            ?? s.shoppingTags.first?.id
        guard defInv != nil, defShop != nil else { return }
        for i in s.catalog.indices {
            if !s.inventoryTags.contains(where: { $0.id == s.catalog[i].inventoryTagID }) {
                s.catalog[i].inventoryTagID = defInv!
            }
            if !s.shoppingTags.contains(where: { $0.id == s.catalog[i].shoppingTagID }) {
                s.catalog[i].shoppingTagID = defShop!
            }
        }
    }

    private func migrateV1CatalogIfNeededForEnglish() {
        guard
            let legacyData = UserDefaults.standard.data(
                forKey: "grocery.catalog.v1.backup"
            ),
            let decodedV1 = try? decoder.decode([GroceryItemV1].self, from: legacyData)
        else {
            repairOrphanedTagIds(in: &english)
            return
        }

        let invByTitle = Dictionary(
            uniqueKeysWithValues: english.inventoryTags.map { ($0.title, $0.id) }
        )
        let shopByTitle = Dictionary(
            uniqueKeysWithValues: english.shoppingTags.map { ($0.title, $0.id) }
        )
        let defInv = englishUnsortedInventoryID
            ?? english.inventoryTags.first?.id
            ?? UUID()
        let defShop = englishUnsortedShoppingID
            ?? english.shoppingTags.first?.id
            ?? UUID()
        english.catalog = decodedV1.map { old in
            GroceryItem(
                id: old.id,
                name: old.name,
                inventoryTagID: invByTitle[old.inventorySection.title] ?? defInv,
                shoppingTagID: shopByTitle[old.shoppingSection.title] ?? defShop,
                sortOrder: 0
            )
        }
        normalizeCatalogSortOrders(in: &english)
        GroceryStore.sort(
            catalog: &english.catalog,
            usingInventoryTagOrder: english.inventoryTags
        )
        saveAllToDisk()
        UserDefaults.standard.removeObject(forKey: "grocery.catalog.v1.backup")
    }

    // MARK: - Load & save (v3)

    private func loadFromDiskOrLegacy() {
        // Phase 0a: library files are the primary copy. When none exist yet (first launch after
        // updating), fall through to UserDefaults below; `init` then saves, which creates the files.
        if loadFromLibraryFilesIfPresent() { return }
        let d = UserDefaults.standard
        if d.data(forKey: Self.v3EnglishKey) != nil
            || d.data(forKey: Self.v3HebrewKey) != nil
        {
            if let enData = d.data(forKey: Self.v3EnglishKey),
               let b = try? decoder.decode(V3Bundle.self, from: enData)
            {
                english = b
            } else {
                english = .empty
            }
            if let heData = d.data(forKey: Self.v3HebrewKey),
               let b = try? decoder.decode(V3Bundle.self, from: heData)
            {
                hebrew = b
            } else {
                hebrew = .empty
            }
            return
        }
        if let data = d.data(forKey: Self.legacyCatalogKey),
           let c = try? decoder.decode([GroceryItem].self, from: data)
        {
            english.catalog = c
        } else if let legacyData = d.data(forKey: "grocery.catalog.v1"),
                  let decodedV1 = try? decoder.decode([GroceryItemV1].self, from: legacyData)
        {
            english.catalog = decodedV1.map {
                GroceryItem(
                    id: $0.id,
                    name: $0.name,
                    inventoryTagID: UUID(),
                    shoppingTagID: UUID(),
                    sortOrder: 0
                )
            }
            UserDefaults.standard.set(legacyData, forKey: "grocery.catalog.v1.backup")
        }
        if let data = d.data(forKey: Self.legacyInventoryTagsKey),
           let t = try? decoder.decode([Tag].self, from: data)
        {
            english.inventoryTags = t
        }
        if let data = d.data(forKey: Self.legacyShoppingTagsKey),
           let t = try? decoder.decode([Tag].self, from: data)
        {
            english.shoppingTags = t
        }
        if let data = d.data(forKey: Self.legacyShoppingKey),
           let t = try? decoder.decode([ShoppingEntry].self, from: data)
        {
            english.shopping = t
        }
        hebrew = .empty
    }

    /// Loads both languages from the library files. Returns `false` when neither file exists yet.
    private func loadFromLibraryFilesIfPresent() -> Bool {
        let englishFile = LibraryFileStore.load(.english)
        let hebrewFile = LibraryFileStore.load(.hebrew)
        guard englishFile != nil || hebrewFile != nil else { return false }
        english = loadBundle(fileData: englishFile, language: .english, defaultsKey: Self.v3EnglishKey)
        hebrew = loadBundle(fileData: hebrewFile, language: .hebrew, defaultsKey: Self.v3HebrewKey)
        return true
    }

    /// One language: file first, UserDefaults copy as the fallback.
    private func loadBundle(fileData: Data?, language: AppContentLanguage, defaultsKey: String) -> V3Bundle {
        let defaultsData = UserDefaults.standard.data(forKey: defaultsKey)
        // While dual-writing (1.2), both copies hold identical bytes. A *different* UserDefaults copy
        // means an older build (e.g. 1.1 installed over this one while testing) saved after us —
        // trust that newer copy. Remove this check together with the dual-write in 1.3.
        if let defaultsData, defaultsData != fileData,
           let bundle = try? decoder.decode(V3Bundle.self, from: defaultsData)
        {
            return bundle
        }
        if let fileData {
            if let bundle = try? decoder.decode(V3Bundle.self, from: fileData) {
                return bundle
            }
            // Unreadable file: keep it for recovery instead of overwriting it on the next save.
            LibraryFileStore.setAsideUnreadableFile(language)
        }
        if let defaultsData, let bundle = try? decoder.decode(V3Bundle.self, from: defaultsData) {
            return bundle
        }
        return .empty
    }

    private func saveAllToDisk() {
        if let d = try? encoder.encode(english) {
            LibraryFileStore.save(d, for: .english)
            // Dual-write fallback for 1.2 (keeps the old copy current). Remove in 1.3.
            UserDefaults.standard.set(d, forKey: Self.v3EnglishKey)
        }
        if let d = try? encoder.encode(hebrew) {
            LibraryFileStore.save(d, for: .hebrew)
            // Dual-write fallback for 1.2 (keeps the old copy current). Remove in 1.3.
            UserDefaults.standard.set(d, forKey: Self.v3HebrewKey)
        }
        ShareExtensionAppGroupSupport.writeCatalogSnapshotToAppGroup(englishCatalog: english.catalog, hebrewCatalog: hebrew.catalog)
    }

    private func removeLegacyUserDefaultsKeysIfMigrated() {
        if UserDefaults.standard.data(forKey: Self.v3EnglishKey) == nil { return }
        if UserDefaults.standard.data(forKey: Self.v3HebrewKey) == nil { return }
        let d = UserDefaults.standard
        d.removeObject(forKey: Self.legacyCatalogKey)
        d.removeObject(forKey: Self.legacyInventoryTagsKey)
        d.removeObject(forKey: Self.legacyShoppingTagsKey)
        d.removeObject(forKey: Self.legacyShoppingKey)
    }

    private func ensureDefaultTagsForEnglishIfNeeded() {
        if english.inventoryTags.isEmpty {
            var list: [Tag] = []
            for (i, title) in BilingualSeedCatalog.defaultEnglishInventoryGroupTitles.enumerated() {
                list.append(Tag(kind: .inventory, title: title, sortOrder: i))
            }
            list.append(
                Tag(
                    kind: .inventory,
                    title: Tag.unsortedCanonicalTitle,
                    sortOrder: list.count
                )
            )
            english.inventoryTags = list
        }
        if english.shoppingTags.isEmpty {
            var list: [Tag] = []
            for (i, title) in BilingualSeedCatalog.defaultEnglishShoppingGroupTitles.enumerated() {
                list.append(Tag(kind: .shopping, title: title, sortOrder: i))
            }
            list.append(
                Tag(
                    kind: .shopping,
                    title: Tag.unsortedCanonicalTitle,
                    sortOrder: list.count
                )
            )
            english.shoppingTags = list
        }
        sortSideTagsInPlace(&english)
    }

    private func ensureDefaultTagsForHebrewIfNeeded() {
        if hebrew.inventoryTags.isEmpty {
            var list: [Tag] = []
            for (i, title) in BilingualSeedCatalog.defaultHebrewInventoryGroupTitles.enumerated() {
                list.append(Tag(kind: .inventory, title: title, sortOrder: i))
            }
            list.append(
                Tag(
                    kind: .inventory,
                    title: Tag.unsortedHebrewTitle,
                    sortOrder: list.count
                )
            )
            hebrew.inventoryTags = list
        }
        if hebrew.shoppingTags.isEmpty {
            var list: [Tag] = []
            for (i, title) in BilingualSeedCatalog.defaultHebrewShoppingGroupTitles.enumerated() {
                list.append(Tag(kind: .shopping, title: title, sortOrder: i))
            }
            list.append(
                Tag(
                    kind: .shopping,
                    title: Tag.unsortedHebrewTitle,
                    sortOrder: list.count
                )
            )
            hebrew.shoppingTags = list
        }
        sortSideTagsInPlace(&hebrew)
    }

    private func sortSideTagsInPlace(_ s: inout V3Bundle) {
        s.inventoryTags.sort(by: tagSortPredicate)
        s.shoppingTags.sort(by: tagSortPredicate)
    }

    private func seedEnglishCatalog() {
        let invBy = Dictionary(
            uniqueKeysWithValues: english.inventoryTags.map { ($0.title, $0.id) }
        )
        let shopBy = Dictionary(
            uniqueKeysWithValues: english.shoppingTags.map { ($0.title, $0.id) }
        )
        let defInv = englishUnsortedInventoryID ?? invBy[Tag.unsortedCanonicalTitle]!
        let defShop = englishUnsortedShoppingID ?? shopBy[Tag.unsortedCanonicalTitle]!
        english.catalog = BilingualSeedCatalog.englishSeedItems.map { seed in
            return GroceryItem(
                name: seed.name,
                inventoryTagID: invBy[seed.inventoryGroupTitle] ?? defInv,
                shoppingTagID: shopBy[seed.shoppingGroupTitle] ?? defShop,
                sortOrder: seed.inventoryOrder
            )
        }
        GroceryStore.sort(
            catalog: &english.catalog,
            usingInventoryTagOrder: english.inventoryTags
        )
    }

    private func seedHebrewCatalog() {
        let invBy = Dictionary(
            uniqueKeysWithValues: hebrew.inventoryTags.map { ($0.title, $0.id) }
        )
        let shopBy = Dictionary(
            uniqueKeysWithValues: hebrew.shoppingTags.map { ($0.title, $0.id) }
        )
        let defInv = hebrewUnsortedInventoryID ?? invBy[Tag.unsortedHebrewTitle]!
        let defShop = hebrewUnsortedShoppingID ?? shopBy[Tag.unsortedHebrewTitle]!
        hebrew.catalog = BilingualSeedCatalog.hebrewSeedItems.map { seed in
            return GroceryItem(
                name: seed.name,
                inventoryTagID: invBy[seed.inventoryGroupTitle] ?? defInv,
                shoppingTagID: shopBy[seed.shoppingGroupTitle] ?? defShop,
                sortOrder: seed.inventoryOrder
            )
        }
        GroceryStore.sort(
            catalog: &hebrew.catalog,
            usingInventoryTagOrder: hebrew.inventoryTags
        )
    }

    // MARK: - Library backup (one language, zip with library.txt + images)

    func exportLibraryBackup(for language: AppContentLanguage) throws -> URL {
        switch language {
        case .hebrew:
            return try LibraryBackupArchive.exportZip(
                language: language,
                catalog: hebrew.catalog,
                inventoryTags: hebrew.inventoryTags,
                shoppingTags: hebrew.shoppingTags,
                recipes: hebrew.recipes
            )
        case .english:
            return try LibraryBackupArchive.exportZip(
                language: language,
                catalog: english.catalog,
                inventoryTags: english.inventoryTags,
                shoppingTags: english.shoppingTags,
                recipes: english.recipes
            )
        }
    }

    /// Replaces library items, tags, and recipes for the given language, clears shopping list, restores images.
    /// Returns the number of recipe ingredient rows skipped because the item name was not in the library.
    @discardableResult
    func importLibraryBackup(from zipURL: URL, into language: AppContentLanguage) throws -> Int {
        let payload = try LibraryBackupArchive.loadImportPayload(from: zipURL, expectedLanguage: language)
        defer {
            if let imagesDirectoryURL = payload.imagesDirectoryURL {
                try? FileManager.default.removeItem(at: imagesDirectoryURL)
            }
        }
        return try applyImportedLibrary(payload, into: language)
    }

    @discardableResult
    private func applyImportedLibrary(
        _ payload: LibraryBackupArchive.ImportPayload,
        into language: AppContentLanguage
    ) throws -> Int {
        let parsed = payload.parsed

        func buildLibrary(
            rows: [LibraryBackupCodec.ParsedLibraryBackup.Row],
            invTags: [Tag],
            shopTags: [Tag]
        ) throws -> [GroceryItem] {
            let invMap = Dictionary(uniqueKeysWithValues: invTags.map { ($0.title.lowercased(), $0.id) })
            let shopMap = Dictionary(uniqueKeysWithValues: shopTags.map { ($0.title.lowercased(), $0.id) })
            return try rows.map { row in
                guard let iid = invMap[row.inventoryGroup.lowercased()] else {
                    throw LibraryBackupCodec.BackupError.unknownInventoryGroup(itemLine: -1, title: row.inventoryGroup)
                }
                guard let sid = shopMap[row.shoppingGroup.lowercased()] else {
                    throw LibraryBackupCodec.BackupError.unknownShoppingGroup(itemLine: -1, title: row.shoppingGroup)
                }
                return GroceryItem(
                    id: row.itemID,
                    name: row.name,
                    inventoryTagID: iid,
                    shoppingTagID: sid,
                    sortOrder: row.inventoryOrder,
                    hasImage: false
                )
            }
        }

        func buildRecipes(
            titles: [String],
            rows: [(recipeName: String, itemName: String, quantity: Int)],
            catalog: [GroceryItem]
        ) -> (recipes: [Recipe], skippedRows: Int) {
            let itemMap = Dictionary(
                catalog.map { ($0.name.lowercased(), $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
            var orderByTitle: [String: Int] = [:]
            for (offset, title) in titles.enumerated() {
                orderByTitle[title.lowercased()] = offset
            }
            var linesByRecipe: [String: [RecipeLine]] = [:]
            var skipped = 0
            for row in rows {
                guard let itemID = itemMap[row.itemName.lowercased()] else {
                    skipped += 1
                    continue
                }
                let key = row.recipeName.lowercased()
                var bucket = linesByRecipe[key] ?? []
                if let existingIndex = bucket.firstIndex(where: { $0.itemID == itemID }) {
                    bucket[existingIndex].quantity += row.quantity
                } else {
                    bucket.append(RecipeLine(id: UUID(), itemID: itemID, quantity: row.quantity))
                }
                linesByRecipe[key] = bucket
                if orderByTitle[key] == nil {
                    orderByTitle[key] = titles.count + orderByTitle.count
                }
            }
            var recipes: [Recipe] = []
            for (key, lines) in linesByRecipe where !lines.isEmpty {
                let displayName = titles.first { $0.lowercased() == key }
                    ?? rows.first { $0.recipeName.lowercased() == key }?.recipeName
                    ?? key
                let sortOrder = orderByTitle[key] ?? recipes.count
                recipes.append(
                    Recipe(
                        id: UUID(),
                        name: displayName,
                        sortOrder: sortOrder,
                        lines: lines
                    )
                )
            }
            recipes.sort {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            for i in recipes.indices {
                recipes[i].sortOrder = i
            }
            return (recipes, skipped)
        }

        func restoreImages(for catalog: [GroceryItem], in bundle: inout V3Bundle) throws {
            guard let imagesDirectoryURL = payload.imagesDirectoryURL else { return }
            let imageURLs = try LibraryBackupArchive.imageURLsByItemID(in: imagesDirectoryURL)
            let catalogIDs = Set(catalog.map(\.id))
            for (itemID, sourceURL) in imageURLs where catalogIDs.contains(itemID) {
                try ItemImageStore.importImage(from: sourceURL, forItemID: itemID)
            }
            normalizeItemImages(in: &bundle)
        }

        var skippedRecipeRows = 0

        switch language {
        case .hebrew:
            for id in hebrew.catalog.map(\.id) {
                ItemImageStore.delete(forItemID: id)
            }
            hebrew.inventoryTags = parsed.inventoryGroupTitles.enumerated().map {
                Tag(kind: .inventory, title: $0.element, sortOrder: $0.offset)
            }
            hebrew.shoppingTags = parsed.shoppingGroupTitles.enumerated().map {
                Tag(kind: .shopping, title: $0.element, sortOrder: $0.offset)
            }
            hebrew.catalog = try buildLibrary(rows: parsed.rows, invTags: hebrew.inventoryTags, shopTags: hebrew.shoppingTags)
            let builtRecipes = buildRecipes(
                titles: parsed.recipeTitles,
                rows: parsed.recipeItemRows,
                catalog: hebrew.catalog
            )
            hebrew.recipes = builtRecipes.recipes
            skippedRecipeRows = builtRecipes.skippedRows
            hebrew.shopping.removeAll()
            try restoreImages(for: hebrew.catalog, in: &hebrew)
            normalizeTagArrayInBundle(&hebrew)
            repairOrphanedTagIds(in: &hebrew)
            normalizeCatalogSortOrders(in: &hebrew)
            sortSideTagsInPlace(&hebrew)
            sortCatalog(for: .hebrew)
        case .english:
            for id in english.catalog.map(\.id) {
                ItemImageStore.delete(forItemID: id)
            }
            english.inventoryTags = parsed.inventoryGroupTitles.enumerated().map {
                Tag(kind: .inventory, title: $0.element, sortOrder: $0.offset)
            }
            english.shoppingTags = parsed.shoppingGroupTitles.enumerated().map {
                Tag(kind: .shopping, title: $0.element, sortOrder: $0.offset)
            }
            english.catalog = try buildLibrary(rows: parsed.rows, invTags: english.inventoryTags, shopTags: english.shoppingTags)
            let builtRecipes = buildRecipes(
                titles: parsed.recipeTitles,
                rows: parsed.recipeItemRows,
                catalog: english.catalog
            )
            english.recipes = builtRecipes.recipes
            skippedRecipeRows = builtRecipes.skippedRows
            english.shopping.removeAll()
            try restoreImages(for: english.catalog, in: &english)
            normalizeTagArrayInBundle(&english)
            repairOrphanedTagIds(in: &english)
            normalizeCatalogSortOrders(in: &english)
            sortSideTagsInPlace(&english)
            sortCatalog(for: .english)
        }

        saveAllToDisk()
        syncPublishedFromActiveContentLanguage()
        return skippedRecipeRows
    }
}

private extension Array where Element == ShoppingEntry {
    /// Prefers an unchecked line; otherwise updates an existing checked line so Home quantity changes do not duplicate entries.
    func firstIndexForQuantityUpdate(itemID: UUID) -> Int? {
        if let idx = firstIndex(where: { $0.itemID == itemID && !$0.isChecked }) {
            return idx
        }
        return firstIndex(where: { $0.itemID == itemID })
    }
}
