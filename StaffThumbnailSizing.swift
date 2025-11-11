import SwiftUI

/// Shared sizing for staff thumbnails used in statistics views (History and Practice Results).
/// Matches the visual scale of PracticeNoteResultRow which draws at 320pt tall.
public struct StaffThumbnailSizing {
    /// Preferred width for thumbnail containers. Width does not affect glyph scale (height does),
    /// but keeping a consistent width improves layout alignment next to text.
    public static let width: CGFloat = 300
    /// Height must be 320 to match PracticeNoteResultRow's Canvas height so the scale factor is 1.0.
    public static let height: CGFloat = 320
}
