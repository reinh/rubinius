-include ../config.mk
include ../common.mk

CPPFLAGS += -I.. -I../.. -I../../.. \
            -I../external_libs/libffi/include \
            -I../external_libs/libev \
            -I../external_libs/onig \
            -I../external_libs/libgdtoa \
            -I../external_libs/libtommath \
            -I../external_libs/libltdl \
            -I../external_libs/libbstring \
            -I../external_libs/libcchash \
            -I../external_libs/libmpa \
            -I../external_libs/libmquark \
            -D_GNU_SOURCE

LIBS= -lz \
      ../external_libs/libffi/.libs/libffi.a \
      ../external_libs/libgdtoa/libgdtoa.a \
      ../external_libs/libtommath/libtommath.a \
      ../external_libs/onig/.libs/libonig.a \
      $(SINGLE_MODULE) \
      ../external_libs/libev/.libs/libev.a \
      ../external_libs/libltdl/.libs/libltdl.a \
      -lm \
      ../external_libs/libbstring/libbstring.a \
      ../external_libs/libcchash/libcchash.a \
      ../external_libs/libmpa/libptr_array.a \
      ../external_libs/libmquark/libmquark.a

ifeq ($(UNAME),Linux)
  CPPFLAGS += -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64
endif

ifeq ($(UNAME),Darwin)
  CPPFLAGS += -D_XOPEN_SOURCE -D_DARWIN_USE_64_BIT_INODE
  SINGLE_MODULE=-Wl,-single_module
else
  SINGLE_MODULE=
endif

ifneq ($(findstring BSD,$(UNAME)),BSD)
  # BSD do not require a separate libdl
  LIBS+=-ldl
else
  # BSD and Darwin comes with strlcat and strlcpy
  CPPFLAGS+=-DHAVE_STRLCAT -DHAVE_STRLCPY
	CPPFLAGS+=-I/usr/local/include
endif

ifeq ($(UNAME),Darwin)
  # BSD and Darwin comes with strlcat and strlcpy
  CPPFLAGS+=-DHAVE_STRLCAT -DHAVE_STRLCPY
endif

# Linux needs -lrt and -lcrypt
# FreeBSD only needs -lcrypt
# Darwin, OpenBSD and Solaris don't need any
ifeq ($(UNAME),Linux)
	LIBS+= -lrt -lcrypt
endif

ifeq ($(UNAME),FreeBSD)
	LIBS+= -lcrypt
endif

# BSD needs special PThread handling
ifeq ($(findstring BSD,$(UNAME)),BSD)
	LIBS+=-lpthread
endif

ifeq ($(UNAME),SunOS)
  CFLAGS+=-D__C99FEATURES__
  LIBS+= -lsocket
endif

ifdef PROF
  OPTIMIZATIONS=-O2
else 
  ifdef DEV
    OPTIMIZATIONS=-O0
  else
    ifdef TURBO
      OPTIMIZATIONS=-O3 -falign-loops -momit-leaf-frame-pointer -fno-tree-pre
    else
      OPTIMIZATIONS=-O2 -finline-functions
    endif
  endif
endif

ifeq ($(CPU), powerpc)
  OPTIMIZATIONS+=-falign-loops=16
endif

CFLAGS += -fPIC $(CPPFLAGS)
DEPS=auto.h system_primitives.gen instruction_names.c instruction_names.h \
     node_types.c node_types.h

SOURCES=$(sort \
        $(wildcard *.c) \
        $(wildcard subtend/*.c) \
        grammar.c \
        auto.c \
        instruction_names.c \
        node_types.c \
        )
OBJS=$(SOURCES:.c=.o) subtend/PortableUContext_asm.o

# Explicitly require anything you need from kernel/ or lib/
RUBY=ruby

%.o: %.c
	$(COMP) $(CFLAGS) $(OPTIMIZATIONS) -c $< -o $@

%.o: %.S
	$(COMP) $(CFLAGS) $(OPTIMIZATIONS) -c $< -o $@

%.d:  %.c  $(DEPS)
	@echo DEP $<
	@set -e; rm -f $@; \
	$(CC) -MM -MT '$(<:.c=.o)' $(CPPFLAGS) $< > $@.$$$$; \
	sed 's,\($*\)\.o[ :]*,\1.o $@ : ,g' < $@.$$$$ > $@; \
	rm -f $@.$$$$

$(RBXLIB): $(RBXLIBLOCAL)
	$(LINKER) -o $(RBXLIB) $(OBJS) $(SONAME) $(LIBS)

$(RBXLIBLOCAL): $(DEPS) $(OBJS) 
	$(LINKER) -o $(RBXLIBLOCAL) $(OBJS) $(SONAMELOCAL) $(LIBS)

library: $(RBXLIB)

.PHONY: library

cpu_instructions.o: instructions.gen instruction_names.c instruction_names.h
cpu_primitives.o: system_primitives.gen
object_memory.o: object_memory.h

instruction_names.c instruction_names.h instructions.gen: instructions.rb
	$(RUBY) instructions.rb > instructions.gen

system_primitives.gen: primitives.rb
	$(RUBY) primitives.rb > system_primitives.gen

auto.h auto.c: genheader.rb ../../lib/compiler/system_hints.rb
	$(RUBY) genheader.rb > auto.c

node_types.c node_types.h: node_types.rb
	$(RUBY) node_types.rb

grammar.o:
	$(COMP) $(CFLAGS) -c grammar.c

subtend/ffi.o: subtend/ffi.c
	$(COMP) $(CFLAGS) $(OPTIMIZATIONS) -Wno-unused-variable -Wno-unused-value -c $< -o $@

# In a perfect world, we'd only rebuild grammar.c if grammar.y changed.
# However, version control systems do not track file modify times, which will
# mess up make's dependency tracking. So don't depend on grammar.y here.
grammar.c: grammar.y
	bison -o grammar.c grammar.y

clean:
	rm -f *.o \
	      *.lo \
	      *.la \
	      subtend/*.o \
	      subtend/*.lo \
	      subtend/*.d \
	      *.gen \
	      *.a \
	      auto.c \
	      auto.h \
	      *.d \
	      .*.d \
	      *.d.* \
	      instruction_names.c \
	      instruction_names.h \
	      node_types.c \
	      node_types.h \
	      primitive_indexes.h \
	      primitive_util.h

	rm -rf .libs \
	       subtend/.libs \
	       librubinius-* \
	       *.dylib

.PHONY: clean

ifneq ($(MAKECMDGOALS),clean)
-include $(SOURCES:%.c=%.d)
endif
