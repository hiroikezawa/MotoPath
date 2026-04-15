//
//  ContentView.swift
//  MotoPath
//
//  Created by Hiro Ikezawa on 2025/09/24.
//

import SwiftUI
import CoreData
import MapKit
import os

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var selectedDate: Date = Date()
    @State private var route: [CLLocationCoordinate2D] = []
    @State private var region: MKCoordinateRegion = .init(center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671), span: .init(latitudeDelta: 0.2, longitudeDelta: 0.2))
    @State private var mapPosition: MapCameraPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671), span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)))
    @State private var recordedDays: Set<Date> = [] // startOfDay dates with records
    @State private var isCalendarPresented: Bool = false
    @State private var polyline: MKPolyline? = nil
    @State private var didSetupMemoryWarningObserver: Bool = false

    private static let log = Logger(subsystem: "com.motopath", category: "ContentView")

    private var currentCalendar: Calendar {
        var cal = Calendar.autoupdatingCurrent
        // autoupdatingCurrent はロケール/タイムゾーンの変更に追随
        return cal
    }

    var body: some View {
        ZStack {
            // 地図を全画面に表示
            MapReader { proxy in
                Map(position: $mapPosition) {
                    if let polyline, route.count > 1 {
                        MapPolyline(polyline)
                            .stroke(.blue, lineWidth: 4)
                    }
                }
                .mapStyle(.standard)
                .ignoresSafeArea()
                .onAppear {
                    print("Map appeared: will loadRoute")
                    Self.log.info("Map appeared: will loadRoute")
                    loadRoute()
                    print("Map appeared: did call loadRoute")
                    Self.log.info("Map appeared: did call loadRoute")
                }
            }
            
            // 上部グラデーション（文字の視認性向上）
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.3), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .ignoresSafeArea(edges: .top)
                
                Spacer()
            }
            
            // フローティング・ヘッダー
            VStack {
                HStack(alignment: .center, spacing: 12) {
                    // 左側: タイトル
//                    VStack(alignment: .leading, spacing: 2) {
//                        Text("移動ルート")
//                            .font(.headline)
//                            .foregroundStyle(.primary)
//                    }
                    
//                    Spacer()
                    
                    // 右側: 日付選択ボタン（チップ状）
                    Button {
                        loadRecordedDays()
                        print("Open calendar sheet")
                        Self.log.info("Open calendar sheet")
                        isCalendarPresented = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.subheadline)
                            Text(formattedDate(selectedDate))
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(.systemBackground).opacity(0.9))
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }
                    .accessibilityLabel("日付を選択")
                    .accessibilityHint("タップしてカレンダーを開く")
                    
                    // 更新ボタン
                    Button {
                        print("Refresh tapped")
                        Self.log.info("Refresh tapped")
                        loadRoute()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color(.systemBackground).opacity(0.9))
                            )
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }
                    .accessibilityLabel("更新")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer()
            }
        }
        .onAppear {
            print("ContentView appeared")
            Self.log.info("ContentView appeared")
            loadRecordedDays()
            if !didSetupMemoryWarningObserver {
                didSetupMemoryWarningObserver = true
                NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
                    print("⚠️ Memory warning received")
                }
            }
        }
        .sheet(isPresented: $isCalendarPresented) {
            RecordedCalendarSheet(selectedDate: $selectedDate, recordedDays: $recordedDays) {
                isCalendarPresented = false
                loadRoute()
            }
        }
        .onChange(of: selectedDate) { newValue in
            print("selectedDate changed:", newValue)
            Self.log.info("selectedDate changed: \(String(describing: newValue), privacy: .public)")
            let day = currentCalendar.startOfDay(for: newValue)
            if !recordedDays.contains(day), let snapped = nearestRecordedDate(to: day) {
                // 未記録日が選ばれた場合、最も近い記録日にスナップ
                print("Snapping to nearest recorded date:", snapped)
                Self.log.info("Snapping to nearest recorded date: \(String(describing: snapped), privacy: .public)")
                selectedDate = snapped
                loadRoute()
            }
        }
    }

    private func loadRoute() {
        print("loadRoute start for:", selectedDate)
        Self.log.info("loadRoute start for: \(String(describing: selectedDate), privacy: .public)")
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        let request = NSFetchRequest<LocationSample>(entityName: "LocationSample")
        request.fetchBatchSize = 2000
        request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", start as NSDate, end as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        do {
            let samples = try viewContext.fetch(request)
            print("Route samples fetched:", samples.count)
            Self.log.info("Route samples fetched: \(samples.count, privacy: .public)")
            route = samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            if route.isEmpty {
                // ルートがない場合は位置は変更しない
                print("No route for date:", selectedDate)
                Self.log.info("No route for date: \(String(describing: selectedDate), privacy: .public)")
                polyline = nil
                return
            }
            // ルート全体をぴったり表示（1点のみなら起点に寄せる）
            let newRegion = fittingRegion(for: route)
            print("Fitting region center:(", newRegion.center.latitude, ",", newRegion.center.longitude, ") span:(", newRegion.span.latitudeDelta, ",", newRegion.span.longitudeDelta, ")")
            Self.log.info("Fitting region center:(\(newRegion.center.latitude, privacy: .public), \(newRegion.center.longitude, privacy: .public)) span:(\(newRegion.span.latitudeDelta, privacy: .public), \(newRegion.span.longitudeDelta, privacy: .public))")
            region = newRegion
            mapPosition = .region(newRegion)
            rebuildPolylineAsync(from: route)
            print("loadRoute end")
            Self.log.info("loadRoute end")
        } catch {
            print("Failed to fetch: \(error)")
            route = []
        }
    }

    private func loadRecordedDays() {
        print("loadRecordedDays start")
        Self.log.info("loadRecordedDays start")
        let request = NSFetchRequest<LocationSample>(entityName: "LocationSample")
        request.fetchBatchSize = 2000
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        do {
            let samples = try viewContext.fetch(request)
            let days = samples.map { currentCalendar.startOfDay(for: $0.timestamp) }
            recordedDays = Set(days)
            print("Recorded days:", recordedDays.count)
            Self.log.info("Recorded days: \(recordedDays.count, privacy: .public)")
        } catch {
            print("Failed to fetch recorded days: \(error)")
            recordedDays = []
        }
    }

    private func decimate(_ coords: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard coords.count > maxPoints, maxPoints > 0 else { return coords }
        let step = max(1, coords.count / maxPoints)
        return stride(from: 0, to: coords.count, by: step).map { coords[$0] }
    }

    private func rebuildPolylineAsync(from coords: [CLLocationCoordinate2D]) {
        let coordsCopy = coords // capture immutably for thread safety
        Task.detached(priority: .userInitiated) {
            let simplified = decimate(coordsCopy, maxPoints: 5000)
            let newPolyline = simplified.isEmpty ? nil : MKPolyline(coordinates: simplified, count: simplified.count)
            await MainActor.run {
                print("Polyline rebuilt. simplifiedCount:", simplified.count)
                Self.log.info("Polyline rebuilt. simplifiedCount: \(simplified.count, privacy: .public)")
                self.polyline = newPolyline
            }
        }
    }

    private func nearestRecordedDate(to day: Date) -> Date? {
        if recordedDays.isEmpty { return nil }
        // もっとも近い startOfDay を探索
        return recordedDays.min(by: { abs($0.timeIntervalSince(day)) < abs($1.timeIntervalSince(day)) })
    }

    private func formattedDate(_ date: Date) -> String {
        struct Cache {
            static let formatter: DateFormatter = {
                let f = DateFormatter()
                f.locale = .autoupdatingCurrent
                f.calendar = Calendar.autoupdatingCurrent
                f.dateStyle = .medium
                f.timeStyle = .none
                return f
            }()
        }
        return Cache.formatter.string(from: date)
    }

    private func fittingRegion(for coordinates: [CLLocationCoordinate2D], paddingFactor: Double = 1.2) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else { return region }
        if coordinates.count == 1 {
            let center = coordinates[0]
            let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            return MKCoordinateRegion(center: center, span: span)
        }
        var minLat = coordinates.first!.latitude
        var maxLat = coordinates.first!.latitude
        var minLon = coordinates.first!.longitude
        var maxLon = coordinates.first!.longitude
        for c in coordinates.dropFirst() {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2.0, longitude: (minLon + maxLon) / 2.0)
        var latDelta = max(0.001, (maxLat - minLat) * paddingFactor)
        var lonDelta = max(0.001, (maxLon - minLon) * paddingFactor)
        // Ensure reasonable minimum span
        latDelta = max(latDelta, 0.005)
        lonDelta = max(lonDelta, 0.005)
        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        return MKCoordinateRegion(center: center, span: span)
    }
}

private struct RecordedCalendarSheet: View {
    @Binding var selectedDate: Date
    @Binding var recordedDays: Set<Date>
    let onSelect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var monthAnchor: Date

    // ロケール/タイムゾーンに追随するカレンダー
    private var currentCalendar: Calendar { Calendar.autoupdatingCurrent }

    init(selectedDate: Binding<Date>, recordedDays: Binding<Set<Date>>, onSelect: @escaping () -> Void) {
        self._selectedDate = selectedDate
        self._recordedDays = recordedDays
        self.onSelect = onSelect
        let cal = Calendar.autoupdatingCurrent
        _monthAnchor = State(initialValue: cal.date(from: cal.dateComponents([.year, .month], from: selectedDate.wrappedValue))!)
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayHeader
            monthGrid
            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack {
            Button(action: { changeMonth(by: -1) }) { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle(for: monthAnchor)).font(.headline)
            Spacer()
            Button(action: { changeMonth(by: 1) }) { Image(systemName: "chevron.right") }
        }
    }

    private var weekdayHeader: some View {
        let symbols = currentCalendar.shortWeekdaySymbols
        return HStack {
            ForEach(symbols, id: \.self) { s in
                Text(s).frame(maxWidth: .infinity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var monthGrid: some View {
        let days = daysForMonthGrid(anchor: monthAnchor)
        return VStack(spacing: 8) {
            ForEach(0..<(days.count/7), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let idx = row * 7 + col
                        let date = days[idx]
                        ZStack {
                            if let d = date {
                                dayCell(for: d, isCurrentMonth: currentCalendar.isDate(d, equalTo: monthAnchor, toGranularity: .month))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedDate = d
                                        onSelect()
                                        dismiss()
                                    }
                            } else {
                                Color.clear.frame(height: 40)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func dayCell(for date: Date, isCurrentMonth: Bool) -> some View {
        let day = currentCalendar.component(.day, from: date)
        let isSelected = currentCalendar.isDate(date, inSameDayAs: selectedDate)
        let isRecorded = recordedDays.contains(currentCalendar.startOfDay(for: date))

        return VStack(spacing: 4) {
            Text("\(day)")
                .font(.body)
                .foregroundStyle(isCurrentMonth ? .primary : .secondary)
                .frame(height: 22)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                )
            // 前回のドットではなく、細いカプセル下線でマーク
            Capsule()
                .fill(isRecorded ? Color.accentColor : Color.clear)
                .frame(width: 14, height: 3)
        }
        .frame(height: 40)
    }

    private func changeMonth(by offset: Int) {
        if let newMonth = currentCalendar.date(byAdding: .month, value: offset, to: monthAnchor) {
            monthAnchor = newMonth
        }
    }

    private func monthTitle(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.calendar = currentCalendar
        f.dateFormat = "yyyy年 M月"
        return f.string(from: date)
    }

    private func daysForMonthGrid(anchor: Date) -> [Date?] {
        let startOfMonth = currentCalendar.date(from: currentCalendar.dateComponents([.year, .month], from: anchor))!
        let range = currentCalendar.range(of: .day, in: .month, for: startOfMonth)!
        let firstWeekday = currentCalendar.component(.weekday, from: startOfMonth)
        let leadingEmpty = (firstWeekday - currentCalendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in range {
            if let d = currentCalendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(d)
            }
        }
        while days.count % 7 != 0 { days.append(nil) }
        while days.count < 42 { days.append(nil) }
        return days
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}

