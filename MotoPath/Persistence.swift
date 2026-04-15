//
//  Persistence.swift
//  MotoPath
//
//  Created by Hiro Ikezawa on 2025/09/24.
//

import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    // Programmatic model: LocationSample entity with attributes
    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // Attributes
        let timestamp = NSAttributeDescription()
        timestamp.name = "timestamp"
        timestamp.attributeType = .dateAttributeType
        timestamp.isOptional = false

        let latitude = NSAttributeDescription()
        latitude.name = "latitude"
        latitude.attributeType = .doubleAttributeType
        latitude.isOptional = false

        let longitude = NSAttributeDescription()
        longitude.name = "longitude"
        longitude.attributeType = .doubleAttributeType
        longitude.isOptional = false

        let accuracy = NSAttributeDescription()
        accuracy.name = "accuracy"
        accuracy.attributeType = .doubleAttributeType
        accuracy.isOptional = true

        let speed = NSAttributeDescription()
        speed.name = "speed"
        speed.attributeType = .doubleAttributeType
        speed.isOptional = true

        // Entity
        let locationEntity = NSEntityDescription()
        locationEntity.name = "LocationSample"
        locationEntity.managedObjectClassName = NSStringFromClass(LocationSample.self)
        locationEntity.properties = [timestamp, latitude, longitude, accuracy, speed]

        model.entities = [locationEntity]
        return model
    }

    init(inMemory: Bool = false) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "MotoPath", managedObjectModel: model)
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
