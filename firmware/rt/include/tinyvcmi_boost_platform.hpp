// SPDX-License-Identifier: GPL-3.0-only
//
// Boost.Config's platform for the AE350: newlib with firmware/rt's POSIX
// threads and clocks.  Boost recognises a platform by its OS macros, which a
// bare-metal riscv-none-elf compiler defines none of, so without this Boost
// sees no platform, no pthreads, and picks Win32 code paths.  This is Boost's
// own generic-unix branch (detail/select_platform_config.hpp): unistd.h, and
// every feature from the POSIX option macros, which the threaded toolchain's
// sysroot sets for what firmware/rt provides.
#ifndef TINYVCMI_BOOST_PLATFORM_HPP
#define TINYVCMI_BOOST_PLATFORM_HPP

#define BOOST_PLATFORM "TinyVCMI AE350 (newlib, cooperative pthreads)"
#ifndef BOOST_HAS_UNISTD_H
#define BOOST_HAS_UNISTD_H
#endif
#include <boost/config/detail/posix_features.hpp>

#endif
