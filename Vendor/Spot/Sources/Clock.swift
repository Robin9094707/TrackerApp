//
//  Clock.swift
//  Spot
//
//  Created by Leon Böttger on 10.12.24.
//

import Foundation
import SwiftUI

/// Class to represent the current date
class Clock: NSObject, ObservableObject {
    /// The current date.
    @Published var currentDate = Date()

    /// The timer to refresh the date
    private var timer = Timer()

    /// The shared instance.
    static var sharedInstance = Clock()

    /// The private initializer
    override private init() {
        /// Initi NSObject
        super.init()

        /// Fire timer every second and refresh date
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            self.objectWillChange.send()
            self.currentDate = Date()
        }
    }
}
