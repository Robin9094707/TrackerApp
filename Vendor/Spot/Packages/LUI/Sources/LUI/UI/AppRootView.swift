//
//  AppRootView.swift
//
//
//  Created by Leon Böttger on 02.08.23.
//

import SwiftUI
import SwiftUIIntrospect
import UserNotifications

let navigationBarItemColor = Color.blue

public struct AppRootView<Content1: View, Content4: View, Content6: View>: View {
    private let phoneView: () -> Content1

    private let settingsView: Content4

    private let firstIntroductionView: () -> Content6

    @State private var opacity: Double = 0
    @StateObject private var luiSettings = LUISettings.sharedInstance

    @Environment(\.scenePhase) var scenePhase

    public init(
        @ViewBuilder phoneView: @escaping () -> Content1,
        @ViewBuilder settingsView: () -> Content4,
        @ViewBuilder firstIntroductionView: @escaping () -> Content6
    ) {
        self.phoneView = phoneView
        self.settingsView = settingsView()
        self.firstIntroductionView = firstIntroductionView
    }

    public var body: some View {
        let appLaunchedBefore = luiSettings.appLaunchedBefore

        SingleColumnRootView(
            phoneView: phoneView, firstIntroductionView: firstIntroductionView,
            appLaunchedBefore: appLaunchedBefore
        )
        .modifier(AlertOverlayModifier())
        .animation(.easeInOut(duration: 0.7), value: appLaunchedBefore)
        .animation(.easeInOut(duration: 0.7), value: luiSettings.canShowIntroductionSheet)
        .luiSheet(
            isPresented: $luiSettings.showSettings,
            content: {
                LUISettingsView(content: {
                    settingsView
                })
            }
        )

        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                opacity = 1
            }
        }
        .opacity(opacity)


        .accentColor(navigationBarItemColor)
    }
}

struct AlertOverlayModifier: ViewModifier {
    @ObservedObject var luiSettings = LUISettings.sharedInstance

    func body(content: Content) -> some View {
        content
            .background(
                Color.clear.alert(
                    isPresented: $luiSettings.showAlert,
                    content: {
                        Alert(
                            title: Text(luiSettings.alertTitle.localized()),
                            message: Text(luiSettings.alertMessage.localized())
                        )
                    }
                )
            )
    }
}

struct IntroductionSheet<Content: View>: View {
    let firstIntroductionView: () -> Content
    @State var showingIntroductionContent = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var luiSettings = LUISettings.sharedInstance

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isiPadOrMac() {
                    LinearGradient(colors: [.blue.opacity(0.12), .green.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .ignoresSafeArea(.all)
                        .opacity(showingIntroductionContent ? 0.9 : 0)
                        .allowsHitTesting(false)
                }

                IntroductionView(firstPagedView: firstIntroductionView())
                    .opacity(showingIntroductionContent ? 1 : 0)
                    .frame(
                        maxWidth: isiPadOrMac() ? min(geo.size.width * 0.8, 800) : .infinity,
                        maxHeight: isiPadOrMac() ? min(geo.size.height * 0.9, 700) : .infinity
                    )
                    .if(
                        isiPadOrMac(),
                        transform: { view in
                            view
                                .cornerRadius(30)
                        }
                    )
                    .onAppear {
                        runAfter(seconds: 1) {
                            withAnimation(.easeInOut(duration: 0.7)) {
                                showingIntroductionContent = true
                            }
                        }
                    }
            }
        }
        .compositingGroup()
        .transition(AnyTransition.blur)
        .zIndex(.infinity)
        .navigationViewStyle(.stack)
    }
}
