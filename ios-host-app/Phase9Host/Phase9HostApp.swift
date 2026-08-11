import OSLog
import SwiftUI
import MooIOSRelay
import MooIOSUI

@main
struct Phase9HostApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = IOSChatViewModel()

    private let logger = Logger(subsystem: "local.moo.Phase9Host", category: "phase9")
    private let stateStore = UserDefaultsRelayStateStore(namespace: Phase9HostConfig.stateNamespace)
    private let wsURL = Phase9HostConfig.webSocketURL

    var body: some Scene {
        WindowGroup {
            Phase9HostRootView(viewModel: viewModel, wsURL: wsURL, logger: logger)
                .onAppear {
                    logger.info("phase9 host appear offset=\(viewModel.currentOffset, privacy: .public)")
                    viewModel.connect(wsURL: wsURL, stateStore: stateStore)
                }
                .onChange(of: scenePhase) { phase in
                    logger.info("scene phase \(String(describing: phase), privacy: .public) offset=\(viewModel.currentOffset, privacy: .public)")
                    if phase == .active {
                        viewModel.reconnect(wsURL: wsURL, stateStore: stateStore)
                    }
                }
        }
    }
}

private struct Phase9HostRootView: View {
    @ObservedObject var viewModel: IOSChatViewModel

    let wsURL: URL
    let logger: Logger

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            IOSChatView(viewModel: viewModel)
                .frame(maxHeight: .infinity)
            Divider()
            debugLog
        }
        .onChange(of: viewModel.debugEvents) { events in
            guard let event = events.last else { return }
            logger.info("event offset=\(event.offset, privacy: .public) \(event.text, privacy: .public)")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(viewModel.isConnected ? "Connected" : "Disconnected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.isConnected ? .green : .orange)
                Spacer()
                Text("offset \(viewModel.currentOffset)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(wsURL.absoluteString)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private var debugLog: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Phase 9 Events")
                .font(.caption.weight(.semibold))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(viewModel.debugEvents.suffix(80)) { event in
                        Text("\(timeString(event.timestamp))  \(event.offset)  \(event.text)")
                            .font(.caption2.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(8)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
