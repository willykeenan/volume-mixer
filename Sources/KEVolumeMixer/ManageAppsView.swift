import SwiftUI

struct ManageAppsView: View {
    @EnvironmentObject private var mixer: AudioMixer

    private var apps: [KnownApp] {
        mixer.manageableApps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Manage Apps")
                    .font(.title2.weight(.semibold))
                Text(
                    "Hide apps you do not want in the menu-bar mixer. A saved custom volume keeps applying until you reset or forget the app."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            if apps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("No apps yet").font(.headline)
                    Text("Apps appear after they open an audio session.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(apps) { app in
                        HStack(spacing: 10) {
                            icon(for: app)
                            Text(app.name)
                                .font(.system(size: 13))
                            Spacer()
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { !app.isHidden },
                                    set: {
                                        mixer.setHidden(!$0, for: app.id)
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityLabel("Show \(app.name)")
                        }
                        .padding(.vertical, 3)
                        .contextMenu {
                            Button("Forget This App") {
                                mixer.forget(key: app.id)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(width: 470, height: 520)
    }

    @ViewBuilder
    private func icon(for app: KnownApp) -> some View {
        if app.id == "system-sounds" {
            Image(systemName: "bell.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                )
        } else if let image = app.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
    }
}
