COMPILER=
ARCHIVER=
COMPILER_FLAGS=
EXTRA_COMPILER_FLAGS=
libs:
	$(COMPILER) $(COMPILER_FLAGS) $(EXTRA_COMPILER_FLAGS) -c pan_tilt_bsp.c -o pan_tilt_bsp.o
	$(ARCHIVER) -r ../../../lib/libxil.a pan_tilt_bsp.o
include:
	cp pan_tilt_bsp.h ../../../include/
clean:
	rm -f pan_tilt_bsp.o
