#ifndef KE_MIXER_ATOMICS_H
#define KE_MIXER_ATOMICS_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KEMixerAtomicFloat KEMixerAtomicFloat;

KEMixerAtomicFloat *KEMixerAtomicFloatCreate(float initialValue);
void KEMixerAtomicFloatDestroy(KEMixerAtomicFloat *storage);
float KEMixerAtomicFloatLoad(const KEMixerAtomicFloat *storage);
void KEMixerAtomicFloatStore(KEMixerAtomicFloat *storage, float value);
bool KEMixerAtomicFloatIsLockFree(const KEMixerAtomicFloat *storage);

#ifdef __cplusplus
}
#endif

#endif
