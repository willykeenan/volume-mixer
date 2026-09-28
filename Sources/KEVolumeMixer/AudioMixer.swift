import AppKit
import CoreAudio
import Foundation
import os

struct AppVolumeEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage?
    let isSystemSounds: Bool
    var volume: Float
    var level: Float
    var isAudible: Bool
    var objectIDs: [AudioObjectID]

    static func == (lhs: AppVolumeEntry, rhs: AppVolumeEntry) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.volume == rhs.volume
            && lhs.level == rhs.level
            && lhs.isAudible == rhs.isAudible
            && lhs.objectIDs == rhs.objectIDs
            && lhs.icon === rhs.icon
    }
}

struct KnownApp: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage?
    let isHidden: Bool
}

@MainActor
final class AudioMixer: NSObject, ObservableObject {
    static let shared = AudioMixer()

    private static let logger = Logger(
        subsystem: "dev.kestudios.volume-mixer",
        category: "AudioMixer"
    )
    private static let volumesDefaultsKey = "perAppVolumes"
    private static let lastAudibleVolumesDefaultsKey = "lastAudibleVolumes"
    private static let hiddenKeysDefaultsKey = "hiddenAppKeys"
    private static let knownAppsDefaultsKey = "knownAppNames"
    private static let systemSoundsKey = "system-sounds"

    @Published private(set) var entries: [AppVolumeEntry] = []
    @Published private(set) var hasAudibleApps = false
    @Published private(set) var audibleAppCount = 0
    @Published private(set) var outputDeviceName = "Default Output"
    @Published var lastError: String?
    @Published private(set) var hiddenKeys: Set<String>
    @Published private(set) var knownAppNames: [String: String]

    private var taps: [String: ProcessTap] = [:]
    private var tapEntries: [String: AppVolumeEntry] = [:]
    private var savedVolumes: [String: Float]
    private var lastAudibleVolumes: [String: Float]
    private var refreshTimer: Timer?
    private var meterTimer: Timer?
    private var iconCache: [String: NSImage] = [:]
    private var tapRetryAfter: [String: Date] = [:]
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var serviceRestartListener: AudioObjectPropertyListenerBlock?

    override init() {
        let rawVolumes =
            UserDefaults.standard.dictionary(
                forKey: Self.volumesDefaultsKey
            ) as? [String: Double] ?? [:]
        savedVolumes = rawVolumes.mapValues { Float($0) }

        let rawLastVolumes =
            UserDefaults.standard.dictionary(
                forKey: Self.lastAudibleVolumesDefaultsKey
            ) as? [String: Double] ?? [:]
        lastAudibleVolumes = rawLastVolumes.mapValues { Float($0) }

        hiddenKeys = Set(
            UserDefaults.standard.stringArray(
                forKey: Self.hiddenKeysDefaultsKey
            ) ?? []
        )
        knownAppNames =
            UserDefaults.standard.dictionary(
                forKey: Self.knownAppsDefaultsKey
            ) as? [String: String] ?? [:]

        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        refresh()
        installListeners()

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 2,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        meterTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshLevels() }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        refreshTimer?.invalidate()
        meterTimer?.invalidate()
    }

    @objc private func applicationWillTerminate() {
        shutdown()
    }

    func shutdown() {
        Self.logger.info("Graceful shutdown started")
        refreshTimer?.invalidate()
        meterTimer?.invalidate()
        refreshTimer = nil
        meterTimer = nil
        for key in Array(taps.keys) {
            taps[key]?.invalidate()
            taps.removeValue(forKey: key)
        }
        tapEntries.removeAll()
        removeListeners()
        Self.logger.info("Graceful shutdown complete")
    }

    func setVolume(_ volume: Float, for key: String) {
        let clamped = min(max(volume, 0), 1)
        if clamped > 0.01 {
            lastAudibleVolumes[key] = clamped
            persistLastAudibleVolumes()
        }

        if clamped == 1 {
            savedVolumes.removeValue(forKey: key)
        } else {
            savedVolumes[key] = clamped
        }
        persistVolumes()

        if var entry = tapEntries[key] {
            entry.volume = clamped
            tapEntries[key] = entry
        }
        if let index = entries.firstIndex(where: { $0.id == key }) {
            entries[index].volume = clamped
        }

        if let tap = taps[key] {
            tap.gain = clamped
        } else if let entry = tapEntries[key] {
            createTap(for: entry)
        }
    }

    func toggleMute(for key: String) {
        guard let entry = tapEntries[key] else { return }
        if entry.volume <= 0.001 {
            setVolume(lastAudibleVolumes[key] ?? 1, for: key)
        } else {
            lastAudibleVolumes[key] = entry.volume
            persistLastAudibleVolumes()
            setVolume(0, for: key)
        }
    }

    func resetVolume(for key: String) {
        setVolume(1, for: key)
    }

    var manageableApps: [KnownApp] {
        knownAppNames.map { key, name in
            KnownApp(
                id: key,
                name: name,
                icon: managementIcon(for: key),
                isHidden: hiddenKeys.contains(key)
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
    }

    func setHidden(_ hidden: Bool, for key: String) {
        if hidden {
            hiddenKeys.insert(key)
        } else {
            hiddenKeys.remove(key)
        }
        UserDefaults.standard.set(
            Array(hiddenKeys),
            forKey: Self.hiddenKeysDefaultsKey
        )
        refresh()
    }

    func forget(key: String) {
        knownAppNames.removeValue(forKey: key)
        hiddenKeys.remove(key)
        savedVolumes.removeValue(forKey: key)
        lastAudibleVolumes.removeValue(forKey: key)
        persistKnownApps()
        persistVolumes()
        persistLastAudibleVolumes()
        UserDefaults.standard.set(
            Array(hiddenKeys),
            forKey: Self.hiddenKeysDefaultsKey
        )
        taps[key]?.invalidate()
        taps.removeValue(forKey: key)
        refresh()
    }

    func openPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openKEStudios() {
        guard let url = URL(string: "https://github.com/willykeenan/volume-mixer")
        else { return }
        NSWorkspace.shared.open(url)
    }

    func refresh() {
        struct Group {
            var objectIDs: [AudioObjectID] = []
            var pids: [pid_t] = []
        }

        if let outputDevice = CoreAudioUtils.defaultOutputDevice() {
            outputDeviceName =
                CoreAudioUtils.deviceName(outputDevice) ?? "Default Output"
        }

        var groups: [String: Group] = [:]
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for object in CoreAudioUtils.processObjectList() {
            guard let pid = CoreAudioUtils.pid(of: object),
                  pid != pid_t(ownPID) else {
                continue
            }
            let key = groupKey(
                bundleID: CoreAudioUtils.bundleID(of: object),
                pid: pid
            )
            var group = groups[key] ?? Group()
            group.objectIDs.append(object)
            group.pids.append(pid)
            groups[key] = group
        }

        var visibleEntries: [AppVolumeEntry] = []
        var nextTapEntries: [String: AppVolumeEntry] = [:]
        var knownChanged = false

        for (key, group) in groups {
            let customVolume = (savedVolumes[key] ?? 1) != 1
            let isSystemSounds = key == Self.systemSoundsKey
            let eligible =
                isSystemSounds
                || customVolume
                || appActivationPolicy(for: key, pids: group.pids) == .regular
            guard eligible else { continue }

            let (name, icon) = displayInfo(for: key, pids: group.pids)
            if knownAppNames[key] != name {
                knownAppNames[key] = name
                knownChanged = true
            }

            let existingLevel = taps[key]?.audioLevel ?? 0
            let entry = AppVolumeEntry(
                id: key,
                name: name,
                icon: icon,
                isSystemSounds: isSystemSounds,
                volume: savedVolumes[key] ?? 1,
                level: existingLevel,
                isAudible: AudioMath.isSignalActive(existingLevel),
                objectIDs: Array(Set(group.objectIDs)).sorted()
            )

            if !hiddenKeys.contains(key) || customVolume {
                nextTapEntries[key] = entry
            }
            if !hiddenKeys.contains(key) {
                visibleEntries.append(entry)
            }
        }

        if knownChanged {
            persistKnownApps()
        }

        visibleEntries.sort {
            if $0.isSystemSounds != $1.isSystemSounds {
                return !$0.isSystemSounds
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
        tapEntries = nextTapEntries

        if visibleEntries != entries {
            entries = visibleEntries
        }

        syncTaps()
        refreshLevels()
    }

    private func refreshLevels() {
        var updated = entries
        var changed = false
        var count = 0

        for index in updated.indices {
            let level = taps[updated[index].id]?.audioLevel ?? 0
            let audible = AudioMath.isSignalActive(level)
            if audible { count += 1 }
            if abs(updated[index].level - level) > 0.001
                || updated[index].isAudible != audible {
                updated[index].level = level
                updated[index].isAudible = audible
                changed = true
            }
        }

        if changed {
            entries = updated
        }
        if audibleAppCount != count {
            audibleAppCount = count
        }
        let anyAudible = count > 0
        if hasAudibleApps != anyAudible {
            hasAudibleApps = anyAudible
        }
    }

    private func syncTaps() {
        let wantedKeys = Set(tapEntries.keys)
        for key in Array(taps.keys) where !wantedKeys.contains(key) {
            taps[key]?.invalidate()
            taps.removeValue(forKey: key)
            tapRetryAfter.removeValue(forKey: key)
        }

        for (key, entry) in tapEntries {
            if let existing = taps[key] {
                existing.gain = entry.volume
                if existing.processObjectIDs != entry.objectIDs,
                   !entry.objectIDs.isEmpty {
                    existing.invalidate()
                    taps.removeValue(forKey: key)
                    createTap(for: entry)
                }
            } else if !entry.objectIDs.isEmpty {
                createTap(for: entry)
            }
        }
    }

    private func createTap(for entry: AppVolumeEntry) {
        if let retryAt = tapRetryAfter[entry.id], retryAt > Date() {
            return
        }
        guard !entry.objectIDs.isEmpty else { return }

        do {
            let tap = try ProcessTap(
                processObjectIDs: entry.objectIDs,
                name: entry.name,
                initialGain: entry.volume
            )
            taps[entry.id] = tap
            tapRetryAfter.removeValue(forKey: entry.id)
            if taps.count == tapEntries.count {
                lastError = nil
            }
        } catch {
            Self.logger.error(
                "Tap failed for \(entry.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            tapRetryAfter[entry.id] = Date().addingTimeInterval(8)
            lastError = error.localizedDescription
        }
    }

    private func rebuildAllTaps(reason: String) {
        Self.logger.info(
            "Rebuilding taps: \(reason, privacy: .public)"
        )
        for key in Array(taps.keys) {
            taps[key]?.invalidate()
            taps.removeValue(forKey: key)
        }
        tapRetryAfter.removeAll()
        refresh()
    }

    private func groupKey(bundleID: String?, pid: pid_t) -> String {
        let processName =
            CoreAudioUtils.processName(pid: pid)?.lowercased() ?? ""
        let lowerBundle = bundleID?.lowercased() ?? ""
        if lowerBundle.contains("systemsound")
            || processName.contains("systemsound")
            || processName == "coreaudiod" {
            return Self.systemSoundsKey
        }

        guard var bundleID, !bundleID.isEmpty else {
            let name = processName.isEmpty ? "unknown-\(pid)" : processName
            return "pid-name:\(name)"
        }

        let explicit: [String: String] = [
            "com.apple.WebKit.GPU": "com.apple.Safari",
            "com.apple.WebKit.WebContent": "com.apple.Safari",
        ]
        if let mapped = explicit[bundleID] {
            return mapped
        }

        var components = bundleID.components(separatedBy: ".")
        while let last = components.last, components.count > 2 {
            let lower = last.lowercased()
            guard lower.contains("helper")
                || lower == "renderer"
                || lower == "plugin" else {
                break
            }
            components.removeLast()
        }
        bundleID = components.joined(separator: ".")
        return bundleID
    }

    private func displayInfo(
        for key: String,
        pids: [pid_t]
    ) -> (String, NSImage?) {
        if key == Self.systemSoundsKey {
            return ("System Sounds", nil)
        }
        if let app = runningApp(for: key, pids: pids) {
            if let icon = app.icon {
                iconCache[key] = icon
            }
            return (
                app.localizedName ?? knownAppNames[key] ?? key,
                app.icon ?? iconCache[key]
            )
        }
        if key.hasPrefix("pid-name:") {
            return (
                String(key.dropFirst("pid-name:".count)),
                iconCache[key]
            )
        }
        return (
            knownAppNames[key]
                ?? key.components(separatedBy: ".").last
                ?? key,
            managementIcon(for: key)
        )
    }

    private func appActivationPolicy(
        for key: String,
        pids: [pid_t]
    ) -> NSApplication.ActivationPolicy? {
        runningApp(for: key, pids: pids)?.activationPolicy
    }

    private func runningApp(
        for key: String,
        pids: [pid_t]
    ) -> NSRunningApplication? {
        if let app =
            NSRunningApplication.runningApplications(
                withBundleIdentifier: key
            ).first {
            return app
        }
        for pid in pids {
            if let app = NSRunningApplication(processIdentifier: pid) {
                return app
            }
        }
        return nil
    }

    private func managementIcon(for key: String) -> NSImage? {
        if key == Self.systemSoundsKey { return nil }
        if let cached = iconCache[key] { return cached }
        if let app =
            NSRunningApplication.runningApplications(
                withBundleIdentifier: key
            ).first,
           let icon = app.icon {
            iconCache[key] = icon
            return icon
        }
        if let url =
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: key
            ) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            iconCache[key] = icon
            return icon
        }
        return nil
    }

    private func installListeners() {
        guard processListListener == nil,
              defaultOutputListener == nil,
              serviceRestartListener == nil else {
            return
        }

        let processListener: AudioObjectPropertyListenerBlock = {
            [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        processListListener = processListener
        var processList = CoreAudioUtils.address(
            kAudioHardwarePropertyProcessObjectList
        )
        let processStatus = AudioObjectAddPropertyListenerBlock(
            CoreAudioUtils.systemObject,
            &processList,
            .main,
            processListener
        )

        let outputListener: AudioObjectPropertyListenerBlock = {
            [weak self] _, _ in
            Task { @MainActor in
                self?.rebuildAllTaps(reason: "default output changed")
            }
        }
        defaultOutputListener = outputListener
        var defaultOutput = CoreAudioUtils.address(
            kAudioHardwarePropertyDefaultOutputDevice
        )
        let outputStatus = AudioObjectAddPropertyListenerBlock(
            CoreAudioUtils.systemObject,
            &defaultOutput,
            .main,
            outputListener
        )

        let restartListener: AudioObjectPropertyListenerBlock = {
            [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.removeListeners()
                self.installListeners()
                self.rebuildAllTaps(reason: "Core Audio service restarted")
            }
        }
        serviceRestartListener = restartListener
        var serviceRestarted = CoreAudioUtils.address(
            kAudioHardwarePropertyServiceRestarted
        )
        let restartStatus = AudioObjectAddPropertyListenerBlock(
            CoreAudioUtils.systemObject,
            &serviceRestarted,
            .main,
            restartListener
        )

        for (label, status) in [
            ("process list", processStatus),
            ("default output", outputStatus),
            ("service restart", restartStatus),
        ] where status != noErr {
            Self.logger.error(
                "Listener registration failed for \(label, privacy: .public): \(status)"
            )
        }
    }

    private func removeListeners() {
        if let listener = processListListener {
            var property = CoreAudioUtils.address(
                kAudioHardwarePropertyProcessObjectList
            )
            AudioObjectRemovePropertyListenerBlock(
                CoreAudioUtils.systemObject,
                &property,
                .main,
                listener
            )
            processListListener = nil
        }
        if let listener = defaultOutputListener {
            var property = CoreAudioUtils.address(
                kAudioHardwarePropertyDefaultOutputDevice
            )
            AudioObjectRemovePropertyListenerBlock(
                CoreAudioUtils.systemObject,
                &property,
                .main,
                listener
            )
            defaultOutputListener = nil
        }
        if let listener = serviceRestartListener {
            var property = CoreAudioUtils.address(
                kAudioHardwarePropertyServiceRestarted
            )
            AudioObjectRemovePropertyListenerBlock(
                CoreAudioUtils.systemObject,
                &property,
                .main,
                listener
            )
            serviceRestartListener = nil
        }
    }

    private func persistVolumes() {
        UserDefaults.standard.set(
            savedVolumes.mapValues { Double($0) },
            forKey: Self.volumesDefaultsKey
        )
    }

    private func persistLastAudibleVolumes() {
        UserDefaults.standard.set(
            lastAudibleVolumes.mapValues { Double($0) },
            forKey: Self.lastAudibleVolumesDefaultsKey
        )
    }

    private func persistKnownApps() {
        UserDefaults.standard.set(
            knownAppNames,
            forKey: Self.knownAppsDefaultsKey
        )
    }
}
