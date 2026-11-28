/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Force-included (-include) into everything built with the threaded
 * toolchain, C and C++, by tools/cmake/ae350-threads.cmake and rt.mk's
 * RT_THREADS.  Only macros, so harmless to code that uses none of them.
 *
 *   TINYVCMI_AE350         the target: the AE350's A25, bare metal, newlib,
 *                          firmware/rt's cooperative POSIX threads.  The
 *                          marked patches tools/build_vcmi_deps.sh applies to
 *                          third-party code test it where that code would
 *                          otherwise reject an OS it does not know.
 *   BOOST_PLATFORM_CONFIG  Boost.Config's platform header for it
 *                          (tinyvcmi_boost_platform.hpp): Boost recognises
 *                          platforms by OS macros, of which there are none.
 */
#ifndef TINYVCMI_TARGET_H
#define TINYVCMI_TARGET_H

#define TINYVCMI_AE350 1

#ifndef BOOST_PLATFORM_CONFIG
#define BOOST_PLATFORM_CONFIG "tinyvcmi_boost_platform.hpp"
#endif

#endif
