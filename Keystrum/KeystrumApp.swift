//
//  KeystrumApp.swift
//  Keystrum
//
//  Created by Andrew Finke on 12/29/25.
//

import SwiftUI
import KeystrumCore

@main
struct KeystrumApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .navigationTitle("Keystrum")
        }
    }
}
