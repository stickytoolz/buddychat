import SwiftUI

struct SignOnView: View {
    @EnvironmentObject var store: ChatStore
    @State private var screenName = ""
    @State private var password = ""
    @State private var savePassword = true
    @State private var error: String?
    @State private var showSignUp = false

    var body: some View {
        RetroWindow(title: "Sign On", icon: "person.crop.circle.fill") {
            ScrollView {
                VStack(spacing: 14) {
                    BuddyMascot(size: 130).padding(.top, 18)
                    Text("BuddyChat").font(.custom("Verdana-Bold", size: 28)).foregroundStyle(Retro.ink)

                    VStack(alignment: .leading, spacing: 12) {
                        RetroField(label: "Screen Name", text: $screenName)
                        RetroField(label: "Password", text: $password, secure: true)
                        Toggle(isOn: $savePassword) { Text("Save password").font(Retro.body(13)).foregroundStyle(Retro.ink) }
                            .toggleStyle(CheckboxStyle())
                        Toggle(isOn: $store.autoSignOn) { Text("Auto-sign on").font(Retro.body(13)).foregroundStyle(Retro.ink) }
                            .toggleStyle(CheckboxStyle())
                    }
                    .padding(.horizontal, 24)

                    if let error {
                        Text(error).font(Retro.body(12)).foregroundStyle(.red).padding(.horizontal, 24)
                    }

                    HStack {
                        Button("New? Sign Up") { showSignUp = true }
                            .buttonStyle(RetroButtonStyle())
                        Spacer()
                        if store.phase == .signingOn {
                            ProgressView().padding(.trailing, 8)
                            Text("Signing on…").font(Retro.body(13)).foregroundStyle(Retro.ink)
                        } else {
                            Button("Sign On") { signOn() }
                                .buttonStyle(RetroButtonStyle(bold: true))
                                .disabled(screenName.isEmpty || password.isEmpty)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
        }
        .padding(16)
        .onAppear {
            screenName = store.lastScreenName
            if let data = Keychain.get("password"), let p = String(data: data, encoding: .utf8) { password = p }
        }
        .sheet(isPresented: $showSignUp) { SignUpView() }
    }

    private func signOn() {
        error = nil
        Keychain.set(savePassword ? password.data(using: .utf8) : nil, for: "password")
        Task {
            do { try await store.signIn(screenName: screenName, password: password) }
            catch {
                self.error = error.localizedDescription
                    + (error.localizedDescription.hasPrefix("Incorrect") ? " New here? Tap \"New? Sign Up\"." : "")
            }
        }
    }
}

struct SignUpView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var screenName = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.5, blue: 0.5).ignoresSafeArea()
            RetroWindow(title: "Get a Screen Name", icon: "person.badge.plus") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Pick your screen name. This is the name your homies will see and use to add you.")
                            .font(Retro.body(13)).foregroundStyle(Retro.ink)
                        RetroField(label: "Screen Name (3–16 letters or numbers)", text: $screenName)
                        RetroField(label: "Password (at least 6 characters)", text: $password, secure: true)
                        RetroField(label: "Confirm Password", text: $confirm, secure: true)
                        Text("Write your password down — there's no email, so it can't be reset.")
                            .font(Retro.body(11)).foregroundStyle(Retro.dark)
                        if let error { Text(error).font(Retro.body(12)).foregroundStyle(.red) }
                        HStack {
                            Button("Cancel") { dismiss() }.buttonStyle(RetroButtonStyle())
                            Spacer()
                            if working { ProgressView() }
                            Button("Create") { create() }
                                .buttonStyle(RetroButtonStyle(bold: true))
                                .disabled(working)
                        }
                    }
                    .padding(20)
                }
            }
            .padding(16)
        }
    }

    private func create() {
        error = nil
        guard password.count >= 6 else { error = "Password must be at least 6 characters."; return }
        guard password == confirm else { error = "The passwords don't match."; return }
        working = true
        Task {
            do {
                Keychain.set(password.data(using: .utf8), for: "password")
                try await store.signUp(screenName: screenName, password: password)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    Rectangle().fill(Retro.field).frame(width: 16, height: 16).bevel(sunken: true)
                    if configuration.isOn {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Retro.ink)
                    }
                }
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}
