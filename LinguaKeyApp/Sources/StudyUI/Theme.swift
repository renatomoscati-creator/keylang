import SwiftUI

/// One place for the handful of values that must look the same in the app and in
/// the share sheet, because the share sheet is a different process and a
/// different presentation and the two drift within a week otherwise.
public enum Theme {
    public static let cardCorner: CGFloat = 14
    public static let gutter: CGFloat = 16

    /// The focus word inside the sentence. Underline rather than a highlight
    /// block: the sentence is the user's own text and it should still read as
    /// their text.
    public static let focusTint = Color.accentColor

    public static func card() -> some View {
        RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
            .fill(.background.secondary)
    }
}

public extension View {
    func studyCard() -> some View {
        padding(Theme.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card())
    }
}
