//
//  LocationRecorder.swift
//  MotoPath
//
//  Created by Hiro Ikezawa on 2025/09/24.
//

import Foundation
import Combine
import CoreLocation
import CoreData
import os.log

@MainActor
final class LocationRecorder: NSObject, ObservableObject {
    static let shared = LocationRecorder()

    private let manager = CLLocationManager()
    private let persistence = PersistenceController.shared
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MotoPath", category: "LocationRecorder")

    // configuration
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBestForNavigation
    private let distanceFilter: CLLocationDistance = 25 // meters
    private let minRecordInterval: TimeInterval = 30 // seconds

    private var lastSavedAt: Date?
    @Published private(set) var currentLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = desiredAccuracy
        manager.distanceFilter = distanceFilter
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            // iOS 推奨フロー: まず WhenInUse を求める
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // バックグラウンド継続のために Always を追加でリクエスト
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            startForegroundAndBackground()
        case .restricted, .denied:
            // ここでは何もしない（設定アプリでの変更を促すなどは UI 側で）
            break
        @unknown default:
            break
        }
    }

    private func startForeground() {
        log.debug("startForeground() called")
        guard CLLocationManager.locationServicesEnabled() else {
            log.error("Location services disabled")
            return
        }
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.pausesLocationUpdatesAutomatically = false

        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    private func startForegroundAndBackground() {
        log.debug("startForegroundAndBackground() called")
        guard CLLocationManager.locationServicesEnabled() else {
            log.error("Location services disabled")
            return
        }
        // Note: Do NOT use significant-change monitoring here to avoid relaunching the app when it's not running.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false

        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    /// Public entry point to start recording based on current authorization state.
    /// - If not determined, requests WhenInUse (and later Always).
    /// - If WhenInUse, starts foreground updates and requests Always.
    /// - If Always, starts both foreground and background updates.
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            startForeground()
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            startForegroundAndBackground()
        case .restricted, .denied:
            // Do nothing; UI can prompt user to change settings
            break
        @unknown default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    private func save(location: CLLocation) {
        // throttle by time
        if let last = lastSavedAt, Date().timeIntervalSince(last) < minRecordInterval {
            return
        }
        lastSavedAt = Date()

        let context = persistence.container.viewContext
        let sample = LocationSample(context: context)
        sample.timestamp = location.timestamp
        sample.latitude = location.coordinate.latitude
        sample.longitude = location.coordinate.longitude
        sample.accuracy = location.horizontalAccuracy
        sample.speed = max(0, location.speed) // -1 means invalid
        do {
            try context.save()
            log.debug("Saved location: (\(sample.latitude), \(sample.longitude)) @ \(sample.timestamp as NSDate)")
        } catch {
            log.error("Failed saving location: \(error.localizedDescription)")
        }
    }
}

extension LocationRecorder: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        log.debug("Authorization changed: \(String(describing: manager.authorizationStatus))")
        switch manager.authorizationStatus {
        case .authorizedAlways:
            startForegroundAndBackground() // Start with foreground + background capabilities
            manager.requestLocation()
        case .authorizedWhenInUse:
            // Start foreground updates immediately, then request Always for background support
            startForeground()
            manager.requestLocation()
            manager.requestAlwaysAuthorization()
        case .denied, .restricted:
            stop()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        currentLocation = latest
        save(location: latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("CLLocationManager error: \(error.localizedDescription)")
    }
}

