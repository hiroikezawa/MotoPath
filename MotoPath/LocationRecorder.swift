//
//  LocationRecorder.swift
//  MotoPath
//
//  Created by Hiro Ikezawa on 2025/09/24.
//

import Foundation
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
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private let distanceFilter: CLLocationDistance = 25 // meters
    private let minRecordInterval: TimeInterval = 30 // seconds

    private var lastSavedAt: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = desiredAccuracy
        manager.distanceFilter = distanceFilter
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = true
    }

    func requestAuthorization() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestAlwaysAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func start() {
        // Combine significant changes and standard updates to balance power and fidelity
        manager.startMonitoringSignificantLocationChanges()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
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
        switch manager.authorizationStatus {
        case .authorizedAlways:
            start()
        case .authorizedWhenInUse:
            // encourage Always for background
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
        save(location: latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("CLLocationManager error: \(error.localizedDescription)")
    }
}
