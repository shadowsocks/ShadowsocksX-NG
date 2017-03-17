//
//  _RX.h
//  RxCocoa
//
//  Created by Krunoslav Zaher on 7/12/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/**
 ################################################################################
 This file is part of RX private API
 ################################################################################
 */

#if        TRACE_RESOURCES >= 2
#   define DLOG(...)         NSLog(__VA_ARGS__)
#else
#   define DLOG(...)
#endif

#if        DEBUG
#   define ABORT_IN_DEBUG    abort();
#else
#   define ABORT_IN_DEBUG
#endif


#define SEL_VALUE(x)      [NSValue valueWithPointer:(x)]
#define CLASS_VALUE(x)    [NSValue valueWithNonretainedObject:(x)]
#define IMP_VALUE(x)      [NSValue valueWithPointer:(x)]

/**
 Checks that the local `error` instance exists before assigning it's value by reference.
 This macro exists to work around static analysis warnings — `NSError` is always assumed to be `nullable`, even though we explictly define the method parameter as `nonnull`. See http://www.openradar.me/21766176 for more details.
 */
#define RX_THROW_ERROR(errorValue, returnValue) if (error != nil) { *error = (errorValue); } return (returnValue);

// Inspired by http://p99.gforge.inria.fr

// https://gcc.gnu.org/onlinedocs/gcc-2.95.3/cpp_1.html#SEC26
#define RX_CAT2(_1, _2) _RX_CAT2(_1, _2)

#define RX_ELEMENT_AT(n, ...) RX_CAT2(_RX_ELEMENT_AT_, n)(__VA_ARGS__)

#define RX_COUNT(...) RX_ELEMENT_AT(6, ## __VA_ARGS__, 6, 5, 4, 3, 2, 1, 0)

/**
 #define JOIN(context, index, head, tail) head; tail
 #define APPLY(context, index, item) item = (context)[index]

 RX_FOR(A, JOIN, APPLY, toto, tutu);

 toto = (A)[0]; tutu = (A)[1];
 */
#define RX_FOR(context, join, generate, ...) RX_CAT2( _RX_FOR_, RX_COUNT(__VA_ARGS__))(context, 0, join, generate, ## __VA_ARGS__)

/**
 #define JOIN(context, index, head, tail) head tail
 #define APPLY(context, index, item) item = (context)[index]

 RX_FOR(A, JOIN, APPLY, toto, tutu);

 , toto = (A)[0], tutu = (A)[1]
 */
#define RX_FOR_COMMA(context, generate, ...) RX_CAT2( _RX_FOR_COMMA_, RX_COUNT(__VA_ARGS__))(context, 0, generate, ## __VA_ARGS__)

#define RX_INC(x) RX_CAT2(_RX_INC_, x)

// element at

#define _RX_ELEMENT_AT_0(x, ...) x
#define _RX_ELEMENT_AT_1(_0, x, ...) x
#define _RX_ELEMENT_AT_2(_0, _1, x, ...) x
#define _RX_ELEMENT_AT_3(_0, _1, _2, x, ...) x
#define _RX_ELEMENT_AT_4(_0, _1, _2, _3, x, ...) x
#define _RX_ELEMENT_AT_5(_0, _1, _2, _3, _4, x, ...) x
#define _RX_ELEMENT_AT_6(_0, _1, _2, _3, _4, _5, x, ...) x

// rx for

#define _RX_FOR_0(context, index, join, generate)

#define _RX_FOR_1(context, index, join, generate, head) \
    generate(context, index, head)

#define _RX_FOR_2(context, index, join, generate, head, ...) \
    join(context, index, generate(context, index, head), _RX_FOR_1(context, RX_INC(index), join, generate, __VA_ARGS__))

#define _RX_FOR_3(context, index, join, generate, head, ...) \
    join(context, index, generate(context, index, head), _RX_FOR_2(context, RX_INC(index), join, generate, __VA_ARGS__))

#define _RX_FOR_4(context, index, join, generate, head, ...) \
    join(context, index, generate(context, index, head), _RX_FOR_3(context, RX_INC(index), join, generate, __VA_ARGS__))

#define _RX_FOR_5(context, index, join, generate, head, ...) \
    join(context, index, generate(context, index, head), _RX_FOR_4(context, RX_INC(index), join, generate, __VA_ARGS__))

#define _RX_FOR_6(context, index, join, generate, head, ...) \
    join(context, index, generate(context, index, head), _RX_FOR_5(context, RX_INC(index), join, generate, __VA_ARGS__))

// rx for

#define _RX_FOR_COMMA_0(context, index, generate)

#define _RX_FOR_COMMA_1(context, index, generate, head) \
    , generate(context, index, head)

#define _RX_FOR_COMMA_2(context, index, generate, head, ...) \
    , generate(context, index, head) _RX_FOR_COMMA_1(context, RX_INC(index), generate, __VA_ARGS__)

#define _RX_FOR_COMMA_3(context, index, generate, head, ...) \
    , generate(context, index, head) _RX_FOR_COMMA_2(context, RX_INC(index), generate, __VA_ARGS__)

#define _RX_FOR_COMMA_4(context, index, generate, head, ...) \
    , generate(context, index, head) _RX_FOR_COMMA_3(context, RX_INC(index), generate, __VA_ARGS__)

#define _RX_FOR_COMMA_5(context, index, generate, head, ...) \
    , generate(context, index, head) _RX_FOR_COMMA_4(context, RX_INC(index), generate, __VA_ARGS__)

#define _RX_FOR_COMMA_6(context, index, generate, head, ...) \
    , generate(context, index, head) _RX_FOR_COMMA_5(context, RX_INC(index), generate, __VA_ARGS__)


// rx inc

#define _RX_INC_0   1
#define _RX_INC_1   2
#define _RX_INC_2   3
#define _RX_INC_3   4
#define _RX_INC_4   5
#define _RX_INC_5   6
#define _RX_INC_6   7

// rx cat

#define _RX_CAT2(_1, _2) _1 ## _2
