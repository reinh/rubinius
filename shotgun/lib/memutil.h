#include <stdint.h>

static inline void fast_memcpy32_x86(void *v_to, void *v_from, int words) {
  uint32_t *to = (uint32_t*)(v_to);
  uint32_t *from = (uint32_t*)(v_from);
  while(words--) { *to++ = *from++; }
}

static inline void fast_memcpy64(void *v_to, void *v_from, int words) {
  uint64_t *to = (uint64_t*)(v_to);
  uint64_t *from = (uint64_t*)(v_from);
  while(words--) { *to++ = *from++; }
}

/* Found this tip floating around the internet. PPC has a 
   preincrement and store opcode, but not post. */
static inline void fast_memcpy32_ppc(void *v_to, void *v_from, int words) {
  uint32_t *to = (uint32_t*)(v_to);
  uint32_t *from = (uint32_t*)(v_from);
  --to;
  --from;
  
  while(words--) { *++to = *++from; }
}

static inline void fast_memfill32_x86(void *v_to, uint32_t val, int words) {
  uint32_t *to = (uint32_t*)(v_to);
  while(words--) { *to++ = val; }
}

static inline void fast_memfill64(void *v_to, uint64_t val, int words) {
  uint64_t *to = (uint64_t*)(v_to);
  while(words--) { *to++ = val; }
}

static inline void fast_memfill32_ppc(void *v_to, uint32_t val, int words) {
  uint32_t *to = (uint32_t*)(v_to);
  --to;
  while(words--) { *++to = val; }
}

static inline void fast_memfill32_s20(void *v_to, uint32_t val) {
  uint32_t *to = (uint32_t*)v_to;
  *(to) = val;
  *(to + 1) = val;
  *(to + 2) = val;
  *(to + 3) = val;
  *(to + 4) = val;
}

static inline void fast_memfill64_s20(void *v_to, uint64_t val) {
  uint64_t *to = (uint64_t*)v_to;
  *(to) = val;
  *(to + 1) = val;
  *(to + 2) = val;
  *(to + 3) = val;
  *(to + 4) = val;
}

#ifdef __POWERPC__
#define fast_memcpy32(a,b,c) fast_memcpy32_ppc(a,b,c)
#define fast_memfill32(a,b,c) fast_memfill32_ppc(a,b,c)
#else
#define fast_memcpy32(a,b,c) fast_memcpy32_x86(a,b,c)
#define fast_memfill32(a,b,c) fast_memfill32_x86(a,b,c)
#endif

#ifdef __x86_64__
#define fast_memcpy(a,b,c) fast_memcpy64(a,b,c)
#define fast_memfill(a,b,c) fast_memfill64(a,b,c)
#define fast_memfill_s20(a,b) fast_memfill64_s20(a,b)
#else
#define fast_memcpy(a,b,c) fast_memcpy32(a,b,c)
#define fast_memfill(a,b,c) fast_memfill32(a,b,c)
#define fast_memfill_s20(a,b) fast_memfill32_s20(a,b)
#endif
