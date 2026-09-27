// save_zstd_linux.h -- the Linux installer of the shared save stream code
// (native/src/save_zstd.h): the system libzstd, dlopen'd.
#pragma once
#include "save_zstd.h"

// Installs the six call-site redirects (slice_core_main.cpp). False, changing
// nothing, when a guard fails, save_threads=0, or no usable libzstd is found.
bool SliceInstallSaveZstd(uintptr_t base, const char* root, const char* data);
void SliceSaveZstdLogAlive();
