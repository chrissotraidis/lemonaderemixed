import SwiftUI

/// What the app is doing before the game is on screen.
final class SetupModel: ObservableObject {
    enum Phase: Equatable {
        case chooseInstaller
        case working(String)
        case needsKey(error: String?)
        case failed(String)
    }
    @Published var phase: Phase = .working("Starting…")
    @Published var name = ""
    @Published var key = ""
    var onChoose: () -> Void = {}
    var onRegister: (String, String) -> Void = { _, _ in }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(spacing: 18) {
            Text("Lemonade Remixed").font(.system(size: 34, weight: .heavy, design: .rounded))
            switch model.phase {
            case .chooseInstaller:
                Text("Lemonade Remixed plays the original Lemonade Tycoon Deluxe from your own copy. Choose its installer, Setup.exe, to set it up.")
                    .multilineTextAlignment(.center).frame(maxWidth: 440)
                Button("Choose Setup.exe…", action: model.onChoose).controlSize(.large).keyboardShortcut(.defaultAction)
            case .working(let message):
                ProgressView()
                Text(message).foregroundStyle(.secondary)
            case .needsKey(let error):
                Text("Enter the registration name and key that came with your copy.")
                    .multilineTextAlignment(.center).frame(maxWidth: 440)
                Form {
                    TextField("Name", text: $model.name)
                    TextField("Key", text: $model.key)
                }
                .frame(maxWidth: 360)
                if let error { Text(error).foregroundStyle(.red) }
                Button("Register") { model.onRegister(model.name, model.key) }
                    .controlSize(.large).keyboardShortcut(.defaultAction)
                    .disabled(model.name.isEmpty || model.key.isEmpty)
            case .failed(let message):
                Text(message).multilineTextAlignment(.center).frame(maxWidth: 440)
                Button("Choose Setup.exe…", action: model.onChoose)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.24, green: 0.55, blue: 0.24).opacity(0.25))
    }
}
