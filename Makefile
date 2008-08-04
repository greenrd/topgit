# Set PREFIX to wherever you want to install TopGit
PREFIX = $(HOME)
bindir = $(PREFIX)/bin
cmddir = $(PREFIX)/libexec/topgit
sharedir = $(PREFIX)/share/topgit
hooksdir = $(cmddir)/hooks


commands_in = tg-create.sh tg-delete.sh tg-info.sh tg-patch.sh tg-summary.sh tg-update.sh
hooks_in = hooks/pre-commit.sh

commands_out = $(patsubst %.sh,%,$(commands_in))
hooks_out = $(patsubst %.sh,%,$(hooks_in))
help_out = $(patsubst %.sh,%.txt,$(commands_in))

all::	tg $(commands_out) $(hooks_out) $(help_out)

tg $(commands_out) $(hooks_out): % : %.sh
	@echo "[SED] $@"
	@sed -e 's#@cmddir@#$(cmddir)#g;' \
		-e 's#@hooksdir@#$(hooksdir)#g' \
		-e 's#@bindir@#$(bindir)#g' \
		-e 's#@sharedir@#$(sharedir)#g' \
		$@.sh >$@+ && \
	chmod +x $@+ && \
	mv $@+ $@

$(help_out): README
	./create-help.sh `echo $@ | sed -e 's/tg-//' -e 's/\.txt//'`

install:: all
	install tg "$(bindir)"
	install -d -m 755 "$(cmddir)"
	install $(commands_out) "$(cmddir)"
	install -d -m 755 "$(hooksdir)"
	install $(hooks_out) "$(hooksdir)"
	install -d -m 755 "$(sharedir)"
	install $(help_out) "$(sharedir)"

clean::
	rm -f tg $(commands_out) $(hooks_out) $(help_out)
