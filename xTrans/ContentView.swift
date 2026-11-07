//
//  ContentView.swift
//  xTrans
//
//  Created by VienLv on 7/11/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MainView()
            .frame(minWidth: 520, minHeight: 420)
    }
}

#Preview {
    let settings = SettingsStore(persistence: nil, accounts: SettingsStore.previewAccounts)
    ContentView()
        .environment(ChatStore(service: MockTranslationService(), settings: settings, persistence: nil))
        .environment(settings)
        .frame(width: 1100, height: 720)
}
