// Copyright 2026 Adhish Thite
// SPDX-License-Identifier: Apache-2.0

#include "StokCaptureRing.h"

#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// Bounds the per-record header walk; no capture format comes close.
#define STOK_MAX_BUFFERS 64

struct StokCaptureRing {
  _Atomic uint64_t head;  // Bytes published by the producer. Producer writes.
  _Atomic uint64_t tail;  // Bytes consumed. Consumer writes.
  _Atomic uint64_t dropped;
  _Atomic uint32_t epoch;
  uint64_t mask;
  uint8_t *storage;
  dispatch_semaphore_t wake;
};

typedef struct {
  uint32_t frames;
  uint32_t bufferCount;
  uint64_t hostTime;
  uint64_t inputHostTime;
  uint32_t epoch;
  uint32_t totalBytes;  // Header plus every buffer section.
} RecordHeader;

typedef struct {
  uint32_t bytes;
  uint32_t padding;
} BufferHeader;

static inline uint64_t round8(uint64_t value) { return (value + 7) & ~(uint64_t)7; }

static void copy_in(StokCaptureRing *ring, uint64_t position, const void *source, uint64_t count) {
  uint64_t capacity = ring->mask + 1;
  uint64_t offset = position & ring->mask;
  uint64_t first = count < capacity - offset ? count : capacity - offset;
  memcpy(ring->storage + offset, source, first);
  if (count > first) memcpy(ring->storage, (const uint8_t *)source + first, count - first);
}

static void copy_out(const StokCaptureRing *ring, uint64_t position, void *destination, uint64_t count) {
  uint64_t capacity = ring->mask + 1;
  uint64_t offset = position & ring->mask;
  uint64_t first = count < capacity - offset ? count : capacity - offset;
  memcpy(destination, ring->storage + offset, first);
  if (count > first) memcpy((uint8_t *)destination + first, ring->storage, count - first);
}

StokCaptureRing *stok_capture_ring_create(uint32_t capacityBytes) {
  uint64_t capacity = 1024;
  while (capacity < capacityBytes) capacity <<= 1;
  StokCaptureRing *ring = calloc(1, sizeof(StokCaptureRing));
  if (!ring) return NULL;
  ring->storage = calloc(1, capacity);
  ring->wake = dispatch_semaphore_create(0);
  if (!ring->storage || !ring->wake) {
    free(ring->storage);
    if (ring->wake) dispatch_release(ring->wake);
    free(ring);
    return NULL;
  }
  ring->mask = capacity - 1;
  atomic_init(&ring->head, 0);
  atomic_init(&ring->tail, 0);
  atomic_init(&ring->dropped, 0);
  atomic_init(&ring->epoch, 0);
  return ring;
}

void stok_capture_ring_destroy(StokCaptureRing *ring) {
  dispatch_release(ring->wake);
  free(ring->storage);
  free(ring);
}

bool stok_capture_ring_write(
    StokCaptureRing *ring, const AudioTimeStamp *timestamp, const AudioBufferList *list,
    uint32_t frames) {
  uint32_t count = list->mNumberBuffers;
  if (count == 0 || count > STOK_MAX_BUFFERS) {
    atomic_fetch_add_explicit(&ring->dropped, 1, memory_order_relaxed);
    return false;
  }
  uint64_t total = sizeof(RecordHeader);
  for (uint32_t index = 0; index < count; index++) {
    if (!list->mBuffers[index].mData) {
      atomic_fetch_add_explicit(&ring->dropped, 1, memory_order_relaxed);
      return false;
    }
    total += sizeof(BufferHeader) + round8(list->mBuffers[index].mDataByteSize);
  }
  uint64_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
  uint64_t tail = atomic_load_explicit(&ring->tail, memory_order_acquire);
  if (total > (ring->mask + 1) - (head - tail) || total > UINT32_MAX) {
    atomic_fetch_add_explicit(&ring->dropped, 1, memory_order_relaxed);
    return false;
  }
  RecordHeader header = {
      .frames = frames,
      .bufferCount = count,
      .hostTime = mach_absolute_time(),
      .inputHostTime =
          timestamp && (timestamp->mFlags & kAudioTimeStampHostTimeValid) ? timestamp->mHostTime : 0,
      .epoch = atomic_load_explicit(&ring->epoch, memory_order_acquire),
      .totalBytes = (uint32_t)total,
  };
  uint64_t position = head;
  copy_in(ring, position, &header, sizeof(header));
  position += sizeof(header);
  for (uint32_t index = 0; index < count; index++) {
    BufferHeader buffer = {.bytes = list->mBuffers[index].mDataByteSize, .padding = 0};
    copy_in(ring, position, &buffer, sizeof(buffer));
    position += sizeof(buffer);
    copy_in(ring, position, list->mBuffers[index].mData, buffer.bytes);
    position += round8(buffer.bytes);
  }
  atomic_store_explicit(&ring->head, head + total, memory_order_release);
  dispatch_semaphore_signal(ring->wake);
  return true;
}

static bool next_header(StokCaptureRing *ring, uint64_t *tail, RecordHeader *header) {
  *tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
  uint64_t head = atomic_load_explicit(&ring->head, memory_order_acquire);
  if (head == *tail) return false;
  copy_out(ring, *tail, header, sizeof(*header));
  return true;
}

bool stok_capture_ring_peek(StokCaptureRing *ring, StokCaptureRecordInfo *info) {
  uint64_t tail;
  RecordHeader header;
  if (!next_header(ring, &tail, &header)) return false;
  info->frames = header.frames;
  info->bufferCount = header.bufferCount;
  info->hostTime = header.hostTime;
  info->inputHostTime = header.inputHostTime;
  info->epoch = header.epoch;
  return true;
}

StokCaptureReadStatus stok_capture_ring_read(
    StokCaptureRing *ring, AudioBufferList *dst, StokCaptureRecordInfo *info) {
  uint64_t tail;
  RecordHeader header;
  if (!next_header(ring, &tail, &header)) return StokCaptureReadEmpty;
  info->frames = header.frames;
  info->bufferCount = header.bufferCount;
  info->hostTime = header.hostTime;
  info->inputHostTime = header.inputHostTime;
  info->epoch = header.epoch;
  StokCaptureReadStatus status = StokCaptureReadOK;
  if (dst->mNumberBuffers != header.bufferCount) status = StokCaptureReadMismatch;
  uint64_t position = tail + sizeof(header);
  for (uint32_t index = 0; index < header.bufferCount && status == StokCaptureReadOK; index++) {
    BufferHeader buffer;
    copy_out(ring, position, &buffer, sizeof(buffer));
    position += sizeof(buffer);
    if (!dst->mBuffers[index].mData || buffer.bytes > dst->mBuffers[index].mDataByteSize) {
      status = StokCaptureReadMismatch;
      break;
    }
    copy_out(ring, position, dst->mBuffers[index].mData, buffer.bytes);
    dst->mBuffers[index].mDataByteSize = buffer.bytes;
    position += round8(buffer.bytes);
  }
  atomic_store_explicit(&ring->tail, tail + header.totalBytes, memory_order_release);
  return status;
}

uint32_t stok_capture_ring_discard_all(StokCaptureRing *ring) {
  // Epoch first: a record the producer starts after this point carries the new epoch; one
  // already in progress carries the old one and is skipped by the consumer.
  uint32_t epoch = atomic_fetch_add_explicit(&ring->epoch, 1, memory_order_acq_rel) + 1;
  uint64_t head = atomic_load_explicit(&ring->head, memory_order_acquire);
  atomic_store_explicit(&ring->tail, head, memory_order_release);
  return epoch;
}

uint32_t stok_capture_ring_epoch(const StokCaptureRing *ring) {
  return atomic_load_explicit(&ring->epoch, memory_order_acquire);
}

uint64_t stok_capture_ring_dropped(const StokCaptureRing *ring) {
  return atomic_load_explicit(&ring->dropped, memory_order_relaxed);
}

uint64_t stok_capture_ring_used(const StokCaptureRing *ring) {
  uint64_t tail = atomic_load_explicit(&ring->tail, memory_order_acquire);
  uint64_t head = atomic_load_explicit(&ring->head, memory_order_acquire);
  return head - tail;
}

void stok_capture_ring_wait(StokCaptureRing *ring) {
  dispatch_semaphore_wait(ring->wake, DISPATCH_TIME_FOREVER);
}

void stok_capture_ring_wake(StokCaptureRing *ring) { dispatch_semaphore_signal(ring->wake); }
