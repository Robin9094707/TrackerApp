//
//  TapticControl.swift
//  Timer
//
//  Created by Leon Böttger on 20.06.20.
//  Copyright © 2020 Leon Böttger.
//

import AudioToolbox
import Foundation
import SwiftUI

/// background thread for database work in background.
let hapticQueue = DispatchQueue(label: "hapticQueue", qos: .userInteractive)

public func errorVibration() {
    hapticQueue.async {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

public func lightVibration() {
    hapticQueue.async {
        let impactMed = UIImpactFeedbackGenerator(style: .light)
        impactMed.impactOccurred()
    }
}

public func doubleVibration() {
    hapticQueue.async {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
