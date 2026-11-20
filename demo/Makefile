# minih264-flash host demo — see README.md in this directory.
# (The repo-root CMakeLists.txt is the ESP-IDF component; host builds
#  live here and do not touch it.)

CC      ?= cc
CFLAGS  ?= -O2 -Wno-pointer-to-int-cast
INC      = -I../include
LDLIBS   = -lpthread

all: minih264_demo

minih264_demo: minih264_demo.c ../include/minih264e.h
	$(CC) $(CFLAGS) $(INC) minih264_demo.c -o $@ $(LDLIBS)

# reference build: plain C only (the right side of the A/B gate)
minih264_demo_plain: minih264_demo.c ../include/minih264e.h
	$(CC) $(CFLAGS) -DH264E_FORCE_PLAIN_C $(INC) minih264_demo.c -o $@ $(LDLIBS)

# dual-backend build: enables the in-process `--ab` diagnostic
# (on arm64 hosts this goes through the VFT dispatch - see README.md)
minih264_demo_ab: minih264_demo.c ../include/minih264e.h
	$(CC) $(CFLAGS) -DH264E_ENABLE_PLAIN_C=1 $(INC) minih264_demo.c -o $@ $(LDLIBS)

# authoritative host A/B gate: encode the same deterministic clip with the
# SIMD single-config binary and the plain-C binary, then byte-compare.
test: all minih264_demo_plain
	./minih264_demo -o out.h264
	./minih264_demo_plain -o out_plain.h264
	@cmp out.h264 out_plain.h264 \
		&& echo "[gate] PASS (SIMD vs plain-C bitstreams are byte-identical)" \
		|| { echo "[gate] FAIL (bitstreams differ)"; exit 1; }

clean:
	rm -f minih264_demo minih264_demo_plain minih264_demo_ab \
		out*.h264 t*.h264

.PHONY: all test clean
