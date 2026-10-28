//
//  TV_appApp.swift
//  TV_app
//
//  Created by Francisca Moore on 27-10-26.
//

import SwiftUI

@main
struct TV_appApp: App {
    @State private var tv = TVState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(tv)
                .task { await startServer(tv) }
        }
    }
}
