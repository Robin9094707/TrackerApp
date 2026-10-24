//
//  LocationManager.swift
//  Spot
//
//  Created by Leon Böttger on 16.12.24.
//

import CoreLocation
import Foundation
import Combine

/// Struct for requests to new locations
struct LocationManagerRequest: Identifiable, Equatable {
    static func == (lhs: LocationManagerRequest, rhs: LocationManagerRequest) -> Bool {
        lhs.id == rhs.id
    }

    /// The ID of the request
    let id = UUID()

    /// The callback after the location was retrieved
    let callback: (CLLocation?) -> Void

    /// The start date of the request
    let date = Date()
}

/// Handles management of GPS locations.
open class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    /// The instance of the CL location manager
    var locationManager: CLLocationManager?

    /// last accurate location stored in database
    var lastLocation: CLLocation?

    /// last update of location
    var lastUpdate = Date.distantPast

    /// last significant location update
    var lastSignificantLocationUpdate = Date()

    /// true if app has location access
    @Published var permissionSet = false

    /// The shared instance
    static var sharedInstance = LocationManager()

    /// specifies in seconds how long to use old cached location until a new request is made
    let secondsUntilNewLocation: Double = 50

    /// specifies the (exclusive) limit of the accepted accuracy for received locations
    let accuracyLimit: Double = 100

    /// saves callbacks of all interested clients
    var callbacks = [LocationManagerRequest]()

    /// Date when the last location was requested.
    var locationUpdateStart = Date.distantPast

    /// specifies if GPS should be kept alive all the time
    var keepAlive = false

    /// The background queue to perform location tasks.
    private let locationManagerQueue = DispatchQueue(label: "locationManagerQueue")

    var pendingOperation: DispatchWorkItem?

    /// sets up the location manager
    override private init() {
        super.init()

        let newManager = CLLocationManager()

        // Create a location manager object
        locationManager = newManager

        // Set delegate
        locationManager?.delegate = self

        // Set the accuracy
        locationManager?.desiredAccuracy = kCLLocationAccuracyNearestTenMeters

        enableBackgroundLocationUpdate()

        locationManager(newManager, didChangeAuthorization: newManager.authorizationStatus)
    }

    /// Enables automatic update of location in the background
    func enableBackgroundLocationUpdate() {
        // Enable background location updates
        locationManager?.allowsBackgroundLocationUpdates = true

        // Enable significant location update
        locationManager?.startMonitoringSignificantLocationChanges()
    }

    /// Disables automatic update of location in the background
    func disableBackgroundLocationUpdate() {
        // Enable background location updates
        locationManager?.allowsBackgroundLocationUpdates = false

        // Enable significant location update
        locationManager?.stopMonitoringSignificantLocationChanges()
    }

    /// requests always usage of location to user
    func requestAlwaysUsage() {
        locationManager?.requestAlwaysAuthorization()
    }

    /// requests when in use usage of location to user
    func requestWhenInUse() {
        locationManager?.requestWhenInUseAuthorization()
    }

    /// gets called if autorization status changes
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedAlways, manager.accuracyAuthorization == .fullAccuracy {
            permissionSet = true
        } else {
            if status == .authorizedWhenInUse, manager.accuracyAuthorization == .fullAccuracy {
                permissionSet = true
            } else {
                permissionSet = false
            }
        }

        if let dispatchWorkItem = pendingOperation, permissionSet {
            locationManagerQueue.async(execute: dispatchWorkItem)
        }
    }

    /// returns if authorization is set to "Always"
    public func hasAlwaysPermission() -> Bool {
        locationManager?.authorizationStatus == .authorizedAlways && locationManager?.accuracyAuthorization == .fullAccuracy
    }

    public func startUpdatingLocation(keepAlive: Bool = false) {
        locationManager?.startUpdatingLocation()

        if keepAlive {
            self.keepAlive = true
        }
    }

    public func stopUpdatingLocation(turnOffKeepAlive: Bool = false) {
        if turnOffKeepAlive {
            keepAlive = false
        }

        if !keepAlive {
            locationManager?.stopUpdatingLocation()
        }
    }

    /// gets called if system received new location
    public func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if Settings.sharedInstance.isBackground {
            // system woke up, use chance  restart scan if necessary
            if !BluetoothManager.sharedInstance.scanning {
                BluetoothManager.sharedInstance.startCentralManager()
            }
        }

        locationManagerQueue.async { [self] in
            /// no client is interested in a new location
            if callbacks.isEmpty {
                stopUpdatingLocation()

                if let lastNew = locations.last, let lastOld = lastLocation, lastNew.distance(from: lastOld) > 200 {
                    lastSignificantLocationUpdate = Date()
                }

                return
            }

            if let location = locations.last, // last entry is the most recent one
               location.horizontalAccuracy < accuracyLimit, // only accept locations with a specified accuracy
               Date().timeIntervalSince(location.timestamp) < secondsUntilNewLocation, // only accept recent locations
               lastUpdate.isOlderThan(seconds: secondsUntilNewLocation)
            { // Sometimes multiple locations are delivered, just take the first

                // We are now done searching
                stopUpdatingLocation()

                lastLocation = location
                lastUpdate = Date()

                // Store location in database or retrieve old one
                finishCallback(withLocation: lastLocation)
            }
        }
    }

    /// provides new location to all interested clients
    func finishCallback(withLocation: CLLocation?) {
        for callback in callbacks {
            // discard entries which are older than X minutes
            if !callback.date.isOlderThan(seconds: minutesToSeconds(minutes: 1)) {
                callback.callback(withLocation)
            } else {
                callback.callback(nil)
            }
        }

        callbacks.removeAll()
    }

    /// requests new location if necessary and calls client back
    func getNewLocation(callback: @escaping (CLLocation?) -> Void) {
        let dispatchWorkItem = DispatchWorkItem { [self] in
            /// Last location update was long time ago
            if lastUpdate.isOlderThan(seconds: secondsUntilNewLocation) {
                let request = LocationManagerRequest(callback: callback)
                callbacks.append(request)

                locationUpdateStart = Date()
                locationManager?.startUpdatingLocation()

                // Check if request is handled after one minute
                locationManagerQueue.asyncAfter(deadline: .now() + minutesToSeconds(minutes: 1)) {
                    // still no location received and no new requests were made
                    if self.callbacks.last == request {
                        // do not keep GPS on all the time if no location was found
                        self.stopUpdatingLocation()
                    }
                }
            }

            /// Last location update was recent
            else {
                if let lastLocation {
                    callback(lastLocation)
                } else {
                    callback(nil)
                }
            }
        }

        if !permissionSet {
            pendingOperation = dispatchWorkItem
            requestWhenInUse()
        } else {
            locationManagerQueue.async(execute: dispatchWorkItem)
        }
    }
}
