import SwiftUI

/// A row that becomes several rows when it runs out of width.
///
/// SwiftUI has no flowing stack, and a dictated sentence is exactly the thing
/// that needs one: eight words fit on one line and fourteen do not, and
/// neither a fixed grid nor a single `HStack` can be told so.
struct WrapLayout: Layout {

    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 12
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(of: subviews, within: width)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, max(widest, 0)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(of: subviews, within: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = switch alignment {
            case .leading: bounds.minX
            case .trailing: bounds.maxX - row.width
            default: bounds.minX + (bounds.width - row.width) / 2
            }
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, within width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty, next > width {
                rows.append(row)
                row = Row()
                row.items = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.items.append(index)
                row.width = next
                row.height = max(row.height, size.height)
            }
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
