//
//  TorSettingsView.swift
//  damus
//
//  Created for Tor mode support.
//

import SwiftUI
import Combine

/// Settings view for configuring Tor/SOCKS5 proxy for relay connections.
struct TorSettingsView: View {
    @ObservedObject var settings: UserSettingsStore
    #if !EXTENSION
    @ObservedObject private var artiClient = ArtiClient.shared
    #endif
    @State private var socks_port_text: String
    @State private var showRestartAlert = false
    @State private var pendingTorEnabled: Bool = false
    @Environment(\.dismiss) var dismiss

    init(settings: UserSettingsStore) {
        self._settings = ObservedObject(initialValue: settings)
        _socks_port_text = State(initialValue: String(settings.tor_socks_port))
    }

    var body: some View {
        Form {
            Section(
                header: Text("Tor Mode", comment: "Section header for Tor mode settings"),
                footer: Text("Route all traffic through the Tor network for enhanced privacy. Requires app restart to take effect.", comment: "Explanation of what Tor mode does")
            ) {
                Toggle(
                    NSLocalizedString("Enable Tor", comment: "Toggle to enable Tor mode for relay connections"),
                    isOn: Binding(
                        get: { settings.tor_enabled },
                        set: { newValue in
                            pendingTorEnabled = newValue
                            showRestartAlert = true
                        }
                    )
                )
                .toggleStyle(.switch)
            }

            #if !EXTENSION
            if settings.tor_enabled {
                Section(
                    header: Text("Arti Status", comment: "Section header for Arti Tor client status"),
                    footer: artiStatusFooter
                ) {
                    HStack {
                        Text("Status", comment: "Label for Arti status")
                        Spacer()
                        HStack(spacing: 8) {
                            artiStatusIndicator
                            Text(artiClient.state.description)
                                .foregroundColor(.secondary)
                        }
                    }

                    if artiClient.isRunning {
                        HStack {
                            Text("SOCKS Port", comment: "Label for Arti SOCKS port")
                            Spacer()
                            Text("\(artiClient.socksPort)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(
                    header: Text("Advanced", comment: "Section header for advanced Tor settings"),
                    footer: Text("Configure fallback SOCKS5 proxy for when embedded Tor is unavailable.", comment: "Help text for fallback proxy settings")
                ) {
                    HStack {
                        Text("Host", comment: "Label for SOCKS proxy host field")
                        Spacer()
                        TextField("127.0.0.1", text: $settings.tor_socks_host)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    HStack {
                        Text("Port", comment: "Label for SOCKS proxy port field")
                        Spacer()
                        TextField("9050", text: $socks_port_text)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .onReceive(Just(socks_port_text)) { newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                guard !filtered.isEmpty,
                                      let port = Int(filtered),
                                      port > 0,
                                      port <= 65535
                                else {
                                    return
                                }
                                socks_port_text = filtered
                                settings.tor_socks_port = port
                            }
                    }
                }
            }
            #endif

            if settings.tor_enabled {
                Section(
                    footer: Text("Media and images will load slower over Tor. Large files may timeout.", comment: "Warning about Tor performance")
                ) {
                    EmptyView()
                }
            }
        }
        .navigationTitle(NSLocalizedString("Tor", comment: "Navigation title for Tor settings"))
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
        .alert(
            pendingTorEnabled
                ? NSLocalizedString("Enable Tor Mode?", comment: "Alert title for enabling Tor")
                : NSLocalizedString("Disable Tor Mode?", comment: "Alert title for disabling Tor"),
            isPresented: $showRestartAlert
        ) {
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                // Don't change the setting
            }
            Button(NSLocalizedString("Apply & Close App", comment: "Apply changes and close app button for Tor toggle")) {
                settings.tor_enabled = pendingTorEnabled
                applyAndRequestClose()
            }
        } message: {
            if pendingTorEnabled {
                Text("Tor mode requires an app restart. Please close and reopen the app after applying.", comment: "Alert message for enabling Tor")
            } else {
                Text("Disabling Tor requires an app restart. Please close and reopen the app after applying.", comment: "Alert message for disabling Tor")
            }
        }
    }

    #if !EXTENSION
    @ViewBuilder
    private var artiStatusIndicator: some View {
        switch artiClient.state {
        case .stopped:
            Circle()
                .fill(Color.gray)
                .frame(width: 10, height: 10)
        case .starting:
            ProgressView()
                .scaleEffect(0.7)
        case .running:
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
        case .stopping:
            ProgressView()
                .scaleEffect(0.7)
        }
    }

    private var artiStatusFooter: Text {
        switch artiClient.state {
        case .stopped:
            return Text("Tor is not running.", comment: "Footer when Tor is stopped")
        case .starting:
            return Text("Connecting to the Tor network...", comment: "Footer when Tor is starting")
        case .running:
            return Text("Connected to Tor. All traffic is being routed anonymously.", comment: "Footer when Tor is running")
        case .stopping:
            return Text("Disconnecting from Tor...", comment: "Footer when Tor is stopping")
        }
    }
    #endif

    /// Applies settings and notifies user to manually close the app.
    /// We don't call exit(0) as it violates App Store guidelines.
    private func applyAndRequestClose() {
        // Settings are auto-persisted by UserDefaults
        // Dismiss the view - user will need to manually close and reopen
        dismiss()
    }
}

struct TorSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TorSettingsView(settings: UserSettingsStore())
        }
    }
}
