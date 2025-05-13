prefix = /usr/local
exec_prefix = $(prefix)
bindir = $(exec_prefix)/bin
libdir = $(exec_prefix)/lib

LIBS = \
	libscddl.sh \

SOURCES_PY = \
	cdsdl.py

SOURCES_SH = \
	ebidl.sh \
	ensembldl.sh \
	ncbidl.sh \
	ucscdl.sh \
	uniprotdl.sh \
	diamonddb.sh \

SOURCES = \
	$(SOURCES_PY) \
	$(SOURCES_SH) \

CHECKS_PY = \
	$(SOURCES_PY:.py=.py.check) \

CHECKS_SH = \
	$(LIBS:.sh=.sh.check) \
	$(SOURCES_SH:.sh=.sh.check) \

default:

all: check

%.py.check: %.py
	flake8 $<

%.sh.check: %.sh
	shellcheck -x $<

$(CHECK_PY):

$(CHECKS_SH):

check: \
	$(CHECKS_PY) \
	$(CHECKS_SH) \

install: $(LIBS) $(SOURCES)
	for lib in $(LIBS); do \
	  install -Dm644 $$lib $(DESTDIR)$(libdir)/$$lib; \
	done
	for script in $(SOURCES_SH:.sh=); do \
	  install -Dm755 $$script.sh $(DESTDIR)$(bindir)/$$script; \
	  sed -i \
	    -e "s|source libscddl.sh|source $(libdir)/libscddl.sh|" \
	    $(DESTDIR)$(bindir)/$$script; \
	done
	for script in $(SOURCES_PY:.py=); do \
	  install -Dm755 $$script.py $(DESTDIR)$(bindir)/$$script; \
	done

.PHONY: \
	all \
	check \
	default \
	install \
