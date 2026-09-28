import AppKit
import SwiftUI

@main
struct KEVolumeMixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var mixer = AudioMixer.shared

    var body: some Scene {
        MenuBarExtra {
            MixerView()
                .environmentObject(mixer)
        } label: {
            Label(
                "KE Volume Mixer",
                systemImage:
                    mixer.hasAudibleApps
                    ? "waveform.circle.fill"
                    : "speaker.wave.2"
            )
            .labelStyle(.iconOnly)
            .accessibilityLabel(
                mixer.hasAudibleApps
                    ? "\(mixer.audibleAppCount) apps making sound"
                    : "KE Volume Mixer"
            )
        }
        .menuBarExtraStyle(.window)

        Window("Manage Apps", id: "manage-apps") {
            ManageAppsView()
                .environmentObject(mixer)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var diagnosticWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard ProcessInfo.processInfo.arguments.contains("--open-window")
        else { return }

        let controller = NSHostingController(
            rootView: MixerView()
                .environmentObject(AudioMixer.shared)
        )
        let window = NSWindow(contentViewController: controller)
        window.title = "KE Volume Mixer"
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
        ]
        window.setContentSize(NSSize(width: 360, height: 560))
        window.center()
        window.makeKeyAndOrderFront(nil)
        diagnosticWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
