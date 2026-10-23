//
//  Date.swift
//  Spot
//
//  Created by Leon Böttger on 16.12.24.
//

import Foundation

extension Date {
    /// Returns `true` if the date is older than the seconds specified.
    func isOlderThan(seconds: Double) -> Bool {
        timeIntervalSinceNow < -seconds
    }

    var unixTime: Int32 {
        Int32(timeIntervalSince1970)
    }
}

extension Int32 {
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(self))
    }
}

/// Returns seconds from the amount of days specified.
func daysToSeconds(days: Int) -> Double {
    Double(days) * 24 * 60 * 60
}

/// Returns seconds from the amount of hours specified.
func hoursToSeconds(hours: Int) -> Double {
    Double(hours) * 60 * 60
}

/// Returns seconds from the amount of minutes specified.
func minutesToSeconds(minutes: Int) -> Double {
    Double(minutes) * 60
}
