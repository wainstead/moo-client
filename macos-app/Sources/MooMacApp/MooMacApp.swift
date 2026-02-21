import SwiftUI

@main
struct MooMacApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("moo-client") {
            ContentView(viewModel: viewModel)
                .onAppear { viewModel.connect() }
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Connect") { viewModel.connect() }
                Button("Disconnect") { viewModel.disconnect() }
                Spacer()
            }
            .padding(10)

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Occupants")
                        .font(.headline)
                    List(viewModel.occupants, id: \.self) { who in
                        Text(who)
                    }
                }
                .frame(minWidth: 200)
                .padding(10)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Messages")
                        .font(.headline)

                    List {
                        ForEach(viewModel.chats) { chat in
                            HStack(alignment: .top) {
                                Text(chat.speaker)
                                    .font(.system(.body, design: .monospaced).weight(.bold))
                                    .frame(width: 120, alignment: .leading)
                                Text(chat.message)
                                    .textSelection(.enabled)
                            }
                        }

                        ForEach(viewModel.systems) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(10)
            }

            Divider()

            HStack {
                TextField("Type message", text: $viewModel.input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.sendInput() }
                Button("Send") { viewModel.sendInput() }
            }
            .padding(10)
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}
