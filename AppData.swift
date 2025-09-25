import Combine
import SwiftUI

// User-selectable note head styles
enum NoteHeadStyle: String, CaseIterable, Identifiable, Hashable {
    case whole
    case half
    case quarter

    var id: String { rawValue }
}

// Centralized app data for user preferences
final class AppData: ObservableObject {
    @Published var noteHeadStyle: NoteHeadStyle {
        didSet {
            UserDefaults.standard.set(noteHeadStyle.rawValue, forKey: Self.noteHeadStyleKey)
        }
    }

    private static let noteHeadStyleKey = "noteHeadStyle"

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.noteHeadStyleKey)
            ?? NoteHeadStyle.whole.rawValue
        self.noteHeadStyle = NoteHeadStyle(rawValue: raw) ?? .whole
    }
}
