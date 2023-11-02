#ifndef PPARSEFP_H
#define PPARSEFP_H

#ifdef __cplusplus
extern "C" {
#endif

#include <string.h> /* memcpy */

/*
 * Parses a float or double number and returns the length parsed if
 * successful. The length argument is of limited value due to dependency
 * on `strtod` - buf[len] must be accessible and must not be part of
 * a valid number, including hex float numbers..
 *
 * Unlike strtod, whitespace is not parsed.
 *
 * May return:
 * - null on error,
 * - buffer start if first character does not start a number,
 * - or end of parse on success.
 *
 */

#define PDIAGNOSTIC_IGNORE_UNUSED_FUNCTION
#include "pdiagnostic_push.h"

/*
 * isinf is needed in order to stay compatible with strtod's
 * over/underflow handling but isinf has some portability issues.
 *
 * Use the parse_double/float_is_range_error instead of isinf directly.
 * This ensures optimizations can be added when not using strtod.
 *
 * On gcc, clang and msvc we can use isinf or equivalent directly.
 * Other compilers such as xlc may require linking with -lm which may not
 * be convienent so a default isinf is provided. If isinf is available
 * and there is a noticable performance issue, define
 * `PORTABLE_USE_ISINF`. This flag also affects isnan.
 */
#if defined(__GNUC__) || defined(__clang__) || defined(_MSC_VER) || defined(PORTABLE_USE_ISINF)
#include <math.h>
#if defined(_MSC_VER) && !defined(isinf)
#include <float.h>
#define isnan _isnan
#define isinf(x) (!_finite(x))
#endif
/*
 * clang-3 through clang-8 but not clang-9 issues incorrect precision
 * loss warning with -Wconversion flag when cast is absent.
 */
#if defined(__clang__)
#if __clang_major__ >= 3 && __clang_major__ <= 8
#define parse_double_isinf(x) isinf((float)x)
#define parse_double_isnan(x) isnan((float)x)
#endif
#endif
#if !defined(parse_double_isinf)
#define parse_double_isinf isinf
#endif
#define parse_float_isinf isinf

#else

#ifndef UINT8_MAX
#include <stdint.h>
#endif

/* Avoid linking with libmath but depends on float/double being IEEE754 */
static inline int parse_double_isinf(const double x)
{
    uint64_t u64x;

    memcpy(&u64x, &x, sizeof(u64x));
    return (u64x & 0x7fffffff00000000ULL) == 0x7ff0000000000000ULL;
}

static inline int parse_float_isinf(float x)
{
    uint32_t u32x;

    memcpy(&u32x, &x, sizeof(u32x));
    return (u32x & 0x7fffffff) == 0x7f800000;
}

#endif

#if !defined(parse_double_isnan)
#define parse_double_isnan isnan
#endif
#if !defined(parse_float_isnan)
#define parse_float_isnan isnan
#endif

/* Returns 0 when in range, 1 on overflow, and -1 on underflow. */
static inline int parse_double_is_range_error(double x)
{
    return parse_double_isinf(x) ? (x < 0.0 ? -1 : 1) : 0;
}

static inline int parse_float_is_range_error(float x)
{
    return parse_float_isinf(x) ? (x < 0.0f ? -1 : 1) : 0;
}

#ifndef PORTABLE_USE_GRISU3
#define PORTABLE_USE_GRISU3 1
#endif

#if PORTABLE_USE_GRISU3
#include "grisu3_parse.h"
#endif

#ifdef grisu3_parse_double_is_defined
static inline const char *parse_double(const char *buf, size_t len, double *result)
{
    return grisu3_parse_double(buf, len, result);
}
#else
#include <stdio.h>
static inline const char *parse_double(const char *buf, size_t len, double *result)
{
    char *end;

    (void)len;
    *result = strtod(buf, &end);
    return end;
}
#endif

static inline const char *parse_float(const char *buf, size_t len, float *result)
{
    const char *end;
    double v;
    union { uint32_t u32; float f32; } inf;
    inf.u32 = 0x7f800000;

    end = parse_double(buf, len, &v);
    *result = (float)v;
    if (parse_float_isinf(*result)) {
        *result = v < 0 ? -inf.f32 : inf.f32;
        return buf;
    }
    return end;
}

/* Inspired by https://bitbashing.io/comparing-floats.html */

/* Return signed ULP distance or INT64_MAX if any value is nan. */
static inline int64_t parse_double_compare(const double x, const double y)
{
    int64_t i64x, i64y;
    
    if (x == y) return 0;
    if (parse_double_isnan(x)) return INT64_MAX;
    if (parse_double_isnan(y)) return INT64_MAX;
    memcpy(&i64x, &x, sizeof(i64x));
    memcpy(&i64y, &y, sizeof(i64y));
    if ((i64x < 0) != (i64y < 0)) return INT64_MAX;
    return i64x - i64y;
}

/* Same as double, but INT32_MAX if nan. */
static inline int32_t parse_float_compare(const float x, const float y)
{
    int32_t i32x, i32y;
    
    if (x == y) return 0;
    if (parse_float_isnan(x)) return INT32_MAX;
    if (parse_float_isnan(y)) return INT32_MAX;
    memcpy(&i32x, &x, sizeof(i32x));
    memcpy(&i32y, &y, sizeof(i32y));
    if ((i32x < 0) != (i32y < 0)) return INT32_MAX;
    return i32x - i32y;
}

/* 
 * Returns the absolute distance in floating point ULP (representational bit difference).
 * Uses signed return value so that INT64_MAX and INT32_MAX indicates NaN similar to
 * the compare function.
 */
static inline int64_t parse_double_dist(const double x, const double y)
{
    uint64_t m64;
    int64_t i64;
    
    i64 = parse_double_compare(x, y);
    /* Absolute integer value of compare. */
    m64 = (uint64_t)-(i64 < 0);
    return (int64_t)(((uint64_t)i64 + m64) ^ m64);
}

/* Same as double, but INT32_MAX if NaN. */
static inline int32_t parse_float_dist(const float x, const float y)
{
    uint32_t m32;
    int32_t i32;
    
    i32 = parse_float_compare(x, y);
    /* Absolute integer value of compare. */
    m32 = (uint32_t)-(i32 < 0);
    return (int32_t)(((uint32_t)i32 + m32) ^ m32);
}

/* 
 * Returns 1 if no value is NaN, and the difference is at most one ULP (1 bit), and the
 * sign is the same, and 0 otherwise.
 */
static inline int parse_double_is_equal(const double x, const double y)
{
    return parse_double_dist(x, y) >> 1 == 0;
}

/* Same as double, but at lower precision. */
static inline int parse_float_is_equal(const float x, const float y)
{
    return parse_float_dist(x, y) >> 1 == 0;
}

#include "pdiagnostic_pop.h"

#ifdef __cplusplus
}
#endif

#endif /* PPARSEFP_H */
