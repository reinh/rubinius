-include config.mk
include common.mk

INSTALL=install
MKDIR=install -d

ifdef DEV
  BINSUFFIX?=-dev
else
  BINSUFFIX?=
endif

ifeq ($(DTRACE),1)
  DTRACE_H=dtrace.h
else
  DTRACE_H=
endif

CFLAGS += -I.. $(CPPFLAGS) -Iexternal_libs/libbstring -Iexternal_libs/libcchash \
          -Iexternal_libs/libmpa -Iexternal_libs/libmquark -Iexternal_libs/libev \
          -Iexternal_libs/libtommath -Iexternal_libs/libgdtoa

ALIBS= external_libs/libffi/.libs/libffi.a \
       external_libs/libgdtoa/libgdtoa.a \
       external_libs/libtommath/libtommath.a \
       external_libs/onig/.libs/libonig.a \
       external_libs/libltdl/.libs/libltdl.a \
       external_libs/libev/.libs/libev.a \
       external_libs/libbstring/libbstring.a \
       external_libs/libcchash/libcchash.a \
       external_libs/libmpa/libptr_array.a \
       external_libs/libmquark/libmquark.a

LIBS=$(ALIBS) -lz -lm shotgun/lib
LDFLAGS=

# amd64 must have fPIC shared
ifeq ($(MARCH),amd64)
	CFLAGS+=-fPIC
endif

ifeq ($(UNAME),SunOS)
  LDFLAGS+=-lrt
endif

ifeq ($(UNAME),Linux)
	LIBS+=-ldl
endif

OBJS=$(patsubst %.c,%.o,$(shell ls *.c))
RBLIB=lib/$(RBXLIB)

rubinius: rubinius.bin

.PHONY: rubinius

install:
	$(MKDIR) $(LIBPATH)
	$(INSTALL) -c $(RBLIB) $(LIBPATH)
	$(MKDIR) $(BINPATH)
	$(INSTALL) -c rubinius.bin $(BINPATH)/rbx$(BINSUFFIX)

config.h:
	./mkconfig.sh

%.o: %.c
	$(COMP) $(CFLAGS) -c $< 

external_libs/libtommath/libtommath.a:
	cd external_libs/libtommath; $(MAKE)

external_libs/onig/config.h:
	cd external_libs/onig; CFLAGS=-fPIC ./configure

external_libs/onig/.libs/libonig.a:	external_libs/onig/config.h
	cd external_libs/onig; $(MAKE)

# cinvoke doesn't produce a config.h
external_libs/cinvoke/lib/libcinvoke.a:
	cd external_libs/cinvoke; CFLAGS=-fPIC ./configure; $(MAKE)

external_libs/libev/config.h:
	cd external_libs/libev; CFLAGS=-fPIC ./configure

external_libs/libev/.libs/libev.a: external_libs/libev/config.h
	cd external_libs/libev; $(MAKE) libev.la

external_libs/libltdl/config.h:
	cd external_libs/libltdl; CFLAGS=-fPIC ./configure

external_libs/libltdl/.libs/libltdl.a: external_libs/libltdl/config.h
	cd external_libs/libltdl; $(MAKE)

external_libs/libbstring/libbstring.a:
	cd external_libs/libbstring; $(MAKE)

external_libs/libcchash/libcchash.a:
	cd external_libs/libcchash; $(MAKE)

external_libs/libmpa/libptr_array.a:
	cd external_libs/libmpa; $(MAKE)

external_libs/libmquark/libmquark.a:
	cd external_libs/libmquark; $(MAKE)

external_libs/libffi/.libs/libffi.a:
	cd external_libs/libffi; CFLAGS=-fPIC ./configure && $(MAKE)

external_libs/libgdtoa/libgdtoa.a:
	cd external_libs/libgdtoa; $(MAKE)

$(RBLIB): config.h $(DTRACE_H) $(ALIBS)
	cd lib; $(MAKE) library; 

.PHONY: $(RBLIB)

# Don't try to build main until librubinius exists
main.c: $(RBLIB)

dtrace.h: rubinius.d
	/usr/sbin/dtrace -h -s rubinius.d -o dtrace.h

rubinius.bin: $(RBLIB) main.o rubinius.local.bin
	$(COMP) -o rubinius.bin main.o $(RBLIB) $(BIN_RPATH) $(LDFLAGS)

rubinius.local.bin: $(RBLIB) main.o
	$(COMP) -o rubinius.local.bin main.o lib/$(RBXLIBLOCAL) $(BIN_RPATHLOCAL) $(LDFLAGS)

test/test_state: test/test_state.c library
	$(COMP) -c -o test/test_state.o test/test_state.c $(CFLAGS)
	$(COMP) $(LIBS) -o test/test_state test/test_state.o $(RBLIB)

test/test_gc: test/test_gc.c library
	$(COMP) -c -o test/test_gc.o test/test_gc.c $(CFLAGS)
	$(COMP) $(LIBS) -o test/test_gc test/test_gc.o $(RBLIB)

test/test_instructions: test/test_instructions.c library
	$(COMP) -c -o test/test_instructions.o test/test_instructions.c $(CFLAGS)
	$(COMP) $(LIBS) -o test/test_instructions test/test_instructions.o $(RBLIB)

test: test/test_state test/test_instructions
	./test/test_state
	./test/test_instructions

.PHONY: test

clean:
	rm -f *.o *.lo *.gen rubinius.bin rubinius.local.bin
	rm -rf .libs
	cd lib; $(MAKE) clean
.PHONY: clean

# Clean, but also nuke configs
distclean: clean
	rm -f config.h config.mk
	rm -f config/is64bit
	rm -f config/isbigendian
	rm -f external_libs/libev/config.h
	rm -f external_libs/libltdl/config.h
	rm -f external_libs/onig/config.h
	-cd external_libs/libbstring; $(MAKE) clean
	-cd external_libs/libcchash; $(MAKE) clean
	-cd external_libs/libev; $(MAKE) clean
	-cd external_libs/libltdl; $(MAKE) clean
	-cd external_libs/libmpa; $(MAKE) clean
	-cd external_libs/libmquark; $(MAKE) clean
	-cd external_libs/libtommath; $(MAKE) clean
	-cd external_libs/onig; $(MAKE) clean
	-cd external_libs/libffi; $(MAKE) clean
	-cd external_libs/libgdtoa; $(MAKE) clean

.PHONY: distclean
