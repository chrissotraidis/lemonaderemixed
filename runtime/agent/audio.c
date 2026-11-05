/*
 * The in-game agent for Lemonade Remixed, loaded by the game as fmod.dll.
 *
 * The game's own fmod.dll is renamed fmodreal.dll; this library takes its
 * place, passes every call through, and applies the player's volume from
 * remix-volume.txt (0-100, next to the DLL) to sound effects and music.
 * If remix-fmod.log exists at start, it is filled with per-function call
 * counts, which shows which parts of FMOD the game uses. It also starts the
 * frame tap (frametap.c).
 */
#include "proxy.h"

void *g_real[EXPORT_COUNT];
volatile long g_counts[EXPORT_COUNT];

static char g_dir[260];
static volatile int g_user = 100;   /* player's volume, 0-100 */
static volatile int g_sfx = 255;    /* the game's own effects volume */
static void *g_songs[16];
static int g_songVolume[16];
static int g_songCount;
static int i_sfx, i_musicVol, i_play, i_musicGet, i_sfxGet;

typedef void(__stdcall *SetSfx)(int);
typedef signed char(__stdcall *SetMusic)(void *, int);
typedef signed char(__stdcall *PlaySong)(void *);
typedef int(__stdcall *GetMusic)(void *);
typedef int(__stdcall *GetSfx)(void);

int same(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

void agent_path(char *out, const char *file) {
    int n = 0;
    for (const char *s = g_dir; *s; s++) out[n++] = *s;
    for (const char *s = file; *s; s++) out[n++] = *s;
    out[n] = 0;
}

#define path agent_path

static int scaled(int v, int max) {
    int s = v * g_user / 100;
    return s < 0 ? 0 : (s > max ? max : s);
}

static void apply(void) {
    ((SetSfx)g_real[i_sfx])(scaled(g_sfx, 255));
    for (int k = 0; k < g_songCount; k++)
        ((SetMusic)g_real[i_musicVol])(g_songs[k], scaled(g_songVolume[k], 256));
}

static void remember(void *song, int volume) {
    for (int k = 0; k < g_songCount; k++)
        if (g_songs[k] == song) { g_songVolume[k] = volume; return; }
    if (g_songCount < 16) { g_songs[g_songCount] = song; g_songVolume[g_songCount] = volume; g_songCount++; }
}

void __stdcall wrap_FSOUND_SetSFXMasterVolume(int volume) {
    g_counts[i_sfx]++;
    g_sfx = volume;
    ((SetSfx)g_real[i_sfx])(scaled(volume, 255));
}

signed char __stdcall wrap_FMUSIC_SetMasterVolume(void *song, int volume) {
    g_counts[i_musicVol]++;
    remember(song, volume);
    return ((SetMusic)g_real[i_musicVol])(song, scaled(volume, 256));
}

signed char __stdcall wrap_FMUSIC_PlaySong(void *song) {
    g_counts[i_play]++;
    remember(song, ((GetMusic)g_real[i_musicGet])(song));
    signed char ok = ((PlaySong)g_real[i_play])(song);
    ((SetMusic)g_real[i_musicVol])(song, scaled(g_songVolume[g_songCount - 1], 256));
    return ok;
}

static int read_volume(void) {
    char file[300], buf[8];
    DWORD got = 0;
    path(file, "remix-volume.txt");
    HANDLE h = CreateFileA(file, 0x80000000 /* GENERIC_READ */, 7, 0, 3 /* OPEN_EXISTING */, 0, 0);
    if (h == (HANDLE)-1) return 100;
    ReadFile(h, buf, sizeof buf - 1, &got, 0);
    CloseHandle(h);
    int v = 0, digits = 0;
    for (DWORD i = 0; i < got && buf[i] >= '0' && buf[i] <= '9'; i++) { v = v * 10 + buf[i] - '0'; digits++; }
    return digits ? (v > 100 ? 100 : v) : 100;
}

static int put_number(char *text, int n, long c) {
    char digits[12]; int d = 0;
    do { digits[d++] = '0' + c % 10; c /= 10; } while (c);
    while (d) text[n++] = digits[--d];
    return n;
}

static void write_log(HANDLE h) {
    static char text[16384];
    int n = 0;
    /* The effective effects volume inside FMOD (0-255), then call counts. */
    for (const char *s = "sfx-master "; *s; s++) text[n++] = *s;
    n = put_number(text, n, ((GetSfx)g_real[i_sfxGet])());
    text[n++] = '\n';
    for (int i = 0; i < EXPORT_COUNT; i++) {
        if (!g_counts[i]) continue;
        for (const char *s = g_names[i]; *s && n < 16300; s++) text[n++] = *s;
        text[n++] = ' ';
        n = put_number(text, n, g_counts[i]);
        text[n++] = '\n';
    }
    DWORD wrote;
    char file[300];
    path(file, "remix-fmod.log");
    HANDLE f = CreateFileA(file, 0x40000000 /* GENERIC_WRITE */, 7, 0, 2 /* CREATE_ALWAYS */, 0, 0);
    if (f != (HANDLE)-1) { WriteFile(f, text, n, &wrote, 0); CloseHandle(f); }
    (void)h;
}

static DWORD __stdcall watcher(void *unused) {
    char file[300];
    path(file, "remix-fmod.log");
    HANDLE log = CreateFileA(file, 0x80000000, 7, 0, 3, 0, 0);
    int logging = log != (HANDLE)-1;
    if (logging) CloseHandle(log);
    int applied = -1, ticks = 0;
    for (;;) {
        int v = read_volume();
        g_user = v;
        if (v != applied || ticks % 10 == 0) { apply(); applied = v; }
        if (logging && ticks % 10 == 0) write_log(0);
        ticks++;
        Sleep(200);
    }
    (void)unused;
    return 0;
}

BOOL __stdcall DllMain(HANDLE self, DWORD reason, void *reserved) {
    if (reason != 1) return 1;
    DWORD n = GetModuleFileNameA(self, g_dir, sizeof g_dir);
    while (n && g_dir[n - 1] != '\\') n--;
    g_dir[n] = 0;
    char real[300];
    path(real, "fmodreal.dll");
    HANDLE lib = LoadLibraryA(real);
    if (!lib) return 0;
    for (int i = 0; i < EXPORT_COUNT; i++) g_real[i] = GetProcAddress(lib, g_names[i]);
    i_sfx = index_of_wrapped("_FSOUND_SetSFXMasterVolume@4");
    i_musicVol = index_of_wrapped("_FMUSIC_SetMasterVolume@8");
    i_play = index_of_wrapped("_FMUSIC_PlaySong@4");
    for (int i = 0; i < EXPORT_COUNT; i++)
        if (same(g_names[i], "_FMUSIC_GetMasterVolume@4")) i_musicGet = i;
        else if (same(g_names[i], "_FSOUND_GetSFXMasterVolume@0")) i_sfxGet = i;
    CreateThread(0, 0, watcher, 0, 0, 0);
    start_frame_tap();
    (void)reserved;
    return 1;
}
