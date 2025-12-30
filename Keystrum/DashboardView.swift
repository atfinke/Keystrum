//
//  DashboardView.swift
//  Keystrum
//
//  Created by Andrew Finke on 12/29/25.
//

import SwiftUI
import Charts
import Combine
import KeystrumCore

struct DashboardView: View {
    @State private var flightTimeData: [DatabaseManager.KeystrokeData] = []
    @State private var topApps: [DatabaseManager.AppUsage] = []
    @State private var recentSessions: [DatabaseManager.SessionInfo] = []
    @State private var analysis: FlightTimeAnalyzer.AnalysisResult?
    @State private var summaryStats: DatabaseManager.SummaryStats?
    @State private var dwellStats: DatabaseManager.DwellTimeStats?
    @State private var modifierStats: DatabaseManager.ModifierStats?
    @State private var topWindows: [DatabaseManager.WindowUsage] = []
    @State private var hourlyActivity: [DatabaseManager.HourlyActivity] = []
    @State private var topKeys: [DatabaseManager.KeyUsage] = []
    @State private var topWords: [DatabaseManager.WordUsage] = []
    @State private var clickHeatmap: [DatabaseManager.ClickZone] = []
    @State private var hourlySpeed: [DatabaseManager.HourlySpeed] = []
    @State private var editingStats: DatabaseManager.EditingStats?
    @State private var wordStats: DatabaseManager.WordStats?
    @State private var peakHours: [DatabaseManager.PeakHour] = []

    let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    let heartbeatTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    let dataUpdatePublisher = DistributedNotificationCenter.default().publisher(
        for: KeystrumConfig.dataUpdatedNotification
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with today's summary
                headerSection

                // Metric Cards Row
                metricsSection

                // Typing Rhythm Chart
                chartSection

                // First row - 3 columns
                HStack(alignment: .top, spacing: 12) {
                    appsSection
                    sessionsSection
                    activitySection
                }

                // Hourly Activity Chart
                hourlyActivitySection

                // Second row - more insights
                HStack(alignment: .top, spacing: 12) {
                    dwellTimeSection
                    modifierSection
                    topWindowsSection
                }

                // Third row - keys, words, clicks
                HStack(alignment: .top, spacing: 12) {
                    topKeysSection
                    topWordsSection
                    clickHeatmapSection
                }

                // Speed over time chart
                speedOverTimeSection

                // Fourth row - editing, word stats, peak hours
                HStack(alignment: .top, spacing: 12) {
                    editingStatsSection
                    wordStatsSection
                    peakHoursSection
                }

                // Explanations section at the bottom
                explanationsSection
            }
            .padding(24)
        }
        .frame(minWidth: 900, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshData()
            sendDashboardHeartbeat()
        }
        .onReceive(timer) { _ in refreshData() }
        .onReceive(heartbeatTimer) { _ in sendDashboardHeartbeat() }
        .onReceive(dataUpdatePublisher) { _ in refreshData() }
    }

    /// Signals to the agent that the dashboard is actively viewing data
    private func sendDashboardHeartbeat() {
        DistributedNotificationCenter.default().postNotificationName(
            KeystrumConfig.dashboardActiveNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keystrum")
                    .font(.system(size: 28, weight: .semibold))
                if let stats = summaryStats {
                    Text("\(formatNumber(stats.totalKeysToday)) keys  \(formatNumber(stats.clicksToday)) clicks today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let stats = summaryStats {
                HStack(spacing: 20) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(formatNumber(stats.totalKeysAllTime))")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                        Text("keys all time")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(formatNumber(stats.clicksAllTime))")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                        Text("clicks all time")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Metrics Section

    @ViewBuilder
    private var metricsSection: some View {
        if let state = analysis, state.activeSamples > 0 {
            HStack(spacing: 12) {
                MetricCard(
                    title: "Typing Speed",
                    value: "\(Int(state.meanFlightTime * 1000))ms",
                    subtitle: speedDescription(state.speed),
                    detail: "avg between keys",
                    accent: speedColor(state.speed),
                    progress: state.speed / 100.0
                )

                MetricCard(
                    title: "Rhythm",
                    value: String(format: "%.0f", state.consistency),
                    subtitle: consistencyDescription(state.consistency),
                    detail: "consistency score",
                    accent: consistencyColor(state.consistency),
                    progress: state.consistency / 100.0
                )

                MetricCard(
                    title: "Focus",
                    value: "\(state.score)",
                    subtitle: scoreDescription(state.score),
                    detail: "combined score",
                    accent: scoreColor(state.score),
                    progress: Double(state.score) / 100.0
                )

                MetricCard(
                    title: "Flow State",
                    value: state.isFlow ? "Active" : "No",
                    subtitle: state.isFlow ? "Fast & consistent" : "Not detected",
                    detail: state.isFlow ? "keep it up!" : "speed + rhythm needed",
                    accent: state.isFlow ? .cyan : .secondary
                )
            }
        } else {
            HStack(spacing: 12) {
                MetricCard(title: "Typing Speed", value: "—", subtitle: "No data", detail: "start typing", accent: .secondary)
                MetricCard(title: "Rhythm", value: "—", subtitle: "No data", detail: "consistency score", accent: .secondary)
                MetricCard(title: "Focus", value: "—", subtitle: "No data", detail: "combined score", accent: .secondary)
                MetricCard(title: "Flow State", value: "—", subtitle: "No data", detail: "speed + rhythm", accent: .secondary)
            }
        }
    }

    // MARK: - Chart Section

    @ViewBuilder
    private var chartSection: some View {
        SectionCard(title: "Typing Rhythm", subtitle: "Time between keystrokes — lower is faster, green line = 150ms (fast)") {
            if flightTimeData.isEmpty {
                ContentUnavailableView {
                    Label("No Data", systemImage: "keyboard")
                } description: {
                    Text("Start typing to see your rhythm")
                }
                .frame(height: 180)
            } else {
                // Filter to active typing only for the chart (< 500ms)
                let activeData = flightTimeData.filter { ($0.flightTime ?? 0) < 0.5 }

                if activeData.isEmpty {
                    Text("No active typing data")
                        .foregroundStyle(.secondary)
                        .frame(height: 180)
                } else {
                    // Group into segments - only connect points within 1s of each other
                    let segments = segmentData(activeData, maxGap: 1.0)

                    Chart {
                        // Reference line at 150ms (typical fast typing)
                        RuleMark(y: .value("Fast", 150))
                            .foregroundStyle(Color.green.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        // Draw each segment separately so lines don't connect across gaps
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            ForEach(segment) { item in
                                LineMark(
                                    x: .value("Time", Date(timeIntervalSince1970: item.timestamp)),
                                    y: .value("ms", (item.flightTime ?? 0) * 1000)
                                )
                                .foregroundStyle(Color.blue)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))

                                AreaMark(
                                    x: .value("Time", Date(timeIntervalSince1970: item.timestamp)),
                                    y: .value("ms", (item.flightTime ?? 0) * 1000)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                        }
                    }
                    .chartYScale(domain: 0...500)
                    .chartYAxis {
                        AxisMarks(values: [0, 150, 300, 500]) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.primary.opacity(0.08))
                            AxisValueLabel {
                                if let ms = value.as(Int.self) {
                                    Text("\(ms)")
                                        .font(.caption2)
                                        .foregroundStyle(ms == 150 ? .green : .secondary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.primary.opacity(0.08))
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    /// Segments data into groups where consecutive points are within maxGap seconds
    private func segmentData(_ data: [DatabaseManager.KeystrokeData], maxGap: Double) -> [[DatabaseManager.KeystrokeData]] {
        guard !data.isEmpty else { return [] }

        var segments: [[DatabaseManager.KeystrokeData]] = []
        var current: [DatabaseManager.KeystrokeData] = [data[0]]

        for i in 1..<data.count {
            let gap = data[i].timestamp - data[i-1].timestamp
            if gap > maxGap {
                if current.count >= 2 {
                    segments.append(current)
                }
                current = [data[i]]
            } else {
                current.append(data[i])
            }
        }

        if current.count >= 2 {
            segments.append(current)
        }

        return segments
    }

    // MARK: - Apps Section

    @ViewBuilder
    private var appsSection: some View {
        SectionCard(title: "Keystrokes by App", subtitle: "Where you've been typing") {
            if topApps.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            } else {
                let maxCount = topApps.map(\.count).max() ?? 1
                VStack(spacing: 0) {
                    ForEach(Array(topApps.enumerated()), id: \.element.id) { index, app in
                        VStack(spacing: 5) {
                            HStack {
                                Text(app.name)
                                    .font(.system(.callout))
                                    .lineLimit(1)
                                Spacer()
                                Text(formatNumber(app.count))
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.blue.opacity(0.5))
                                    .frame(width: geo.size.width * (Double(app.count) / Double(maxCount)), height: 3)
                            }
                            .frame(height: 3)
                        }
                        .padding(.vertical, 6)
                        if index < topApps.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sessions Section

    @ViewBuilder
    private var sessionsSection: some View {
        SectionCard(title: "Recent Sessions", subtitle: "30s inactivity = new session") {
            if recentSessions.isEmpty {
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentSessions.prefix(4).enumerated()), id: \.element.id) { index, session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatSessionTime(session.startTime))
                                    .font(.system(.callout))
                                Text(formatDuration(session.duration))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text("\(formatNumber(session.keyCount))")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        if index < min(recentSessions.count, 4) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Activity Section (Clicks + Ratio)

    @ViewBuilder
    private var activitySection: some View {
        SectionCard(title: "Input Activity", subtitle: "Keys vs clicks today") {
            if let stats = summaryStats, stats.totalKeysToday > 0 || stats.clicksToday > 0 {
                VStack(spacing: 12) {
                    // Keys to clicks ratio
                    let total = stats.totalKeysToday + stats.clicksToday
                    let keyRatio = total > 0 ? Double(stats.totalKeysToday) / Double(total) : 0.5

                    VStack(spacing: 4) {
                        HStack {
                            Text("Keys")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Spacer()
                            Text("Clicks")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: geo.size.width * keyRatio)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.orange.opacity(0.7))
                                    .frame(width: geo.size.width * (1 - keyRatio))
                            }
                        }
                        .frame(height: 8)
                        HStack {
                            Text("\(Int(keyRatio * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((1 - keyRatio) * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Stats breakdown
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("\(formatNumber(stats.totalKeysToday))", systemImage: "keyboard")
                                .font(.callout)
                            Text("keystrokes")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Label("\(formatNumber(stats.clicksToday))", systemImage: "cursorarrow.click.2")
                                .font(.callout)
                            Text("clicks")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if stats.sessionsToday > 0 {
                        Divider()
                        HStack {
                            Text("\(stats.sessionsToday) session\(stats.sessionsToday == 1 ? "" : "s") today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            } else {
                Text("No activity yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hourly Activity Section

    @ViewBuilder
    private var hourlyActivitySection: some View {
        SectionCard(title: "Activity by Hour", subtitle: "When you're most active today") {
            let maxKeys = hourlyActivity.map(\.keyCount).max() ?? 1

            if maxKeys == 0 {
                Text("No activity yet today")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            } else {
                Chart {
                    ForEach(hourlyActivity) { hour in
                        BarMark(
                            x: .value("Hour", hour.hour),
                            y: .value("Keys", hour.keyCount)
                        )
                        .foregroundStyle(
                            hour.hour == Calendar.current.component(.hour, from: Date())
                                ? Color.blue
                                : Color.blue.opacity(0.5)
                        )
                        .cornerRadius(2)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisValueLabel {
                            if let h = value.as(Int.self) {
                                Text(formatHour(h))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(formatNumber(v))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 100)
            }
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened).replacingOccurrences(of: ":00", with: "")
    }

    // MARK: - Dwell Time Section

    @ViewBuilder
    private var dwellTimeSection: some View {
        SectionCard(title: "Key Press Duration", subtitle: "How long you hold keys down") {
            if let dwell = dwellStats, (dwell.shortPresses + dwell.normalPresses + dwell.longPresses) > 0 {
                VStack(spacing: 12) {
                    // Average
                    HStack {
                        Text("Average")
                            .font(.callout)
                        Spacer()
                        Text(String(format: "%.0fms", dwell.averageDwellMs))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Distribution
                    let total = dwell.shortPresses + dwell.normalPresses + dwell.longPresses
                    VStack(spacing: 8) {
                        dwellRow("Quick (<100ms)", count: dwell.shortPresses, total: total, color: .green)
                        dwellRow("Normal (100-200ms)", count: dwell.normalPresses, total: total, color: .blue)
                        dwellRow("Long (>200ms)", count: dwell.longPresses, total: total, color: .orange)
                    }
                }
            } else {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dwellRow(_ label: String, count: Int, total: Int, color: Color) -> some View {
        let ratio = total > 0 ? Double(count) / Double(total) : 0
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(ratio * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.6))
                    .frame(width: geo.size.width * ratio, height: 4)
            }
            .frame(height: 4)
        }
    }

    // MARK: - Modifier Keys Section

    @ViewBuilder
    private var modifierSection: some View {
        SectionCard(title: "Modifier Keys", subtitle: "Keyboard shortcuts used today") {
            if let mods = modifierStats, (mods.shiftCount + mods.commandCount + mods.optionCount + mods.controlCount) > 0 {
                let items: [(String, String, Int, Color)] = [
                    ("Cmd", "command", mods.commandCount, .blue),
                    ("Shift", "shift", mods.shiftCount, .green),
                    ("Option", "option", mods.optionCount, .orange),
                    ("Control", "control", mods.controlCount, .purple)
                ]
                let maxCount = items.map(\.2).max() ?? 1

                VStack(spacing: 0) {
                    ForEach(items.sorted { $0.2 > $1.2 }, id: \.0) { item in
                        HStack {
                            Image(systemName: item.1)
                                .frame(width: 20)
                                .foregroundStyle(item.3)
                            Text(item.0)
                                .font(.callout)
                            Spacer()
                            Text(formatNumber(item.2))
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item.3.opacity(0.4))
                                .frame(width: geo.size.width * (Double(item.2) / Double(maxCount)), height: 3)
                        }
                        .frame(height: 3)
                    }
                }
            } else {
                Text("No modifier keys used")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Top Windows Section

    @ViewBuilder
    private var topWindowsSection: some View {
        SectionCard(title: "Top Documents", subtitle: "Windows you've typed in today") {
            if topWindows.isEmpty {
                Text("No window data")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topWindows.prefix(5).enumerated()), id: \.element.id) { index, window in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(truncateTitle(window.title))
                                    .font(.callout)
                                    .lineLimit(1)
                                Text(window.appName)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(formatNumber(window.count))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        if index < min(topWindows.count, 5) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func truncateTitle(_ title: String) -> String {
        if title.count > 30 {
            return String(title.prefix(27)) + "..."
        }
        return title
    }

    // MARK: - Top Keys Section

    @ViewBuilder
    private var topKeysSection: some View {
        SectionCard(title: "Most Used Keys", subtitle: "Keys you press most today") {
            if topKeys.isEmpty {
                Text("No key data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                let maxCount = topKeys.map(\.count).max() ?? 1
                VStack(spacing: 0) {
                    ForEach(Array(topKeys.prefix(8).enumerated()), id: \.element.id) { index, key in
                        HStack {
                            Text(key.keyName)
                                .font(.system(.callout, design: .monospaced))
                                .frame(width: 60, alignment: .leading)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.indigo.opacity(0.5))
                                    .frame(width: geo.size.width * (Double(key.count) / Double(maxCount)), height: 12)
                            }
                            .frame(height: 12)
                            Text(formatNumber(key.count))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Top Words Section

    @ViewBuilder
    private var topWordsSection: some View {
        SectionCard(title: "Top Words", subtitle: "Most typed words today") {
            if topWords.isEmpty {
                Text("No word data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                let maxCount = topWords.map(\.count).max() ?? 1
                VStack(spacing: 0) {
                    ForEach(Array(topWords.prefix(8).enumerated()), id: \.element.id) { index, word in
                        HStack {
                            Text(word.word)
                                .font(.system(.callout))
                                .lineLimit(1)
                            Spacer()
                            Text("\(word.count)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.teal.opacity(0.4))
                                .frame(width: geo.size.width * (Double(word.count) / Double(maxCount)), height: 3)
                        }
                        .frame(height: 3)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Click Heatmap Section

    @ViewBuilder
    private var clickHeatmapSection: some View {
        SectionCard(title: "Click Zones", subtitle: "Where you click on screen") {
            if clickHeatmap.isEmpty {
                Text("No click data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                // 3x3 grid representing screen zones
                let zoneDict = Dictionary(uniqueKeysWithValues: clickHeatmap.map { ($0.zone, $0) })
                let maxCount = clickHeatmap.map(\.count).max() ?? 1

                VStack(spacing: 2) {
                    ForEach(["top", "middle", "bottom"], id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(["left", "center", "right"], id: \.self) { col in
                                let zone = "\(row)-\(col)"
                                let data = zoneDict[zone]
                                let count = data?.count ?? 0
                                let intensity = maxCount > 0 ? Double(count) / Double(maxCount) : 0

                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.orange.opacity(0.1 + intensity * 0.6))
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(intensity > 0.5 ? .white : .secondary)
                                    }
                                }
                                .frame(height: 35)
                            }
                        }
                    }
                }

                // Legend
                HStack {
                    Text("Low")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [.orange.opacity(0.1), .orange.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 4)
                    Text("High")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Speed Over Time Section

    @ViewBuilder
    private var speedOverTimeSection: some View {
        SectionCard(title: "Typing Speed Over Time", subtitle: "How your speed changes throughout the day (lower = faster)") {
            let activeHours = hourlySpeed.filter { $0.sampleCount > 0 }

            if activeHours.isEmpty {
                Text("No speed data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            } else {
                Chart {
                    // Reference line at 150ms
                    RuleMark(y: .value("Fast", 150))
                        .foregroundStyle(Color.green.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(activeHours) { hour in
                        LineMark(
                            x: .value("Hour", hour.hour),
                            y: .value("Speed", hour.avgSpeedMs)
                        )
                        .foregroundStyle(Color.purple)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Hour", hour.hour),
                            y: .value("Speed", hour.avgSpeedMs)
                        )
                        .foregroundStyle(Color.purple)
                        .symbolSize(30)
                    }
                }
                .chartYScale(domain: 50...350)
                .chartXScale(domain: 0...23)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisValueLabel {
                            if let h = value.as(Int.self) {
                                Text(formatHour(h))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [100, 150, 200, 300]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel {
                            if let ms = value.as(Int.self) {
                                Text("\(ms)ms")
                                    .font(.caption2)
                                    .foregroundStyle(ms == 150 ? .green : .secondary)
                            }
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    // MARK: - Editing Stats Section

    @ViewBuilder
    private var editingStatsSection: some View {
        SectionCard(title: "Editing Behavior", subtitle: "Backspace and navigation usage") {
            if let stats = editingStats, stats.totalKeys > 0 {
                VStack(spacing: 12) {
                    // Backspace ratio visualization
                    VStack(spacing: 4) {
                        HStack {
                            Text("Backspace ratio")
                                .font(.callout)
                            Spacer()
                            Text(String(format: "%.1f%%", stats.backspaceRatio))
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(stats.backspaceRatio > 15 ? .orange : .green)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.primary.opacity(0.1))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(stats.backspaceRatio > 15 ? Color.orange : Color.green)
                                    .frame(width: geo.size.width * min(stats.backspaceRatio / 30, 1))
                            }
                        }
                        .frame(height: 6)
                        Text(stats.backspaceRatio < 8 ? "Excellent accuracy" : stats.backspaceRatio < 15 ? "Good accuracy" : "High correction rate")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    // Stats breakdown
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(formatNumber(stats.backspaceCount))")
                                .font(.system(.title3, design: .monospaced))
                            Text("backspaces")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(formatNumber(stats.arrowKeyCount))")
                                .font(.system(.title3, design: .monospaced))
                            Text("arrow keys")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Word Stats Section

    @ViewBuilder
    private var wordStatsSection: some View {
        SectionCard(title: "Word Statistics", subtitle: "Writing patterns today") {
            if let stats = wordStats, stats.totalWords > 0 {
                VStack(spacing: 12) {
                    // WPM highlight
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.0f", stats.wordsPerMinute))
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .foregroundStyle(.blue)
                            Text("words/min avg")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(stats.totalWords)")
                                .font(.system(.title2, design: .rounded))
                            Text("total words")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Divider()

                    // Word length stats
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%.1f", stats.avgWordLength))
                                .font(.system(.title3, design: .monospaced))
                            Text("avg length")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if !stats.longestWord.isEmpty {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(stats.longestWord.prefix(12) + (stats.longestWord.count > 12 ? "..." : ""))
                                    .font(.system(.callout, design: .monospaced))
                                Text("longest word")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } else {
                Text("No word data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Peak Hours Section

    @ViewBuilder
    private var peakHoursSection: some View {
        SectionCard(title: "Peak Productivity", subtitle: "Your most productive hours") {
            if peakHours.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(peakHours.prefix(4).enumerated()), id: \.element.hour) { index, peak in
                        HStack {
                            // Rank badge
                            Text("\(index + 1)")
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(index == 0 ? Color.yellow : index == 1 ? Color.gray : Color.orange.opacity(0.6))
                                .clipShape(Circle())

                            Text(peak.formattedHour)
                                .font(.system(.callout, design: .monospaced))
                                .frame(width: 45, alignment: .leading)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(formatNumber(peak.keyCount)) keys")
                                    .font(.caption)
                                Text("\(Int(peak.avgSpeedMs))ms")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 6)
                        if index < min(peakHours.count, 4) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Explanations Section

    @ViewBuilder
    private var explanationsSection: some View {
        SectionCard(title: "How It Works", subtitle: "Understanding your typing metrics") {
            VStack(alignment: .leading, spacing: 16) {
                explanationItem(
                    title: "Typing Speed",
                    description: "The average time between consecutive keystrokes (flight time). Lower is faster. Under 150ms is considered fast typing."
                )
                explanationItem(
                    title: "Rhythm Score",
                    description: "Measures how consistent your typing pace is. Higher scores mean steadier typing with less variation. Based on coefficient of variation."
                )
                explanationItem(
                    title: "Focus Score",
                    description: "A combined metric of speed and rhythm. High scores (70+) indicate you're typing both quickly and consistently."
                )
                explanationItem(
                    title: "Flow State",
                    description: "Detected when you're typing fast (<200ms avg) with good rhythm (>40). This is the optimal typing state where you're in the zone."
                )
                explanationItem(
                    title: "Key Press Duration",
                    description: "How long you hold each key down (dwell time). Quick presses (<100ms) indicate confident, experienced typing."
                )
                explanationItem(
                    title: "Sessions",
                    description: "A new session starts after 30 seconds of inactivity. Helps track distinct working periods throughout the day."
                )
            }
        }
    }

    @ViewBuilder
    private func explanationItem(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Data Refresh

    private func refreshData() {
        Task {
            let rawFlightData = await DatabaseManager.shared.getRecentFlightTimes(limit: 500)
            let validFlights = rawFlightData.compactMap { $0.flightTime }.filter { $0 < 5.0 }
            let analysisResult = FlightTimeAnalyzer.analyze(history: validFlights)
            let appData = await DatabaseManager.shared.getTopApps(limit: 5)
            let sessionData = await DatabaseManager.shared.getRecentSessions(limit: 10)
            let stats = await DatabaseManager.shared.getSummaryStats()
            let dwell = await DatabaseManager.shared.getDwellTimeStats(today: true)
            let mods = await DatabaseManager.shared.getModifierStats(today: true)
            let windows = await DatabaseManager.shared.getTopWindows(limit: 5)
            let hourly = await DatabaseManager.shared.getHourlyActivity()
            let keys = await DatabaseManager.shared.getTopKeys(limit: 10)
            let words = await DatabaseManager.shared.getTopWords(limit: 10)
            let heatmap = await DatabaseManager.shared.getClickHeatmap()
            let speed = await DatabaseManager.shared.getHourlySpeed()
            let editing = await DatabaseManager.shared.getEditingStats(today: true)
            let wordS = await DatabaseManager.shared.getWordStats()
            let peaks = await DatabaseManager.shared.getPeakProductivityHours()

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.flightTimeData = rawFlightData
                    self.analysis = analysisResult
                    self.topApps = appData
                    self.recentSessions = sessionData
                    self.summaryStats = stats
                    self.dwellStats = dwell
                    self.modifierStats = mods
                    self.topWindows = windows
                    self.hourlyActivity = hourly
                    self.topKeys = keys
                    self.topWords = words
                    self.clickHeatmap = heatmap
                    self.hourlySpeed = speed
                    self.editingStats = editing
                    self.wordStats = wordS
                    self.peakHours = peaks
                }
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatSessionTime(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today, " + date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday, " + date.formatted(date: .omitted, time: .shortened)
        } else {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let mins = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
        } else {
            let hours = Int(seconds / 3600)
            let mins = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(mins)m"
        }
    }

    // MARK: - Score Descriptions

    private func speedColor(_ speed: Double) -> Color {
        if speed >= 70 { return .green }
        if speed >= 40 { return .blue }
        return .orange
    }

    private func speedDescription(_ speed: Double) -> String {
        if speed >= 80 { return "Very fast" }
        if speed >= 60 { return "Fast" }
        if speed >= 40 { return "Moderate" }
        if speed >= 20 { return "Relaxed" }
        return "Slow"
    }

    private func consistencyColor(_ consistency: Double) -> Color {
        if consistency >= 60 { return .green }
        if consistency >= 30 { return .blue }
        return .orange
    }

    private func consistencyDescription(_ consistency: Double) -> String {
        if consistency >= 70 { return "Very steady" }
        if consistency >= 50 { return "Steady" }
        if consistency >= 30 { return "Variable" }
        return "Irregular"
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }

    private func scoreDescription(_ score: Int) -> String {
        if score >= 80 { return "Excellent" }
        if score >= 60 { return "Good" }
        if score >= 40 { return "Moderate" }
        return "Low"
    }
}

// MARK: - Components

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let detail: String
    let accent: Color
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)

            if let progress = progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accent)
                            .frame(width: geo.size.width * max(0, min(1, progress)), height: 4)
                    }
                }
                .frame(height: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.8))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    DashboardView()
}
