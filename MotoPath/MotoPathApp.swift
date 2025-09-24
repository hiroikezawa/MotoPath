//
//  MotoPathApp.swift
//  MotoPath
//
//  Created by Hiro Ikezawa on 2025/09/24.
//

import SwiftUI
import CoreData

@main
struct MotoPathApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
