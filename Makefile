prefix ?= $(HOME)
bindir := $(prefix)/bin
cmddir := $(prefix)/libexec/topgit
sharedir := $(prefix)/share/topgit
hooksdir := $(cmddir)/hooks


commands_in := $(wildcard tg-*.sh)
hooks_in = hooks/pre-commit.sh

commands_out := $(patsubst %.sh,%,$(commands_in))
hooks_out := $(patsubst %.sh,%,$(hooks_in))
help_out := $(patsubst %.sh,%.txt,$(commands_in))

version = $(shell test -d .git && git describe --match "topgit-[0-9]*" --abbrev=4 HEAD 2>/dev/null | sed -e 's/^topgit-//' )
ifneq ($(strip $(version)),)
	version_arg = -e s/TG_VERSION=.*/TG_VERSION=$(version)/
endif

all::	precheck $(commands_out) $(hooks_out) $(help_out)

tg $(commands_out) $(hooks_out): % : %.sh Makefile
	@echo "[SED] $@"
	@sed -e 's#@cmddir@#$(cmddir)#g;' \
		-e 's#@hooksdir@#$(hooksdir)#g' \
		-e 's#@bindir@#$(bindir)#g' \
		-e 's#@sharedir@#$(sharedir)#g' \
		$(version_arg) \
		$@.sh >$@+ && \
	chmod +x $@+ && \
	mv $@+ $@

$(help_out): README create-help.sh
	@CMD=`echo $@ | sed -e 's/tg-//' -e 's/\.txt//'` && \
	echo '[HELP]' $$CMD && \
	./create-help.sh $$CMD

precheck:: tg
	./$+ precheck

install:: all
	install -d -m 755 "$(DESTDIR)$(bindir)"
	install tg "$(DESTDIR)$(bindir)"
	install -d -m 755 "$(DESTDIR)$(cmddir)"
	install $(commands_out) "$(DESTDIR)$(cmddir)"
	install -d -m 755 "$(DESTDIR)$(hooksdir)"
	install $(hooks_out) "$(DESTDIR)$(hooksdir)"
	install -d -m 755 "$(DESTDIR)$(sharedir)"
	install -m 644 $(help_out) "$(DESTDIR)$(sharedir)"
	install -m 644 leaves.awk "$(DESTDIR)$(sharedir)"

clean::
	rm -f tg $(commands_out) $(hooks_out) $(help_out)

check::
	@./vendor/bats/libexec/bats --pretty tests
