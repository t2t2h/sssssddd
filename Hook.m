// Hook.m - getaddrinfo (DNS override) + built-in symbol rebinding (no Substrate) - AFLATOON
#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <dlfcn.h>
#include <unistd.h>
#include <string.h>
#include <sys/mman.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <stdatomic.h>
#include "Shared.h"
#include "DNS.h"

#ifndef TCP_KEEPALIVE
#define TCP_KEEPALIVE 0x10
#endif
#ifndef SO_TRAFFIC_CLASS
#define SO_TRAFFIC_CLASS 0x1086
#endif

volatile int ap_dnsOn = 0;
const char * volatile ap_dnsServer = "1.1.1.1";

static NSMutableDictionary<NSString *, NSString *> *gCache;

void ap_dns_clear_cache(void) {
    @synchronized (gCache) { [gCache removeAllObjects]; }
}

// ---- net.boost : honest QoS tuning on this app's OWN sockets only ----
// NOT a VPN: no tunnel, no encryption, no IP change, no traffic re-routing.
// It only flips a handful of kernel socket options (TCP_NODELAY, bigger
// buffers, low-delay QoS class) on every new TCP socket the app opens,
// which can reduce jitter/stutter on an already-good connection - it
// cannot fix a weak signal or a slow ISP, and changes nothing server-side.
volatile int ap_netBoostOn = 0;
static _Atomic int ap_boostedCount = 0;

static int (*orig_socket)(int, int, int) = NULL;

static void ap_boost_fd(int fd, int domain) {
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &one, sizeof one);
    int idle = 30;
    setsockopt(fd, IPPROTO_TCP, TCP_KEEPALIVE, &idle, sizeof idle);
    int rb = 512 * 1024, sb = 256 * 1024;
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rb, sizeof rb);
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sb, sizeof sb);
    int tc = 700;   // SO_TC_VI-ish: ask the OS to prioritize this traffic
    setsockopt(fd, SOL_SOCKET, SO_TRAFFIC_CLASS, &tc, sizeof tc);
    if (domain == AF_INET) { int tos = 0x10; setsockopt(fd, IPPROTO_IP, IP_TOS, &tos, sizeof tos); }
    atomic_fetch_add(&ap_boostedCount, 1);
}

static int my_socket(int domain, int type, int proto) {
    int fd = orig_socket(domain, type, proto);
    if (fd >= 0 && ap_netBoostOn && type == SOCK_STREAM && (domain == AF_INET || domain == AF_INET6))
        ap_boost_fd(fd, domain);
    return fd;
}

int ap_net_boosted_count(void) { return atomic_load(&ap_boostedCount); }

static int is_ip_literal(const char *s) {
    struct in_addr a4; struct in6_addr a6;
    return inet_pton(AF_INET, s, &a4) == 1 || inet_pton(AF_INET6, s, &a6) == 1;
}

static int (*orig_getaddrinfo)(const char *, const char *, const struct addrinfo *, struct addrinfo **);

static int my_getaddrinfo(const char *node, const char *service,
                          const struct addrinfo *hints, struct addrinfo **res) {
    if (!ap_dnsOn || !node || !*node || is_ip_literal(node) || strcmp(node, "localhost") == 0)
        return orig_getaddrinfo(node, service, hints, res);

    const char *server = ap_dnsServer;
    NSString *key = [NSString stringWithFormat:@"%s|%s", server, node];
    NSString *ip = nil;
    @synchronized (gCache) { ip = gCache[key]; }
    if (!ip) {
        struct in_addr a;
        if (ap_dns_resolve(node, server, 53, &a)) {
            char buf[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &a, buf, sizeof buf);
            ip = [NSString stringWithUTF8String:buf];
            @synchronized (gCache) { gCache[key] = ip; }
        }
    }
    if (ip) {
        int rc = orig_getaddrinfo(ip.UTF8String, service, hints, res);
        if (rc == 0) return rc;
    }
    return orig_getaddrinfo(node, service, hints, res);
}

#pragma mark - symbol rebinding (fishhook-style)

typedef struct { const char *name; void *rep; } APRebind;
static APRebind gRebinds[3];
static int gRebindCount = 0;

static void patch_section(struct section_64 *sect, const char *segname, intptr_t slide,
                          struct nlist_64 *symtab, char *strtab, uint32_t *indirect) {
    uint32_t *idx = indirect + sect->reserved1;
    void **slots = (void **)((uintptr_t)slide + sect->addr);
    size_t count = sect->size / sizeof(void *);
    int isConst = (strcmp(segname, "__DATA_CONST") == 0);
    uintptr_t pg = (uintptr_t)getpagesize();
    uintptr_t start = (uintptr_t)slots & ~(pg - 1);
    uintptr_t end = ((uintptr_t)slots + sect->size + pg - 1) & ~(pg - 1);
    int unlocked = 0;

    for (size_t k = 0; k < count; k++) {
        uint32_t si = idx[k];
        if (si == INDIRECT_SYMBOL_ABS || si == INDIRECT_SYMBOL_LOCAL ||
            si == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
        const char *nm = strtab + symtab[si].n_un.n_strx;
        if (!nm[0]) continue;
        for (int t = 0; t < gRebindCount; t++) {
            if (strcmp(nm + 1, gRebinds[t].name) != 0) continue;
            if (slots[k] == gRebinds[t].rep) break;
            if (isConst && !unlocked) {
                if (mprotect((void *)start, end - start, PROT_READ | PROT_WRITE) != 0) return;
                unlocked = 1;
            }
            slots[k] = gRebinds[t].rep;
            break;
        }
    }
    if (unlocked) mprotect((void *)start, end - start, PROT_READ);
}

static void rebind_image(const struct mach_header *h, intptr_t slide) {
    if (!h) return;
    const struct mach_header_64 *hdr = (const struct mach_header_64 *)h;
    if (hdr->magic != MH_MAGIC_64) return;

    struct segment_command_64 *linkedit = NULL;
    struct symtab_command *symCmd = NULL;
    struct dysymtab_command *dysymCmd = NULL;

    uintptr_t cur = (uintptr_t)hdr + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < hdr->ncmds; i++) {
        struct load_command *lc = (struct load_command *)cur;
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)lc;
            if (strcmp(seg->segname, SEG_LINKEDIT) == 0) linkedit = seg;
        } else if (lc->cmd == LC_SYMTAB) {
            symCmd = (struct symtab_command *)lc;
        } else if (lc->cmd == LC_DYSYMTAB) {
            dysymCmd = (struct dysymtab_command *)lc;
        }
        cur += lc->cmdsize;
    }
    if (!linkedit || !symCmd || !dysymCmd || !dysymCmd->nindirectsyms) return;

    uintptr_t base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
    struct nlist_64 *symtab = (struct nlist_64 *)(base + symCmd->symoff);
    char *strtab = (char *)(base + symCmd->stroff);
    uint32_t *indirect = (uint32_t *)(base + dysymCmd->indirectsymoff);

    cur = (uintptr_t)hdr + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < hdr->ncmds; i++) {
        struct load_command *lc = (struct load_command *)cur;
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)lc;
            if (strcmp(seg->segname, "__DATA") == 0 || strcmp(seg->segname, "__DATA_CONST") == 0) {
                struct section_64 *sects = (struct section_64 *)((uintptr_t)seg + sizeof(struct segment_command_64));
                for (uint32_t j = 0; j < seg->nsects; j++) {
                    uint32_t type = sects[j].flags & SECTION_TYPE;
                    if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS)
                        patch_section(&sects[j], seg->segname, slide, symtab, strtab, indirect);
                }
            }
        }
        cur += lc->cmdsize;
    }
}

void ap_install_hooks(void) {
    gCache = [NSMutableDictionary new];
    dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_NOW);

    orig_getaddrinfo = (int (*)(const char *, const char *, const struct addrinfo *, struct addrinfo **))
                       dlsym(RTLD_DEFAULT, "getaddrinfo");
    ap_orig_AudioUnitRender = (OSStatus (*)(AudioUnit, AudioUnitRenderActionFlags *, const AudioTimeStamp *,
                                            UInt32, UInt32, AudioBufferList *))dlsym(RTLD_DEFAULT, "AudioUnitRender");
    orig_socket = (int (*)(int, int, int))dlsym(RTLD_DEFAULT, "socket");

    if (orig_getaddrinfo) { gRebinds[gRebindCount].name = "getaddrinfo"; gRebinds[gRebindCount].rep = (void *)my_getaddrinfo; gRebindCount++; }
    if (ap_orig_AudioUnitRender) { gRebinds[gRebindCount].name = "AudioUnitRender"; gRebinds[gRebindCount].rep = (void *)ap_AudioUnitRender; gRebindCount++; }
    if (orig_socket) { gRebinds[gRebindCount].name = "socket"; gRebinds[gRebindCount].rep = (void *)my_socket; gRebindCount++; }
    if (gRebindCount) _dyld_register_func_for_add_image(rebind_image);
}
