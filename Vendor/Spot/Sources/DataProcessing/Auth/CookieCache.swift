//
//  CookieCache.swift
//  Spot
//
//  Created by Leon Böttger on 12.12.24.
//

import Combine
import WebKit

class CookieCache {
    static func clearWKWebViewCacheAndCookies(completion: @escaping () -> Void) {
        let dataStore = WKWebsiteDataStore.default()

        // Get all types of data to be removed
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        dataStore.fetchDataRecords(ofTypes: dataTypes) { _ in
            dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) {
                completion()
            }
        }
    }

    static func addCookies(cookies: [WebloginAuthResponse.WebloginCookies.Cookie], completion: @escaping () -> Void) {
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
