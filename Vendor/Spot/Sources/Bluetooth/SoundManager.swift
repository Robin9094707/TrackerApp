//
//  SoundManager.swift
//  Spot
//
//  Created by Leon Böttger on 24.12.24.
//

import CoreBluetooth
import Foundation
import LUI
import SwiftUI

/// Manages sound playback on trackers
public class SoundManager: ObservableObject {
    /// Shows if a sound is requested, but not yet sent to device
    @Published var soundRequest = false {
        didSet {
            if soundRequest {}
        }
    }

    /// Shows that a sound is played on device
    @Published var playingSound = false

    /// Shows that an error occured last time playing a sound
    @Published var error: SoundError?

    /// The Bluetooth UUID of the device to play the sound on.
    private var bluetoothUUID: String?

    /// Queue which handles wait for signal of device
    private let waitForSoundQueue = DispatchQueue(label: "waitForSoundQueue")

    /// Timeout for playSound in seconds, if device could not be connected
    private let connectTimeout = 10

    /// DispatchWorkItem which sets playingSound to false after sound playback is assumed to be over
    private var stoppedPlayingSound = DispatchWorkItem(block: {})

    /// The EIK of the device to play the sound on.
    private var eik: Data?

    /// Tries to play a sound on the given device
    func playSound(eik: Data, bluetoothUUID: String?) {
        self.eik = eik
        self.bluetoothUUID = bluetoothUUID

        if !soundRequest, !playingSound {
            // cancel if multiple sound requests started consequentely
            stoppedPlayingSound.cancel()

            startQueue()

            runAfter(seconds: 0.1) { [self] in
                withAnimation {
                    playingSound = false
                    error = nil
                    soundRequest = true
                }
            }
        }
    }

    /// Starts the queue and periodically tries to connect to the device
    private func startQueue() {
        waitForSoundQueue.async {
            if !self.tryToPlay() {
                self.soundNotPlayed(error: .couldNotConnect)
            }
        }
    }

    /// Gets called if characteristic was written, but not acknowledged
    private func soundNotPlayed(error: SoundError) {
        DispatchQueue.main.async {
            errorVibration()

            withAnimation {
                self.error = error
                self.soundRequest = false
            }
        }
    }

    /// Gets called if Bluetooth manager gets positive feedback
    private func playedSound() {
        doubleVibration()

        DispatchQueue.main.async {
            withAnimation {
                self.soundRequest = false
                self.playingSound = true
            }
        }

        stoppedPlayingSound = DispatchWorkItem(block: {
            withAnimation {
                self.playingSound = false
            }
        })

        let soundDuration = 30
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(soundDuration), execute: stoppedPlayingSound)
    }

    /// Tries to request sound playback. Returns true if request was sent.
    private func tryToPlay() -> Bool {
        guard let id = bluetoothUUID else { return false }
        guard let eik else { return false }

        FMDNOwnerOperations.executeRingerOperation(currentBluetoothId: id, eik: eik) { state, _ in
            switch state {
            case .Success:
                self.playedSound()
            case .Timeout:
                self.soundNotPlayed(error: .couldNotConnect)
            case .Failure:
                self.soundNotPlayed(error: .playbackFailed)
            }
        }

        return true
    }
}

/// Stores sound playback error
enum SoundError {
    /// The playback failed. Tracker does not allow playback.
    case playbackFailed

    /// Could not connect. Tracker out of range.
    case couldNotConnect

    /// The title of the error, visible to user
    var title: String {
        switch self {
        case .playbackFailed:
            "Playback Failed".localized()
        case .couldNotConnect:
            "Could Not Connect".localized()
        }
    }

    /// The description of the error, visible to user
    var description: String {
        switch self {
        case .playbackFailed:
            "Your device could not play a sound on this tracker. This usually means that the tracker is not in range. Move around and try again."
        case .couldNotConnect:
            "Your device could not connect to this tracker. This usually means that the tracker is not in range. Move around and try again."
        }
    }
}
