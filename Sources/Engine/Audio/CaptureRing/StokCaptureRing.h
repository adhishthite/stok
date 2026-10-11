// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

// Single-producer, single-consumer ring of hardware audio buffers. The producer is the
// CoreAudio IO thread; the consumer is the capture processing queue. The producer path
// takes no lock, allocates nothing and makes no Objective-C or Swift runtime call: it
// copies the buffer list into preallocated storage, publishes it with a release store,
// and signals a dispatch semaphore (an atomic increment; a Mach trap only when the
// consumer thread is already waiting).

#ifndef STOK_CAPTURE_RING_H
#define STOK_CAPTURE_RING_H

#include <CoreAudio/CoreAudioTypes.h>
#include <stdbool.h>
#include <stdint.h>

#pragma clang assume_nonnull begin

typedef struct StokCaptureRing StokCaptureRing;

typedef struct {
  uint32_t frames;
  uint32_t bufferCount;
  // mach_absolute_time() when the IO thread delivered the buffer.
  uint64_t hostTime;
  // Host time of the buffer's first frame as CoreAudio stamped it, or 0 when not valid.
  uint64_t inputHostTime;
  // Discard generation the record was written under (see stok_capture_ring_discard_all).
  uint32_t epoch;
} StokCaptureRecordInfo;

typedef enum {
  StokCaptureReadEmpty = 0,
  StokCaptureReadOK = 1,
  // A record existed but did not fit the destination list; it was consumed and dropped.
  StokCaptureReadMismatch = 2,
} StokCaptureReadStatus;

// capacityBytes is rounded up to a power of two. Returns NULL on allocation failure.
StokCaptureRing *_Nullable stok_capture_ring_create(uint32_t capacityBytes);
void stok_capture_ring_destroy(StokCaptureRing *ring);

// Producer (real-time thread). Copies every buffer in the list as one record. Returns
// false and counts a drop when the ring lacks space or the list is malformed.
bool stok_capture_ring_write(
    StokCaptureRing *ring, const AudioTimeStamp *_Nullable timestamp, const AudioBufferList *list,
    uint32_t frames);

// Consumer. Header of the next record, or false when the ring is empty.
bool stok_capture_ring_peek(StokCaptureRing *ring, StokCaptureRecordInfo *info);
// Consumer. Copies the next record into dst (buffer count must match and each mData must hold
// the record's bytes; mDataByteSize is the capacity on entry and the copied size on return),
// then consumes it.
StokCaptureReadStatus stok_capture_ring_read(
    StokCaptureRing *ring, AudioBufferList *dst, StokCaptureRecordInfo *info);
// Consumer. Drops every published record and starts a new epoch, so a record the producer
// is writing concurrently is recognisably stale. Safe while the producer runs.
uint32_t stok_capture_ring_discard_all(StokCaptureRing *ring);
uint32_t stok_capture_ring_epoch(const StokCaptureRing *ring);

// Records the producer could not store since creation.
uint64_t stok_capture_ring_dropped(const StokCaptureRing *ring);
// Bytes currently published and unread.
uint64_t stok_capture_ring_used(const StokCaptureRing *ring);

// Consumer thread: block until the producer publishes or stok_capture_ring_wake is called.
void stok_capture_ring_wait(StokCaptureRing *ring);
// Wake the waiting consumer without publishing (shutdown).
void stok_capture_ring_wake(StokCaptureRing *ring);

#pragma clang assume_nonnull end

#endif
