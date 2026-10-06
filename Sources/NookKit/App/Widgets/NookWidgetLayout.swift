// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// Where widgets go on a grid: in order, row by row, each at the first place it fits at or
/// after the one before it. Nothing moves back to fill a gap, so the reading order is the
/// order given and resizing one widget never jumps another ahead of it.
enum NookWidgetLayout {
    /// A widget's cell: its top-left column and row, and its span, clamped to the grid.
    struct Cell: Equatable {
        var column: Int
        var row: Int
        var columns: Int
        var rows: Int
    }

    /// The cells for `sizes`, in the same order, on a grid `columns` wide, and the rows used.
    static func place(_ sizes: [NookWidgetSize], columns: Int) -> (cells: [Cell], rows: Int) {
        let columns = max(columns, 1)
        var taken: [[Bool]] = []
        var cells: [Cell] = []
        // The earliest place the next widget may start: right after the last one's start.
        var cursor = (row: 0, column: 0)

        func isFree(_ row: Int, _ column: Int, _ span: (columns: Int, rows: Int)) -> Bool {
            guard column + span.columns <= columns else { return false }
            for r in row..<(row + span.rows) where r < taken.count {
                for c in column..<(column + span.columns) where taken[r][c] { return false }
            }
            return true
        }

        for size in sizes {
            let span = (columns: min(max(size.columns, 1), columns), rows: max(size.rows, 1))
            var row = cursor.row
            var column = cursor.column
            while !isFree(row, column, span) {
                column += 1
                if column + span.columns > columns {
                    column = 0
                    row += 1
                }
            }
            while taken.count < row + span.rows {
                taken.append(Array(repeating: false, count: columns))
            }
            for r in row..<(row + span.rows) {
                for c in column..<(column + span.columns) { taken[r][c] = true }
            }
            cells.append(Cell(column: column, row: row, columns: span.columns, rows: span.rows))
            cursor = column + span.columns < columns ? (row, column + span.columns) : (row + 1, 0)
        }
        return (cells, taken.count)
    }

    /// The height of `rows` rows of `rowHeight`, `gap` apart.
    static func height(rows: Int, rowHeight: CGFloat, gap: CGFloat) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * rowHeight + CGFloat(rows - 1) * gap
    }
}

/// The span a subview of ``NookWidgetGridLayout`` takes.
struct NookWidgetSpanKey: LayoutValueKey {
    static let defaultValue = NookWidgetSize.small
}

/// Lays its subviews out on a column grid with ``NookWidgetLayout``: each one gets the frame
/// of its cell. The width is the width offered, split into `columns` equal columns; the
/// height is the rows the widgets use.
struct NookWidgetGridLayout: Layout {
    var columns: Int
    var rowHeight: CGFloat
    var gap: CGFloat
    /// The column width when no width is offered: the grid then takes its ideal size.
    var idealColumnWidth: CGFloat = 116

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let placed = NookWidgetLayout.place(subviews.map { $0[NookWidgetSpanKey.self] }, columns: columns)
        let width = proposal.width ?? idealWidth
        return CGSize(width: width, height: NookWidgetLayout.height(rows: placed.rows, rowHeight: rowHeight, gap: gap))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = NookWidgetLayout.place(subviews.map { $0[NookWidgetSpanKey.self] }, columns: columns)
        let columnCount = CGFloat(max(columns, 1))
        let columnWidth: CGFloat = max((bounds.width - gap * (columnCount - 1)) / columnCount, 0)
        for (subview, cell) in zip(subviews, placed.cells) {
            let x: CGFloat = bounds.minX + CGFloat(cell.column) * (columnWidth + gap)
            let y: CGFloat = bounds.minY + CGFloat(cell.row) * (rowHeight + gap)
            let width: CGFloat = CGFloat(cell.columns) * columnWidth + CGFloat(cell.columns - 1) * gap
            let height: CGFloat = NookWidgetLayout.height(rows: cell.rows, rowHeight: rowHeight, gap: gap)
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: height)
            )
        }
    }

    private var idealWidth: CGFloat {
        let columnCount = CGFloat(max(columns, 1))
        return columnCount * idealColumnWidth + (columnCount - 1) * gap
    }
}
