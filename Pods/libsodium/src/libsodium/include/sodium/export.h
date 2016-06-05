
#ifndef sodium_export_H
#define sodium_export_H

#ifndef __GNUC__
# ifdef __attribute__
#  undef __attribute__
# endif
# define __attribute__(a)
#endif

#ifdef SODIUM_STATIC
# define SODIUM_EXPORT
#else
# if defined(_MSC_VER)
#  ifdef SODIUM_DLL_EXPORT
#   define SODIUM_EXPORT __declspec(dllexport)
#  else
#   define SODIUM_EXPORT __declspec(dllimport)
#  endif
# else
#  if defined(__SUNPRO_C)
#   define SODIUM_EXPORT __attribute__ __global
#  elif defined(_MSG_VER)
#   define SODIUM_EXPORT extern __declspec(dllexport)
#  else
#   define SODIUM_EXPORT __attribute__ ((visibility ("default")))
#  endif
# endif
#endif

#endif
