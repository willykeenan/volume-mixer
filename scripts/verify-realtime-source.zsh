#!/usr/bin/env zsh
set -euo pipefail

script_dir=${0:A:h}
root=${script_dir:h}
tap="$root/Sources/KEVolumeMixer/ProcessTap.swift"

if grep -En \
  'OSAllocatedUnfairLock|NSLock|DispatchSemaphore|inputChannels[[:space:]]*:[[:space:]]*\[|reserveCapacity|append\(' \
  "$tap"; then
  echo "hard real-time source check failed: blocking lock or callback collection found" >&2
  exit 1
fi

if ! grep -Eq 'KEMixerAtomicFloatIsLockFree' "$tap"; then
  echo "hard real-time source check failed: lock-free admission is absent" >&2
  exit 1
fi

if grep -En \
  'takeUnretainedValue|CFRelease' \
  "$root/Sources/KEVolumeMixer/CoreAudioUtils.swift"; then
  echo "Core Audio CF ownership check failed: unbalanced bridge found" >&2
  exit 1
fi

if ! grep -Eq 'Unmanaged<CFString>' \
  "$root/Sources/KEVolumeMixer/CoreAudioUtils.swift" \
  || ! grep -Eq 'takeRetainedValue' \
  "$root/Sources/KEVolumeMixer/CoreAudioUtils.swift"; then
  echo "Core Audio CF ownership check failed: caller-owned +1 is not transferred to ARC" >&2
  exit 1
fi

if ! grep -Eq 'AudioHardwarePropertyServiceRestarted|kAudioHardwarePropertyServiceRestarted' \
  "$root/Sources/KEVolumeMixer/AudioMixer.swift"; then
  echo "lifecycle source check failed: Core Audio service restart listener is absent" >&2
  exit 1
fi

if ! grep -Eq 'willTerminateNotification' \
  "$root/Sources/KEVolumeMixer/AudioMixer.swift"; then
  echo "lifecycle source check failed: graceful shutdown cleanup is absent" >&2
  exit 1
fi

echo "ok: callback uses fixed channel views and lock-free atomic state"
