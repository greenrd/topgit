# Set PREFIX to wherever you want to install TopGit
PREFIX = $(HOME)
bindir = $(PREFIX)/bin
cmddir = $(PREFIX)/libexec/topgit
hooksdir = $(cmddir)/hooks


commands_in = tg-create.sh tg-delete.sh tg-info.sh tg-patch.sh tg-summary.sh tg-update.sh
hooks_in = hooks/pre-commit.sh

commands_out = $(patsubst %.sh,%,$(commands_in))
hooks_out = $(patsubst %.sh,%,$(hooks_in))

all::	tg $(commands_out) $(hooks_out)

tg $(commands_out) $(hooks_out): % : %.sh
	@echo "[SED] $@"
	@sed -e 's#@cmddir@#$(cmddir)#g;' \
		-e 's#@hooksdir@#$(hooksdir)#g' \
		-e 's#@bindir@#$(bindir)#g' \
		$@.sh >$@+ && \
	chmod +x $@+ && \
	mv $@+ $@


install:: all
	install tg "$(bindir)"
	install -d -m 755 "$(cmddir)"
	install $(commands_out) "$(cmddir)"
	install -d -m 755 "$(hooksdir)"
	install $(hooks_out) "$(hooksdir)"

clean::
	rm -f tg $(commands_out) $(hooks_out)
