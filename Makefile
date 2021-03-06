include configure.mk

# Test flavour. See test/toxcore/Makefile for choices.
TEST	:= vanilla

SRCDIRS	:= src test tools
SOURCES	:= $(shell find $(SRCDIRS) -name "*.*hs" -or -name "*.c" -or -name "*.h")

export LD_LIBRARY_PATH := $(HOME)/.cabal/extra-dist/lib

EXTRA_DIRS :=							\
	--extra-include-dirs=$(HOME)/.cabal/extra-dist/include	\
	--extra-lib-dirs=$(HOME)/.cabal/extra-dist/lib

CONFIGURE_FLAGS :=		\
	--enable-benchmarks	\
	--enable-tests		\
	$(DISABLE_PROFILING)	\
	$(EXTRA_DIRS)

CLANG_TIDY_FLAGS :=					\
	$(wildcard test/toxcore/*.[ch])			\
	-fix						\
	--						\
	-Itest/toxcore/libsodium/src/libsodium/include	\
	-Itest/toxcore/msgpack-c/include		\
	-Itest/toxcore/toxcore/toxcore

CLANG_FORMAT_FLAGS :=	\
	-style=file	\
	-i

HSTOX_TIX	= dist/hpc/tix/hstox/hstox.tix
SUT_TOXCORE	= dist/build/sut-toxcore/sut-toxcore
TEST_TOXCORE	= dist/build/test-toxcore/test-toxcore


all: check $(DOCS)
	$(MAKE) -C tools/docker scripts

fuzz: .build.stamp
	@echo "Cleaning up previous results"
	@$(MAKE) -C test/toxcore clean
	@echo "Generating initial test inputs"
	@rm -f test/toxcore/test-inputs/*
	@$(TEST_TOXCORE) --qc-max-success=1 --format=silent
	@$(MAKE) -C test/toxcore master

check: $(HSTOX_TIX)
	hpc markup $(HPC_DIRS) --destdir=dist/hpc/html $< > /dev/null
	hpc report $(HPC_DIRS) $<

$(HSTOX_TIX): .build.stamp
	cabal test $(CABAL_JOBS) | grep -v '^Writing: '
	mkdir -p $(@D)
	hpc sum --exclude=Main --union `find dist -name "*.tix" -and -not -wholename "*$@"` --output=$@

check-toxcore: $(SUT_TOXCORE)
	cabal test test-toxcore $(CABAL_JOBS)

repl:
	rm -f .configure.stamp
	cabal configure $(CONFIGURE_FLAGS)
	cabal repl

clean:
	cabal clean
	rm -f $(wildcard .*.stamp *.tix)
	@$(MAKE) -C test/toxcore clean


build: .build.stamp
.build.stamp: $(SOURCES) .configure.stamp .format.stamp .lint.stamp
	rm -f $(wildcard *.tix)
	cabal build $(CABAL_JOBS)
	@touch $@

$(SUT_TOXCORE): test/toxcore/test_main-$(TEST)
	mkdir -p $(@D)
	cp $< $@

test/toxcore/test_main-$(TEST): $(shell find test/toxcore -name "*.[ch]") test/toxcore/Makefile
	make -C $(@D) $(@F)

configure: .configure.stamp
.configure.stamp: .libsodium.stamp hstox.cabal
	cabal update
	cabal install $(CONFIGURE_FLAGS) --only-dependencies $(CABAL_JOBS)
	cabal configure $(CONFIGURE_FLAGS) $(ENABLE_COVERAGE)
	@touch $@

doc: $(DOCS)
../tox-spec/spec.md: src/tox/Network/Tox.lhs $(shell find src -name "*.lhs") ../tox-spec/pandoc.mk
	echo '% The Tox Reference' > $@
	echo '' >> $@
	pandoc $< $(PANDOC_ARGS)							\
		-f latex+lhs								\
		-t $(FORMAT)								\
		| perl -pe 'BEGIN{undef $$/} s/\`\`\` sourceCode\n.*?\`\`\`\n\n//sg'	\
		>> $@
	pandoc $(PANDOC_ARGS) -f $(FORMAT) -t $(FORMAT) $@ -o $@
	if which mdl; then $(MAKE) -C ../tox-spec check; fi
	if test -d ../toktok.github.io; then $(MAKE) -C ../toktok.github.io push; fi

libsodium: .libsodium.stamp
.libsodium.stamp: tools/install-libsodium
	$<
	@touch $@

format: .format.stamp
.format.stamp: $(SOURCES) .configure.stamp
	if which stylish-haskell; then tools/format-haskell -i $(SRCDIRS); fi
	if which $(CLANG_FORMAT); then $(CLANG_FORMAT) $(CLANG_FORMAT_FLAGS) test/toxcore/*.[ch]; fi
	if which $(CLANG_TIDY); then $(CLANG_TIDY) $(CLANG_TIDY_FLAGS); fi
	@touch $@

lint: .lint.stamp
.lint.stamp: $(SOURCES) .configure.stamp
	if which hlint; then hlint --cross src; fi
	@touch $@
