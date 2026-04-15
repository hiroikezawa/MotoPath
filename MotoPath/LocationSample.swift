//
//  LocationSample.swift
//  MotoPath
//
//  Created by Hiro Ikezawa on 2025/09/24.
//

import CoreData

@objc(LocationSample)
public class LocationSample: NSManagedObject {
    @NSManaged public var timestamp: Date
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var accuracy: Double
    @NSManaged public var speed: Double
}
