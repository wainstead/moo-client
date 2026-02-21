import SwiftUI

public struct IOSChatView: View {
    @ObservedObject private var viewModel: IOSChatViewModel

    public init(viewModel: IOSChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.isConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundStyle(viewModel.isConnected ? .green : .orange)
                Spacer()
                Button("Ping") { viewModel.ping() }
            }
            .padding(8)

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Occupants")
                        .font(.headline)
                    List(viewModel.occupants, id: \.self) { who in
                        Text(who)
                    }
                }
                .frame(minWidth: 120)
                .padding(8)

                Divider()

                List {
                    ForEach(viewModel.chatMessages) { chat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.speaker).font(.subheadline.weight(.semibold))
                            Text(chat.message)
                        }
                    }
                    ForEach(viewModel.systemMessages) { line in
                        Text(line.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                TextField("Type message", text: $viewModel.inputText)
                    .textFieldStyle(.roundedBorder)
                Button("Send") { viewModel.sendInput() }
            }
            .padding(8)
        }
    }
}
