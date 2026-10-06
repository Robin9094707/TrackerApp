import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct JSONImportFile {
    let name: String
    let data: Data
    var text: String { String(decoding: data, as: UTF8.self) }

    func object() throws -> Any {
        guard data.count <= ImportStorage.maximumSize else { throw APIError.message("Maximal 1 MB pro JSON-Datei.") }
        let parsed = try JSONSerialization.jsonObject(with: data)
        guard parsed is [String: Any] || parsed is [Any] else {
            throw APIError.message("Bitte ein JSON-Objekt oder eine JSON-Liste einfügen.")
        }
        return parsed
    }
}

struct LocalImportFile: Identifiable {
    let url: URL
    let size: Int
    let modified: Date
    var id: String { url.path }
}

enum ImportStorage {
    static let maximumSize = 1_048_576
    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var folder: URL { documents.appendingPathComponent("Imports", isDirectory: true) }

    static func prepare() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var directory = folder
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let guide = folder.appendingPathComponent("Import-Anleitung.txt")
        if !FileManager.default.fileExists(atPath: guide.path) {
            let text = "RJ Tracker: Lege Apple-Tracker-JSON oder Google secrets.json in diesen Ordner. In der App unter Einrichtung > JSON importieren > App-Ordner auswählen. Dateien werden erst nach deiner Bestätigung an deinen eigenen Server gesendet. Schlüsseldateien sind vertraulich; nach dem Import kannst du sie in Dateien löschen."
            try Data(text.utf8).write(to: guide, options: [.atomic, .completeFileProtection])
        }
    }

    /// Coordinated reading also handles iCloud/File Provider downloads. The picker copies first.
    static func read(_ url: URL) throws -> JSONImportFile {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var failure: NSError?
        var result: Result<JSONImportFile, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &failure) { coordinatedURL in
            result = Result {
                let values = try coordinatedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true else { throw APIError.message("Bitte eine Datei auswählen.") }
                guard (values.fileSize ?? 0) <= maximumSize else { throw APIError.message("Maximal 1 MB pro JSON-Datei.") }
                let data = try Data(contentsOf: coordinatedURL)
                let file = JSONImportFile(name: url.lastPathComponent, data: data)
                _ = try file.object()
                return file
            }
        }
        if let failure { throw failure }
        guard let result else { throw APIError.message("Die Datei konnte nicht geöffnet werden. Versuche Text einfügen oder den App-Ordner.") }
        return try result.get()
    }

    static func files() throws -> [LocalImportFile] {
        try prepare()
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        return try [documents, folder].flatMap { directory in
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        }.compactMap { url in
            guard ["json", "txt"].contains(url.pathExtension.lowercased()), url.lastPathComponent != "Import-Anleitung.txt" else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { return nil }
            return LocalImportFile(url: url, size: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast)
        }.sorted { $0.modified > $1.modified }
    }

    static func save(_ file: JSONImportFile) throws -> URL {
        _ = try file.object(); try prepare()
        let proposed = (file.name as NSString).deletingPathExtension
        let safe = proposed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || "-_ ".unicodeScalars.contains($0) }
        let stem = String(String.UnicodeScalarView(safe)).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = stem.isEmpty ? "Import" : String(stem.prefix(80))
        // Never overwrite an existing key file silently.
        var url = folder.appendingPathComponent(base + ".json")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(suffix).json"); suffix += 1
        }
        try file.data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

struct JSONDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Providers sometimes label JSON as generic data. Validate content after selection.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick; self.onCancel = onCancel
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) } else { onCancel() }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
    }
}
