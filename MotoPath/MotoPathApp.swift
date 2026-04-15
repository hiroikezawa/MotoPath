//
//  MotoPathApp.swift
//  MotoPath
//
//  Created by Hiro Ikezawa on 2025/09/24.
//

import SwiftUI
import CoreData
import Combine
import CoreLocation

@main
struct MotoPathApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var recorder = LocationRecorder.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    print("App appeared: requesting authorization and starting recorder")
                    recorder.requestAuthorization()
                    recorder.start() // ensure start even when already authorized
                    print("Auth status:", recorder.authorizationStatus.rawValue)
                    print("Location services enabled:", CLLocationManager.locationServicesEnabled())
                }
                .onReceive(recorder.$currentLocation) { loc in
                    if let loc {
                        print("[Location Update] lat: \(loc.coordinate.latitude), lon: \(loc.coordinate.longitude), acc: \(loc.horizontalAccuracy), speed: \(max(0, loc.speed)) @ \(loc.timestamp)")
                    }
                }
                .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                    if let loc = recorder.currentLocation {
                        print("[Location Log] lat: \(loc.coordinate.latitude), lon: \(loc.coordinate.longitude), acc: \(loc.horizontalAccuracy), speed: \(max(0, loc.speed)) @ \(loc.timestamp)")
                    } else {
                        print("[Location Log] No current location yet")
                    }
                }
        }
    }
}

