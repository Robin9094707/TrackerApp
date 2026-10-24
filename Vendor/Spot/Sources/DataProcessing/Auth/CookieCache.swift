//
//  CookieCache.swift
//  Spot
//
//  Created by Leon Böttger on 12.12.24.
//

import Combine
import WebKit

final class CookieCache {
    // Callback adapters can execute their start closure on Swift's generic executor.
    // Every entry point must hop explicitly before touching WebKit, including at cold start.
    static func getAllCookies(completion: @escaping ([HTTPCookie]) -> Void) {
        DispatchQueue.main.async {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies(completion)
        }
    }

    static func removeOAuthCookie(value: String) {
        DispatchQueue.main.async {
            let store = WKWebsiteDataStore.default().httpCookieStore
            store.getAllCookies { cookies in
                for cookie in cookies where cookie.name == "oauth_token"
                    && ["accounts.google.com", ".google.com", "google.com"].contains(cookie.domain)
                    && cookie.value == value {
                    store.delete(cookie)
                }
            }
        }
    }

    static func clearWKWebViewCacheAndCookies(completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            let dataStore = WKWebsiteDataStore.default()

            // Get all types of data to be removed
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

            dataStore.fetchDataRecords(ofTypes: dataTypes) { _ in
                dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) {
                    completion()
                }
            }
        }
    }

    static func addCookies(cookies: [WebloginAuthResponse.WebloginCookies.Cookie], completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            addCookiesOnMain(cookies: cookies, completion: completion)
        }
    }

    private static func addCookiesOnMain(cookies: [WebloginAuthResponse.WebloginCookies.Cookie], completion: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let firstCookie = cookies.first {
            let domain = firstCookie.hasDomain ? firstCookie.domain : firstCookie.subDomain

            let cookieProperties: [HTTPCookiePropertyKey: Any] = [
                .name: firstCookie.cookieName,
                .value: firstCookie.cookieValue,
                .domain: domain,
                .path: firstCookie.path,
                .secure: firstCookie.secure,
                .maximumAge: firstCookie.maxAge,
                .version: 1,
            ]

            if let cookie = HTTPCookie(properties: cookieProperties) {
                WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) {
                    addCookies(cookies: Array(cookies.dropFirst()), completion: completion)
                }
            } else { addCookies(cookies: Array(cookies.dropFirst()), completion: completion) }
        } else {
            // dont need other cookies
            completion()
        }
    }
}
