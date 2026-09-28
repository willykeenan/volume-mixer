import AppKit
import SwiftUI

struct MixerView: View {
    @EnvironmentObject private var mixer: AudioMixer
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var launchAtLoginDetail =
        LaunchAtLoginService.statusDetail
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().padding(.horizontal, 14)

            if mixer.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(mixer.entries) { entry in
                            AppVolumeRow(entry: entry)
                            if entry.id != mixer.entries.last?.id {
                                Divider().padding(.horizontal, 14)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 440)
            }

            if let error = mixer.lastError {
                Divider().padding(.horizontal, 14)
                errorCard(error)
            }

            Divider().padding(.horizontal, 14)
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 360)
        .onAppear {
            mixer.refresh()
            refreshLaunchAtLoginStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Volume Mixer")
                    .font(.system(size: 15, weight: .semibold))
                Text(activitySummary)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        mixer.hasAudibleApps ? Color.green : Color.secondary
                    )
            }

            Spacer()

            Menu {
                Text("Output: \(mixer.outputDeviceName)")
                Divider()
                Button("Manage Apps…") {
                    openWindow(id: "manage-apps")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Toggle(
                    LaunchAtLoginService.usesPreviewFallback
                        ? "Launch at Login (Preview)"
                        : "Launch at Login",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: configureLaunchAtLogin
                    )
                )
                if let detail = launchAtLoginDetail {
                    Text(detail)
                }
                if let error = launchAtLoginError {
                    Text(error)
                }
                Divider()
                Button("KE Studios") {
                    mixer.openKEStudios()
                }
                Button("Quit KE Volume Mixer") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Volume Mixer options")
        }
    }

    private var activitySummary: String {
        switch mixer.audibleAppCount {
        case 0:
            return "Listening for app audio"
        case 1:
            return "1 app making sound"
        default:
            return "\(mixer.audibleAppCount) apps making sound"
        }
    }

    private func configureLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLoginStatus()
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLogin = LaunchAtLoginService.isEnabled
        launchAtLoginDetail = LaunchAtLoginService.statusDetail
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No app audio sessions")
                .font(.callout.weight(.medium))
            Text("Start audio in an app and it will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Audio access needed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Privacy & Security") {
                mixer.openPrivacySettings()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.link)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 10))
            Text("Processed locally · never saved or sent")
                .font(.system(size: 10))
            Spacer()
            Button("KE Studios") {
                mixer.openKEStudios()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(.tertiary)
    }
}

private struct AppVolumeRow: View {
    @EnvironmentObject private var mixer: AudioMixer
    let entry: AppVolumeEntry

    private var volumeBinding: Binding<Float> {
        Binding(
            get: { entry.volume },
            set: { mixer.setVolume($0, for: entry.id) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                iconView
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(
                                entry.isAudible
                                    ? Color.green
                                    : Color.secondary.opacity(0.35)
                            )
                            .frame(width: 5, height: 5)
                        Text(
                            entry.isAudible
                                ? "Making sound"
                                : "Audio session idle"
                        )
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(Int((entry.volume * 100).rounded()))%")
                    .font(
                        .system(size: 11, weight: .medium)
                        .monospacedDigit()
                    )
                    .foregroundStyle(.secondary)
            }

            LevelMeter(level: entry.level, isAudible: entry.isAudible)

            HStack(spacing: 8) {
                Button {
                    mixer.toggleMute(for: entry.id)
                } label: {
                    Image(
                        systemName:
                            entry.volume <= 0.001
                            ? "speaker.slash.fill"
                            : "speaker.wave.2.fill"
                    )
                    .font(.system(size: 11))
                    .frame(width: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    entry.volume <= 0.001 ? Color.orange : Color.secondary
                )
                .help(entry.volume <= 0.001 ? "Unmute" : "Mute")
                .accessibilityLabel(
                    entry.volume <= 0.001
                        ? "Unmute \(entry.name)"
                        : "Mute \(entry.name)"
                )

                Slider(value: volumeBinding, in: 0...1)
                    .controlSize(.small)
                    .accessibilityLabel("\(entry.name) volume")
                    .accessibilityValue(
                        "\(Int((entry.volume * 100).rounded())) percent"
                    )

                Button {
                    mixer.resetVolume(for: entry.id)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    entry.volume == 1 ? Color.gray.opacity(0.35) : .secondary
                )
                .disabled(entry.volume == 1)
                .help("Reset \(entry.name) to 100%")
                .accessibilityLabel("Reset \(entry.name) volume")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var iconView: some View {
        if entry.isSystemSounds {
            Image(systemName: "bell.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                )
        } else if let icon = entry.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
    }
}

private struct LevelMeter: View {
    let level: Float
    let isAudible: Bool

    private var displayedLevel: CGFloat {
        CGFloat(AudioMath.meterFraction(for: level))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .green.opacity(0.85),
                                .mint,
                                .yellow.opacity(0.9),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: max(
                            isAudible ? 2 : 0,
                            geometry.size.width * displayedLevel
                        )
                    )
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
