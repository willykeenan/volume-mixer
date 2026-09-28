import AppKit
import AVFoundation

final class AudioFixtureDelegate: NSObject, NSApplicationDelegate {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var phase = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let frequency = Double(environment["KE_FIXTURE_FREQUENCY"] ?? "") ?? 440
        let amplitude = Float(environment["KE_FIXTURE_AMPLITUDE"] ?? "") ?? 0.08
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioData in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioData)
            let phaseStep = 2 * Double.pi * frequency / sampleRate

            for frame in 0..<Int(frameCount) {
                let sample = sin(self.phase) * Double(amplitude)
                self.phase += phaseStep
                if self.phase >= 2 * Double.pi {
                    self.phase -= 2 * Double.pi
                }
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    data.assumingMemoryBound(to: Float.self)[frame] =
                        Float(sample)
                }
            }
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            engine.prepare()
            try engine.start()
        } catch {
            fputs("fixture audio failed: \(error)\n", stderr)
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }
}

let app = NSApplication.shared
let delegate = AudioFixtureDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
