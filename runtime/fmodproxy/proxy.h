/* Shared declarations for the FMOD proxy (freestanding: no C runtime). */
#pragma once
#include "count.h"

typedef void *HANDLE;
typedef int BOOL;
typedef unsigned long DWORD;

__declspec(dllimport) HANDLE __stdcall LoadLibraryA(const char *);
__declspec(dllimport) void *__stdcall GetProcAddress(HANDLE, const char *);
__declspec(dllimport) HANDLE __stdcall CreateThread(void *, unsigned, DWORD(__stdcall *)(void *), void *, DWORD, DWORD *);
__declspec(dllimport) void __stdcall Sleep(DWORD);
__declspec(dllimport) HANDLE __stdcall CreateFileA(const char *, DWORD, DWORD, void *, DWORD, DWORD, HANDLE);
__declspec(dllimport) BOOL __stdcall ReadFile(HANDLE, void *, DWORD, DWORD *, void *);
__declspec(dllimport) BOOL __stdcall WriteFile(HANDLE, const void *, DWORD, DWORD *, void *);
__declspec(dllimport) BOOL __stdcall CloseHandle(HANDLE);
__declspec(dllimport) DWORD __stdcall GetModuleFileNameA(HANDLE, char *, DWORD);

extern const char *const g_names[EXPORT_COUNT];
extern void *g_real[EXPORT_COUNT];
extern volatile long g_counts[EXPORT_COUNT];

int same(const char *a, const char *b);
int index_of_wrapped(const char *name);
