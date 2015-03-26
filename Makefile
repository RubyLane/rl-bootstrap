TCLSH = tclsh8.6

all:

#test:
#	$(TCLSH) tests/all.tcl

test:
	$(TCLSH) tests/runtest.tcl $(TESTARGS)

# test_long:
#     $(TCLSH) tests/runtest.tcl -verbose 1

clean:
