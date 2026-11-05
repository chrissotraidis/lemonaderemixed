/*
 * Frame tap: copies the game's 640x480 window into shared memory so the app
 * can draw exact game pixels without screen capture.
 *
 * remix-frames.bin (next to the DLL) holds a 64-byte header and two frame
 * buffers. Each buffer is a top-down 32-bit BGRX DIB section placed directly
 * in the file mapping, so BitBlt writes straight into the shared file. The
 * header names the buffer that was finished last; the app reads that one
 * while the next frame goes into the other.
 */
#include "proxy.h"

enum { WIDTH = 640, HEIGHT = 480, HEADER = 64, FRAME = WIDTH * HEIGHT * 4 };

typedef struct {
    char magic[4];            /* "LRFT" */
    DWORD version;            /* 1 */
    DWORD width, height, stride;
    volatile DWORD latest;    /* buffer index finished last: 0 or 1 */
    volatile DWORD frame;     /* increases with every finished frame */
} TapHeader;

typedef struct {
    DWORD size; long width, height;
    unsigned short planes, bits;
    DWORD compression, image;
    long xppm, yppm;
    DWORD used, important;
} BitmapHeader;

__declspec(dllimport) HANDLE __stdcall FindWindowA(const char *, const char *);
__declspec(dllimport) HANDLE __stdcall GetDC(HANDLE);
__declspec(dllimport) int __stdcall ReleaseDC(HANDLE, HANDLE);
__declspec(dllimport) HANDLE __stdcall CreateCompatibleDC(HANDLE);
__declspec(dllimport) HANDLE __stdcall CreateDIBSection(HANDLE, const void *, unsigned, void **, HANDLE, DWORD);
__declspec(dllimport) HANDLE __stdcall SelectObject(HANDLE, HANDLE);
__declspec(dllimport) BOOL __stdcall BitBlt(HANDLE, int, int, int, int, HANDLE, int, int, DWORD);
__declspec(dllimport) BOOL __stdcall GdiFlush(void);
__declspec(dllimport) HANDLE __stdcall CreateFileMappingA(HANDLE, void *, DWORD, DWORD, DWORD, const char *);
__declspec(dllimport) void *__stdcall MapViewOfFile(HANDLE, DWORD, DWORD, DWORD, unsigned long);

static DWORD __stdcall tap(void *unused) {
    char file[300];
    agent_path(file, "remix-frames.bin");
    HANDLE f = CreateFileA(file, 0xC0000000 /* read+write */, 7, 0, 2 /* CREATE_ALWAYS */, 0x80, 0);
    if (f == (HANDLE)-1) return 1;
    DWORD size = HEADER + 2 * FRAME;
    HANDLE mapping = CreateFileMappingA(f, 0, 4 /* PAGE_READWRITE */, 0, size, 0);
    TapHeader *h = mapping ? (TapHeader *)MapViewOfFile(mapping, 0xF001F, 0, 0, size) : 0;
    if (!h) return 1;

    BitmapHeader bmi = { sizeof(BitmapHeader), WIDTH, -HEIGHT, 1, 32, 0, 0, 0, 0, 0, 0 };
    HANDLE dc[2];
    for (int i = 0; i < 2; i++) {
        void *bits;
        dc[i] = CreateCompatibleDC(0);
        HANDLE dib = CreateDIBSection(dc[i], &bmi, 0, &bits, mapping, HEADER + i * FRAME);
        if (!dib) return 1;
        SelectObject(dc[i], dib);
    }
    h->magic[0] = 'L'; h->magic[1] = 'R'; h->magic[2] = 'F'; h->magic[3] = 'T';
    h->version = 1; h->width = WIDTH; h->height = HEIGHT; h->stride = WIDTH * 4;
    h->latest = 0; h->frame = 0;

    for (;;) {
        HANDLE window = FindWindowA(0, "Lemonade Tycoon Deluxe");
        if (window) {
            HANDLE screen = GetDC(window);
            DWORD next = 1 - h->latest;
            BitBlt(dc[next], 0, 0, WIDTH, HEIGHT, screen, 0, 0, 0x00CC0020 /* SRCCOPY */);
            GdiFlush();
            ReleaseDC(window, screen);
            h->latest = next;
            h->frame++;
        }
        Sleep(16);
    }
    (void)unused;
    return 0;
}

void start_frame_tap(void) { CreateThread(0, 0, tap, 0, 0, 0); }
