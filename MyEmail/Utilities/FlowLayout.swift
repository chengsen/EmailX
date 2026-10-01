//
//  FlowLayout.swift
//  MyEmail
//
//  Horizontal wrap layout (flex-wrap: wrap). Shared across views.
//

import SwiftUI

// Ponytail: retain this geometry helper until SwiftUI provides a native wrapping
// container that preserves attachment and recipient actions and accessibility.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let rows = computeRows(proposal: ProposedViewSize(width: width, height: nil), subviews: subviews)
        guard !rows.isEmpty else { return .zero }
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height }
            + CGFloat(rows.count - 1) * spacing
        return CGSize(width: width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        var y = bounds.minY
        var subviewIndex = 0
        for row in rows {
            var x = bounds.minX
            for _ in 0..<row.count {
                let size = subviews[subviewIndex].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[subviewIndex].place(at: CGPoint(x: x, y: y),
                                            proposal: ProposedViewSize(size))
                x += size.width + spacing
                subviewIndex += 1
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var count: Int
        var height: CGFloat
        var width: CGFloat
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        var currentCount = 0

        for subview in subviews {
            // Constrain long filenames and recipients using the same width
            // contract during measurement and placement.
            let size = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            if currentCount > 0 && currentWidth + spacing + size.width > maxWidth {
                rows.append(Row(count: currentCount, height: currentHeight, width: currentWidth))
                currentWidth = size.width
                currentHeight = size.height
                currentCount = 1
            } else {
                currentWidth += (currentCount > 0 ? spacing : 0) + size.width
                currentHeight = max(currentHeight, size.height)
                currentCount += 1
            }
        }
        if currentCount > 0 {
            rows.append(Row(count: currentCount, height: currentHeight, width: currentWidth))
        }
        return rows
    }
}
