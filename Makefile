prefix = /usr/local
exec_prefix = $(prefix)
bindir = $(exec_prefix)/bin
libdir = $(exec_prefix)/lib

LIBS = \
	libscddl.sh \

SOURCES = \
	ebidl.sh \
	ensembldl.sh \
	ncbidl.sh \
	ucscdl.sh \
	diamonddb.sh \

CHECKS = \
	$(LIBS:.sh=.check) \
	$(SOURCES:.sh=.check) \

default:

all: check

%.check: %.sh
	shellcheck -x $<

$(CHECKS):

check: $(CHECKS)

install: $(LIBS) $(SOURCES)
	for lib in $(LIBS); do \
	  install -Dm644 $$lib $(DESTDIR)$(libdir)/$$lib; \
	done
	for script in $(SOURCES:.sh=); do \
	  install -Dm755 $$script.sh $(DESTDIR)$(bindir)/$$script; \
	  sed -i \
	    -e "s|source libscddl.sh|source $(libdir)/libscddl.sh|" \
	    $(DESTDIR)$(bindir)/$$script; \
	done

.PHONY: \
	all \
	check \
	default \
	install \
