TopGit installation

Direct from source
==================

Although TopGit is essentially a bunch of shell scripts (and their
accompanying documentation), it does require some preprocessing.

Normally you can just do `make` followed by `make install`, and that will
install the tg program in your own `~/bin/` directory.  If you want to do a
global install, you can do

	# make prefix=/usr install ;# as root

(or `prefix=/usr/local`, of course).  Just like any program suite that uses
$prefix, the built results have some paths encoded, which are derived from
$prefix, so `make; make prefix=/usr install` would not work.

The Makefile does not currently install the bash completion support in
[`contrib/tg-completion.bash`](contrib/tg-completion.bash).
Instructions for installing that file are at the top of that file.


Other
=====

Alternatively, you can install using OS/distro-specific packages or similar,
which should also pull in git as a dependency if you are installing on
a machine which does not already have git installed.

Note that most such packages have not yet been updated to point to the new
TopGit repo on GitHub. Ones that have are listed below:

Linux
-----

* Fedora/EPEL/QubesOS: `yum install topgit`
* Exherbo: `cave resolve dev-scm/topgit -x`
* Nix: `nix-env -f nixpkgs-version -i topgit`
* OpenSuSE: http://software.opensuse.org/download.html?project=home:arvidjaar:TopGIT&package=topgit [unofficial]

Mac OS X
--------

* Nix: `nix-env -f nixpkgs-version -i topgit`

FreeBSD
-------

none as yet
