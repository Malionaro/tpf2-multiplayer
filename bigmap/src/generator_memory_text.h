#pragma once
// Shared text transformation; embedding supplied by each platform build.
static const char kGenAnchor[] = "\t\treturn result";
static const char kGenReplacement[] =
    "\t\tif (tonumber(params and params.mapSizeX) or 0) * (tonumber(params and params.mapSizeY) or 0) > 32768 * 32768"
    " then result = _tpf2_bigmap_memory.Optimize(result) end return result -- tpf2_bigmap memory";

// The patched generator text, malloc'd; nullptr when the anchor is not exactly
// one whole line.
static char* PatchGeneratorText(const char* src, size_t len, size_t* outLen) {
    const size_t a = sizeof kGenAnchor - 1;
    const char* hit = nullptr;
    if (len < a) return nullptr;
    for (size_t pos = 0; pos <= len - a; ++pos) {
        const char* p = src + pos;
        if (memcmp(p, kGenAnchor, a) != 0) continue;
        const char* e = p + a;
        bool lineStart = p == src || p[-1] == '\n';
        bool lineEnd = e == src + len || *e == '\n' || (*e == '\r' && e + 1 < src + len && e[1] == '\n');
        if (!lineStart || !lineEnd) continue;
        if (hit) return nullptr;   // repeated
        hit = p;
    }
    if (!hit) return nullptr;
    static const char head[] = "\n_tpf2_bigmap_memory = (function()\n";
    static const char tail[] = "\nend)()\n";
    size_t module = 0;
    for (const char* part : kGeneratorMemoryLuaParts) module += strlen(part);
    const size_t r = sizeof kGenReplacement - 1;
    size_t total = len - a + r + (sizeof head - 1) + module + (sizeof tail - 1);
    char* out = (char*)malloc(total + 1);
    if (!out) return nullptr;
    char* o = out;
    size_t pre = size_t(hit - src);
    memcpy(o, src, pre); o += pre;
    memcpy(o, kGenReplacement, r); o += r;
    memcpy(o, hit + a, len - pre - a); o += len - pre - a;
    memcpy(o, head, sizeof head - 1); o += sizeof head - 1;
    for (const char* part : kGeneratorMemoryLuaParts) { size_t k = strlen(part); memcpy(o, part, k); o += k; }
    memcpy(o, tail, sizeof tail - 1); o += sizeof tail - 1;
    *o = 0;
    *outLen = size_t(o - out);
    return out;
}
