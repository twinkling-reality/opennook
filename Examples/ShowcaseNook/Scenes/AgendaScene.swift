// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookApp
import SwiftUI

enum AgendaPalette {
    static let today = Color(red: 1.00, green: 0.62, blue: 0.30)
}

/// A month at a glance beside today's schedule. The calendar is the real current month; the
/// events are sample data drawn at a fixed time of day (`SampleAgenda.now`).
struct AgendaHome: View {
    @Environment(\.nookContentInsets) private var insets

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            MiniMonth(today: Date())
                .frame(width: 176)
            ColumnRule()
                .frame(height: 190)
            DaySchedule(today: Date(), now: SampleAgenda.now, events: SampleAgenda.events)
        }
        .padding(.top, 2)
        .padding(.bottom, max(insets.bottom, 6))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MiniMonth: View {
    let today: Date
    @Environment(\.nookResolvedTheme) private var theme

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    /// The month's days in rows of seven, with `nil` padding before the first and after the last.
    private var weeks: [[Int?]] {
        let calendar = calendar
        guard let interval = calendar.dateInterval(of: .month, for: today),
            let days = calendar.range(of: .day, in: .month, for: today)
        else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    var body: some View {
        let day = calendar.component(.day, from: today)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(today, format: .dateTime.month(.wide))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryLabel)
                Text(today, format: .dateTime.year())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.tertiaryLabel)
                Spacer()
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
                    .padding(.leading, 6)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(theme.tertiaryLabel)

            Grid(horizontalSpacing: 0, verticalSpacing: 3) {
                GridRow {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { index in
                        Text(["M", "T", "W", "T", "F", "S", "S"][index])
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(theme.quaternaryLabel)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(weeks.indices, id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            DayCell(
                                number: weeks[row][column],
                                isToday: weeks[row][column] == day,
                                isWeekend: column >= 5
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let number: Int?
    let isToday: Bool
    let isWeekend: Bool
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(spacing: 1) {
            if let number {
                Text("\(number)")
                    .font(.system(size: 11, weight: isToday ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(
                        isToday ? Color.black : (isWeekend ? theme.tertiaryLabel : theme.secondaryLabel)
                    )
                    .frame(width: 21, height: 21)
                    .background {
                        if isToday {
                            Circle().fill(AgendaPalette.today)
                        }
                    }
                Circle()
                    .fill(SampleAgenda.busyDays.contains(number) && !isToday ? theme.tertiaryLabel : .clear)
                    .frame(width: 3, height: 3)
            } else {
                Color.clear.frame(width: 21, height: 25)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DaySchedule: View {
    let today: Date
    let now: Int
    let events: [AgendaEvent]
    @Environment(\.nookResolvedTheme) private var theme

    private var next: AgendaEvent? { events.first { $0.start > now } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(today, format: .dateTime.weekday(.wide))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryLabel)
                Text(today, format: .dateTime.day().month(.wide))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.tertiaryLabel)
                Spacer()
                if let next {
                    Text("Next in \(Format.span(next.start - now))")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(theme.secondaryLabel)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(theme.subtleFill))
                }
            }
            .padding(.horizontal, 8)
            VStack(spacing: 4) {
                ForEach(events) { event in
                    EventRow(event: event, now: now)
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: AgendaEvent
    let now: Int
    @Environment(\.nookResolvedTheme) private var theme

    private var isDone: Bool { event.end <= now }
    private var isNow: Bool { event.start <= now && now < event.end }

    private var place: (symbol: String, label: String) {
        switch event.kind {
            case .call: ("video.fill", "Video call")
            case .room(let room): ("mappin.and.ellipse", room)
            case .focus: ("moon.fill", "Focus")
            case .personal(let place): ("figure.climbing", place)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(event.tint.opacity(isDone ? 0.4 : 1))
                .frame(width: 3.5)
                .padding(.vertical, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isDone ? theme.tertiaryLabel : theme.primaryLabel)
                    .strikethrough(isDone, color: theme.quaternaryLabel)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text("\(Format.time(event.start)) - \(Format.time(event.end))")
                        .monospacedDigit()
                    Image(systemName: place.symbol)
                        .font(.system(size: 8.5, weight: .semibold))
                        .padding(.leading, 3)
                    Text(place.label)
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(theme.tertiaryLabel)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background {
            if isNow {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(event.tint.opacity(0.14))
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isNow {
            Text(Format.span(event.end - now) + " left")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.tertiaryLabel)
            Text("Now")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(event.tint))
        } else if isDone {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.quaternaryLabel)
        } else {
            Text("in " + Format.span(event.start - now))
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.tertiaryLabel)
        }
    }
}

/// The next event beside the notch: a dot in its color and how long until it starts.
struct CompactNextEvent: View {
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        if let next = SampleAgenda.events.first(where: { $0.start > SampleAgenda.now }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(next.tint)
                    .frame(width: 6, height: 6)
                Text(Format.span(next.start - SampleAgenda.now))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.primaryLabel)
            }
            .frame(height: 24)
        }
    }
}
