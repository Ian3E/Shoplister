import Foundation

/// Plain-text library backup for one `AppContentLanguage` (sections, items, recipes; images ship in the zip archive).
enum LibraryBackupCodec {
    static let formatVersion = 4
    static let minimumImportFormatVersion = 4
    static let libraryFileName = "library.txt"

    enum BackupError: LocalizedError {
        case missingFormatHeader
        case unsupportedFormat(Int)
        case languageMismatch(expected: AppContentLanguage, found: AppContentLanguage)
        case missingLanguageHeader
        case invalidLibraryHeader
        case invalidRecipeItemsHeader
        case wrongColumnCount(line: Int, expected: Int, got: Int)
        case emptyInventoryGroups
        case emptyShoppingGroups
        case unknownInventoryGroup(itemLine: Int, title: String)
        case unknownShoppingGroup(itemLine: Int, title: String)
        case emptyItemName(line: Int)
        case emptyRecipeName(line: Int)
        case invalidRecipeQuantity(line: Int)
        case invalidItemID(line: Int)

        var errorDescription: String? {
            switch self {
            case .missingFormatHeader:
                return LocalizedCopy.backupMissingFormatHeader(expectedVersion: formatVersion)
            case .unsupportedFormat(let v):
                return LocalizedCopy.backupUnsupportedFormat(v)
            case .languageMismatch(let expected, let found):
                return LocalizedCopy.backupLanguageMismatch(found: found.title, expected: expected.title)
            case .missingLanguageHeader:
                return LocalizedCopy.backupMissingLanguageHeader
            case .invalidLibraryHeader:
                return LocalizedCopy.backupInvalidLibraryHeader
            case .invalidRecipeItemsHeader:
                return LocalizedCopy.backupInvalidRecipeItemsHeader
            case .wrongColumnCount(let line, let expected, let got):
                return LocalizedCopy.backupWrongColumnCount(line: line, expected: expected, got: got)
            case .emptyInventoryGroups:
                return LocalizedCopy.backupEmptyInventoryGroups
            case .emptyShoppingGroups:
                return LocalizedCopy.backupEmptyShoppingGroups
            case .unknownInventoryGroup(let itemLine, let title):
                return LocalizedCopy.backupUnknownInventoryGroup(itemLine: itemLine, title: title)
            case .unknownShoppingGroup(let itemLine, let title):
                return LocalizedCopy.backupUnknownShoppingGroup(itemLine: itemLine, title: title)
            case .emptyItemName(let line):
                return LocalizedCopy.backupEmptyItemName(line: line)
            case .emptyRecipeName(let line):
                return LocalizedCopy.backupEmptyRecipeName(line: line)
            case .invalidRecipeQuantity(let line):
                return LocalizedCopy.backupInvalidRecipeQuantity(line: line)
            case .invalidItemID(let line):
                return LocalizedCopy.backupInvalidItemID(line: line)
            }
        }
    }

    struct ParsedLibraryBackup {
        let language: AppContentLanguage
        let inventoryGroupTitles: [String]
        let shoppingGroupTitles: [String]
        let rows: [Row]
        let recipeTitles: [String]
        let recipeItemRows: [(recipeName: String, itemName: String, quantity: Int)]

        struct Row: Equatable {
            let name: String
            let inventoryGroup: String
            let shoppingGroup: String
            let inventoryOrder: Int
            let itemID: UUID
        }
    }

    // MARK: - Export

    static func exportDocument(
        language: AppContentLanguage,
        catalog: [GroceryItem],
        inventoryTags: [Tag],
        shoppingTags: [Tag],
        recipes: [Recipe]
    ) -> String {
        var lines: [String] = []
        lines.append("# Shoplister library backup")
        lines.append("# format-version: \(formatVersion)")
        lines.append("# language: \(language.rawValue)")
        lines.append("#")
        lines.append("# Edit in any plain-text editor. Lines starting with # are comments.")
        lines.append("# Sections: [home_sections], [shopping_sections], [library], [recipes], [recipe_items].")
        lines.append("# Library item rows are TAB-separated: name, home_section, shopping_section, home_order, item_id.")
        lines.append("# Recipe item rows are TAB-separated: recipe_name, item_name, quantity.")
        lines.append("# Item photos are stored in the images/ folder next to this file (one JPEG per item_id).")
        lines.append("")

        lines.append("[home_sections]")
        for t in inventoryTags {
            lines.append(sanitizeSingleLine(t.title))
        }
        lines.append("")

        lines.append("[shopping_sections]")
        for t in shoppingTags {
            lines.append(sanitizeSingleLine(t.title))
        }
        lines.append("")

        lines.append("[library]")
        lines.append("name\thome_section\tshopping_section\thome_order\titem_id")
        for item in catalog {
            let invTitle = inventoryTags.first { $0.id == item.inventoryTagID }?.title
                ?? (language == .hebrew ? Tag.unsortedHebrewTitle : Tag.unsortedCanonicalTitle)
            let shopTitle = shoppingTags.first { $0.id == item.shoppingTagID }?.title
                ?? (language == .hebrew ? Tag.unsortedHebrewTitle : Tag.unsortedCanonicalTitle)
            let row = [
                sanitizeFieldForTSV(item.name),
                sanitizeFieldForTSV(invTitle),
                sanitizeFieldForTSV(shopTitle),
                "\(max(0, item.sortOrder))",
                item.id.uuidString,
            ].joined(separator: "\t")
            lines.append(row)
        }
        lines.append("")

        let sortedRecipes = recipes.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        lines.append("[recipes]")
        for recipe in sortedRecipes {
            lines.append(sanitizeSingleLine(recipe.name))
        }
        lines.append("")

        lines.append("[recipe_items]")
        lines.append("recipe_name\titem_name\tquantity")
        for recipe in sortedRecipes {
            let recipeName = sanitizeFieldForTSV(recipe.name)
            for line in recipe.lines {
                guard let item = catalog.first(where: { $0.id == line.itemID }) else { continue }
                let row = [
                    recipeName,
                    sanitizeFieldForTSV(item.name),
                    "\(max(1, line.quantity))",
                ].joined(separator: "\t")
                lines.append(row)
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func sanitizeSingleLine(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeFieldForTSV(_ s: String) -> String {
        sanitizeSingleLine(s).replacingOccurrences(of: "\t", with: " ")
    }

    // MARK: - Import

    static func parseDocument(_ text: String, expectedLanguage: AppContentLanguage) throws -> ParsedLibraryBackup {
        var normalizedText = text
        if normalizedText.first == "\u{FEFF}" {
            normalizedText.removeFirst()
        }
        let rawLines = normalizedText.split(whereSeparator: \.isNewline).map(String.init)
        var metaFormat: Int?
        var metaLanguage: AppContentLanguage?
        var section: String?
        var invGroups: [String] = []
        var shopGroups: [String] = []
        var recipeTitles: [String] = []
        var libraryHeaderSeen = false
        var rows: [ParsedLibraryBackup.Row] = []
        var recipeItemsHeaderSeen = false
        var recipeItemRows: [(recipeName: String, itemName: String, quantity: Int)] = []

        func flushSectionLine(_ line: String) {
            let t = sanitizeSingleLine(line)
            guard !t.isEmpty else { return }
            switch section {
            case "home_sections": invGroups.append(t)
            case "shopping_sections": shopGroups.append(t)
            case "recipes": recipeTitles.append(t)
            default: break
            }
        }

        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if let v = parseMetaInt(body, prefix: "format-version:") {
                    metaFormat = v
                } else if let rawLang = parseMetaString(body, prefix: "language:") {
                    metaLanguage = AppContentLanguage(rawValue: rawLang.lowercased())
                }
                continue
            }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                section = String(trimmed.dropFirst().dropLast())
                if section == "library" {
                    libraryHeaderSeen = false
                }
                if section == "recipe_items" {
                    recipeItemsHeaderSeen = false
                }
                continue
            }
            guard let sec = section else { continue }

            if sec == "library" {
                if !libraryHeaderSeen {
                    if sanitizeSingleLine(trimmed).isEmpty { continue }
                    let cols = trimmed.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    let normalized = cols.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    let header = ["name", "home_section", "shopping_section", "home_order", "item_id"]
                    guard normalized.count == 5 && zip(normalized, header).allSatisfy({ $0 == $1 }) else {
                        throw BackupError.invalidLibraryHeader
                    }
                    libraryHeaderSeen = true
                    continue
                }
                if sanitizeSingleLine(trimmed).isEmpty { continue }
                let cols = trimmed.split(separator: "\t", omittingEmptySubsequences: false).map {
                    String($0).trimmingCharacters(in: .whitespaces)
                }
                let lineNumber = rows.count + 1
                guard cols.count == 5 else {
                    throw BackupError.wrongColumnCount(line: lineNumber, expected: 5, got: cols.count)
                }
                let name = cols[0]
                guard !name.isEmpty else { throw BackupError.emptyItemName(line: lineNumber) }
                guard let order = Int(cols[3].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw BackupError.wrongColumnCount(line: lineNumber, expected: 5, got: cols.count)
                }
                guard let itemID = UUID(uuidString: cols[4]) else {
                    throw BackupError.invalidItemID(line: lineNumber)
                }
                rows.append(
                    ParsedLibraryBackup.Row(
                        name: name,
                        inventoryGroup: cols[1],
                        shoppingGroup: cols[2],
                        inventoryOrder: max(0, order),
                        itemID: itemID
                    )
                )
            } else if sec == "recipe_items" {
                if !recipeItemsHeaderSeen {
                    if sanitizeSingleLine(trimmed).isEmpty { continue }
                    let cols = trimmed.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    let normalized = cols.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    let header = ["recipe_name", "item_name", "quantity"]
                    guard normalized.count == 3 && zip(normalized, header).allSatisfy({ $0 == $1 }) else {
                        throw BackupError.invalidRecipeItemsHeader
                    }
                    recipeItemsHeaderSeen = true
                    continue
                }
                if sanitizeSingleLine(trimmed).isEmpty { continue }
                let cols = trimmed.split(separator: "\t", omittingEmptySubsequences: false).map {
                    String($0).trimmingCharacters(in: .whitespaces)
                }
                let lineNumber = recipeItemRows.count + 1
                guard cols.count == 3 else {
                    throw BackupError.wrongColumnCount(line: lineNumber, expected: 3, got: cols.count)
                }
                let recipeName = cols[0]
                guard !recipeName.isEmpty else { throw BackupError.emptyRecipeName(line: lineNumber) }
                let itemName = cols[1]
                guard !itemName.isEmpty else { throw BackupError.emptyItemName(line: lineNumber) }
                guard let quantity = Int(cols[2].trimmingCharacters(in: .whitespacesAndNewlines)), quantity >= 1 else {
                    throw BackupError.invalidRecipeQuantity(line: lineNumber)
                }
                recipeItemRows.append((recipeName: recipeName, itemName: itemName, quantity: quantity))
            } else {
                flushSectionLine(trimmed)
            }
        }

        guard let v = metaFormat else { throw BackupError.missingFormatHeader }
        guard v >= minimumImportFormatVersion && v <= formatVersion else {
            throw BackupError.unsupportedFormat(v)
        }
        guard let fileLang = metaLanguage else { throw BackupError.missingLanguageHeader }
        guard fileLang == expectedLanguage else {
            throw BackupError.languageMismatch(expected: expectedLanguage, found: fileLang)
        }

        invGroups = prepareGroupTitles(invGroups, language: fileLang)
        shopGroups = prepareGroupTitles(shopGroups, language: fileLang)

        guard !invGroups.isEmpty else { throw BackupError.emptyInventoryGroups }
        guard !shopGroups.isEmpty else { throw BackupError.emptyShoppingGroups }

        let invSet = Set(invGroups.map { normalizeGroupTitle($0, language: fileLang).lowercased() })
        let shopSet = Set(shopGroups.map { normalizeGroupTitle($0, language: fileLang).lowercased() })

        for (i, row) in rows.enumerated() {
            let invN = normalizeGroupTitle(row.inventoryGroup, language: fileLang)
            let shopN = normalizeGroupTitle(row.shoppingGroup, language: fileLang)
            guard invSet.contains(invN.lowercased()) else {
                throw BackupError.unknownInventoryGroup(itemLine: i + 1, title: row.inventoryGroup)
            }
            guard shopSet.contains(shopN.lowercased()) else {
                throw BackupError.unknownShoppingGroup(itemLine: i + 1, title: row.shoppingGroup)
            }
        }

        let invNormalized = invGroups.map { normalizeGroupTitle($0, language: fileLang) }
        let shopNormalized = shopGroups.map { normalizeGroupTitle($0, language: fileLang) }

        let normalizedRows = rows.map { row in
            ParsedLibraryBackup.Row(
                name: normalizeField(row.name),
                inventoryGroup: normalizeGroupTitle(row.inventoryGroup, language: fileLang),
                shoppingGroup: normalizeGroupTitle(row.shoppingGroup, language: fileLang),
                inventoryOrder: row.inventoryOrder,
                itemID: row.itemID
            )
        }

        let normalizedRecipeTitles = dedupePreservingOrder(
            recipeTitles.map { sanitizeSingleLine($0) }.filter { !$0.isEmpty }
        )
        let normalizedRecipeItemRows = recipeItemRows.map { row in
            (
                recipeName: normalizeField(row.recipeName),
                itemName: normalizeField(row.itemName),
                quantity: max(1, row.quantity)
            )
        }

        return ParsedLibraryBackup(
            language: fileLang,
            inventoryGroupTitles: invNormalized,
            shoppingGroupTitles: shopNormalized,
            rows: normalizedRows,
            recipeTitles: normalizedRecipeTitles,
            recipeItemRows: normalizedRecipeItemRows
        )
    }

    private static func dedupePreservingOrder(_ titles: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in titles {
            let k = t.lowercased()
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            out.append(t)
        }
        return out
    }

    private static func prepareGroupTitles(_ titles: [String], language: AppContentLanguage) -> [String] {
        var t = dedupePreservingOrder(titles.map { sanitizeSingleLine($0) }.filter { !$0.isEmpty })
        if !t.contains(where: { Tag.isUnsortedCanonicalTitle($0) }) {
            t.insert(language == .hebrew ? Tag.unsortedHebrewTitle : Tag.unsortedCanonicalTitle, at: 0)
        }
        return t
    }

    private static func normalizeField(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeGroupTitle(_ raw: String, language: AppContentLanguage) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if Tag.isUnsortedCanonicalTitle(t) {
            return language == .hebrew ? Tag.unsortedHebrewTitle : Tag.unsortedCanonicalTitle
        }
        return t
    }

    private static func parseMetaInt(_ body: String, prefix: String) -> Int? {
        guard body.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        let rest = body.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return Int(rest)
    }

    private static func parseMetaString(_ body: String, prefix: String) -> String? {
        guard body.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        return String(body.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}
