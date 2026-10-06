import SwiftUI

/// A card: a rounded surface with a hairline edge and no shadow.
///
/// The hairline does the separating a shadow would otherwise do, which is why
/// the interface stays flat and quiet.
struct CardSurface: ViewModifier {
    var padding: CGFloat = Metrics.cardPadding
    var isEmphasised: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(
                        isEmphasised ? Palette.selection.opacity(0.55) : Palette.separator,
                        lineWidth: isEmphasised ? 1.5 : 1
                    )
            }
    }
}

extension View {
    func cardSurface(padding: CGFloat = Metrics.cardPadding, isEmphasised: Bool = false) -> some View {
        modifier(CardSurface(padding: padding, isEmphasised: isEmphasised))
    }

    /// Standard page padding. Applied by every screen so nothing drifts.
    func pageInsets() -> some View {
        padding(.horizontal, Metrics.gutter)
            .padding(.vertical, Metrics.pageTop)
    }
}

/// A quiet rule above a group of content.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Rows stacked inside one card with hairlines between them, the way grouped
/// lists look in System Settings.
struct GroupedRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.separator, lineWidth: 1)
        }
    }
}

/// One row inside `GroupedRows`. The divider stops short of the left edge,
/// which is the difference between a grouped list and a stack of boxes.
struct GroupedRow<Content: View>: View {
    var showsDivider: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.vertical, 11)
            if showsDivider {
                Divider().padding(.leading, Metrics.cardPadding)
            }
        }
    }
}

/// A number and what it counts, as used in the day's summary.
///
/// Zero is shown as a dash: a row of noughts reads as a broken screen, while a
/// dash reads as "nothing here today", which is the truth.
struct StatTile: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value > 0 ? "\(value)" : "—")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(value > 0 ? Palette.primaryText : Palette.tertiaryText)
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// The title block at the top of a sheet.
struct SheetHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.top, Metrics.cardPadding)
        .padding(.bottom, 4)
    }
}

/// The row of buttons at the foot of a sheet.
struct SheetActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            content
        }
        .padding(Metrics.cardPadding)
    }
}
