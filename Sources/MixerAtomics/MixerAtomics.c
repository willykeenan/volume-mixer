#include "MixerAtomics.h"

#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct KEMixerAtomicFloat {
    _Atomic(uint32_t) bits;
};

static uint32_t KEMixerFloatBits(float value) {
    uint32_t bits = 0;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}

static float KEMixerBitsFloat(uint32_t bits) {
    float value = 0;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

KEMixerAtomicFloat *KEMixerAtomicFloatCreate(float initialValue) {
    KEMixerAtomicFloat *storage = calloc(1, sizeof(KEMixerAtomicFloat));
    if (storage == NULL) {
        return NULL;
    }
    atomic_init(&storage->bits, KEMixerFloatBits(initialValue));
    return storage;
}

void KEMixerAtomicFloatDestroy(KEMixerAtomicFloat *storage) {
    free(storage);
}

float KEMixerAtomicFloatLoad(const KEMixerAtomicFloat *storage) {
    if (storage == NULL) {
        return 0;
    }
    uint32_t bits = atomic_load_explicit(&storage->bits, memory_order_relaxed);
    return KEMixerBitsFloat(bits);
}

void KEMixerAtomicFloatStore(KEMixerAtomicFloat *storage, float value) {
    if (storage == NULL) {
        return;
    }
    atomic_store_explicit(
        &storage->bits,
        KEMixerFloatBits(value),
        memory_order_relaxed
    );
}

bool KEMixerAtomicFloatIsLockFree(const KEMixerAtomicFloat *storage) {
    if (storage == NULL) {
        return false;
    }
    return atomic_is_lock_free(&storage->bits);
}
