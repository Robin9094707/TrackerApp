//
//  PrecisionFindingView.swift
//  Spot
//
//  Created by Leon Böttger on 24.12.24.
//

import LUI
import SwiftUI

struct PrecisionFindingView: View {
    let tracker: LocalFindMyDevice
    @ObservedObject var bluetoothData: BluetoothTempData

    @StateObject var soundManager = SoundManager()
    @ObservedObject var clock = Clock.sharedInstance
    @State private var showSoundErrorInfo = false

    @Environment(\.colorScheme) var colorScheme

    @State var isStarted = false

    @Environment(\.scenePhase) var scenePhase
    @Environment(\.safeAreaInsets) private var safeAreaInsets

    var body: some View {
        let maxRSSI = Double(-30)

        let notReachable = deviceNotCurrentlyReachable(device: bluetoothData, currentDate: clock.currentDate, timeout: 45)

        let rssi = !isStarted || notReachable ? Constants.worstRSSI : Double(bluetoothData.rssi_publisher)

        let pct = rssiToPercentage(rssi: rssi, bestRSSI: maxRSSI)

        let delay: CGFloat = 2

        GeometryReader { geo in
            let fullHeight = geo.size.height

            ZStack {
                VStack(spacing: 0) {
                    ZStack {
                        Color.blue.opacity(colorScheme.isLight ? 0.9 : 1)
                        LinearGradient(colors: [.clear, .white.opacity(0.3)], startPoint: .bottom, endPoint: .top)

                        PrecisionOverlayElements(soundManager: soundManager, tracker: tracker, tempdata: bluetoothData, pct: pct, rssi: rssi, animationDelay: delay, textColor: .white, notReachable: notReachable)

                            .padding(safeAreaInsets)
                            .frame(height: fullHeight)
                    }
                    .frame(height: fullHeight * pct, alignment: .bottom)
                    .clipped()
                }
                .frame(height: fullHeight, alignment: .bottom)

                VStack(spacing: 0) {
                    ZStack {
                        Color.defaultBackgroundColor

                        PrecisionOverlayElements(soundManager: soundManager, tracker: tracker, tempdata: bluetoothData, pct: pct, rssi: rssi, animationDelay: delay, textColor: .mainColor, notReachable: notReachable)
                            .padding(safeAreaInsets)
                            .frame(height: fullHeight)
                    }
                    .frame(height: fullHeight * (1 - pct), alignment: .top)
                    .clipped()
                }
                .frame(height: fullHeight, alignment: .top)
            }
        }
        .rounded()
        .navigationBarBackButtonHidden()
        .ignoresSafeArea()
        .animation(.easeInOut(duration: delay), value: pct)
        .onAppear {
            isStarted = true
            startScan()
        }
        .onDisappear {
            BluetoothManager.sharedInstance.disableFastScan()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                runAfter(seconds: 1) {
                    startScan()
                }
            }
        }
    }

    func startScan() {
        var uuids = [UUID]()
        if let trackerUUID = UUID(uuidString: bluetoothData.identifier_background) {
            uuids.append(trackerUUID)
        }

        BluetoothManager.sharedInstance.enableFastScan(for: RSSIScan(service: Constants.FindMyDeviceService), allowedUUIDs: uuids)
    }
}

struct PrecisionOverlayElements: View {
    let soundManager: SoundManager
    let tracker: LocalFindMyDevice
    let tempdata: BluetoothTempData
    @Environment(\.colorScheme) var colorScheme
    @State var lastVibration = Date.distantPast
    let pct: CGFloat
    let rssi: CGFloat
    let animationDelay: CGFloat
    let textColor: Color
    let notReachable: Bool

    var body: some View {
        VStack {
            Text(tracker.userDefinedName)
                .bold()
                .font(.largeTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(textColor)
                .padding()
                .padding(.top)

            Spacer()

            Indicator(pct: pct, color: textColor)
                .onChange(of: pct, perform: { [pct] newPct in
                    if newPct == 0 {
                        errorVibration()
                    } else if abs(pct - newPct) > 0.05, lastVibration.isOlderThan(seconds: 5) {
                        lastVibration = Date()
                        if pct > newPct {
                            // User is going away
                            errorVibration()
                        } else {
                            // User is getting closer
                            doubleVibration()
                        }
                    }
                })

            Group {
                if notReachable {
                    HStack {
                        Text("No signal. Connecting...")

                        LoadingIndicator()
                            .frame(width: 18)
                            .padding(5)
                    }
                    .transition(AnyTransition.opacity.animation(.easeInOut(duration: 0.1)))
                } else {
                    Text("Move slowly and try to maximize the signal strength to find the tracker.")
                        .transition(AnyTransition.opacity.animation(.easeInOut(duration: 0.1)))
                }
            }
            .opacity(textColor == .white ? 1 : 0.7)
            .foregroundColor(textColor)
            .padding(.horizontal)
            .multilineTextAlignment(.center)
            .padding()

            Spacer()

            SoundAndCloseView(soundManager: soundManager, device: tracker, bluetoothData: tempdata, notReachable: notReachable)
        }
    }
}

struct SoundAndCloseView: View {
    @ObservedObject var soundManager: SoundManager
    let device: LocalFindMyDevice
    @State private var showSoundErrorInfo = false
    @ObservedObject var bluetoothData: BluetoothTempData
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    let notReachable: Bool

    var body: some View {
        let rightLabelColor = Color.mainColor.opacity(0.5)

        CustomSection(backgroundColor: Color.white.opacity(colorScheme.isLight ? 0.8 : 0.1)) {
            if !notReachable {
                LUIButton {
                    lightVibration()

                    if let eik = device.eik {
                        soundManager.playSound(eik: eik, bluetoothUUID: bluetoothData.identifier_background)
                    } else {
                        showAlert(title: "Sound Playback Failed", message: "You need to need to enter your credentials on the previous page to play a sound.")
                    }
                } label: {
                    HStack {
                        SettingsLabel(imageName: "speaker.wave.2.fill", text: "Play Sound", backgroundColor: .orange)
                            .fixedSize(horizontal: true, vertical: false)

                        ZStack(alignment: .trailing) {
                            HStack {
                                Text("Connecting...")
                                    .lineLimit(1)
                                    .foregroundColor(rightLabelColor)
                                    .padding(.trailing, 7)

                                LoadingIndicator()
                                    .frame(width: 18)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .opacity(soundManager.soundRequest ? 1 : 0)

                            Text("Playing...")
                                .lineLimit(1)
                                .foregroundColor(rightLabelColor)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .opacity(soundManager.playingSound ? 1 : 0)

                            if let error = soundManager.error {
                                Text(error.title)
                                    .lineLimit(1)
                                    .foregroundColor(rightLabelColor)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .alert(isPresented: $showSoundErrorInfo, content: {
                            Alert(title: Text(soundManager.error?.title ?? ""), message: Text(soundManager.error?.description ?? ""))
                        })

                        .onChange(of: soundManager.error) { val in
                            if val != nil {
                                showSoundErrorInfo = true
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
            }

            LUIButton {
                DispatchQueue.main.async {
                    presentationMode.wrappedValue.dismiss()
                }
            } label: {
                SettingsLabel(imageName: "xmark", text: "Close And Stop Searching", backgroundColor: .red)
            }
        }
        .padding(.bottom)
    }
}

struct Indicator: View {
    var pct: CGFloat
    let color: Color

    var body: some View {
        Color.clear
            .frame(height: 100)
            .modifier(PercentageIndicator(pct: pct, color: color))
            .padding(.horizontal)
    }
}

struct PercentageIndicator: AnimatableModifier {
    var pct: CGFloat = 0
    let color: Color

    var animatableData: CGFloat {
        get { pct }
        set { pct = newValue }
    }

    func body(content: Content) -> some View {
        content
            .overlay(LabelView(pct: pct, color: color))
    }

    struct ArcShape: Shape {
        let pct: CGFloat

        func path(in rect: CGRect) -> Path {
            var p = Path()

            p.addArc(center: CGPoint(x: rect.width / 2.0, y: rect.height / 2.0),
                     radius: rect.height / 2.0 + 5.0,
                     startAngle: .degrees(0),
                     endAngle: .degrees(360.0 * Double(pct)), clockwise: false)

            return p.strokedPath(.init(lineWidth: 10, lineCap: .round))
        }
    }

    struct LabelView: View {
        let pct: CGFloat
        let color: Color

        var body: some View {
            Text("\(Int(pct * 100))%")

                .font(.system(size: 100))
                .fontWeight(.ultraLight)
                .foregroundColor(color)
        }
    }
}

/// Specifies if a device is not currently reachable.
func deviceNotCurrentlyReachable(device: BluetoothTempData, currentDate _: Date, timeout: Int = Int(Constants.scanInterval * 2)) -> Bool {
    // If device was not seen in the last X seconds, device is not reachable
    device.last_update_publisher.isOlderThan(seconds: Double(timeout))
}
