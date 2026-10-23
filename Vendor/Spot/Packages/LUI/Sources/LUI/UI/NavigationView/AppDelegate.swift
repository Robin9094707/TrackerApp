//
//  AppDelegate.swift
//
//
//  Created by Leon Böttger on 11.08.23.
//

import UIKit

public final class AppDelegate: UIResponder, UIApplicationDelegate {
    public func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        setNavigationBarColor()
        return true
    }

    override public func buildMenu(with builder: UIMenuBuilder) {
        if builder.system == .main {
            builder.remove(menu: .edit)
            builder.remove(menu: .format)
            builder.remove(menu: .help)
        }
    }
}
