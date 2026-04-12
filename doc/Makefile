TOP=hazard3
DEPS=$(shell find -name "*.adoc" | grep -v rev.adoc) diagrams/* *.yml

.PHONY: all clean view spell rev

all: spell $(TOP).pdf $(TOP).html

# `xdg-open` for Ubuntu and friends; `open` for MacOS
view: all
ifneq (,$(shell which xdg-open))
	xdg-open $(TOP).pdf
else
	open $(TOP).pdf
endif

clean:
	rm -f $(TOP).pdf

spell:
ifeq (,$(shell which codespell))
	@echo "Install codespell to check spelling"
else
	@find -name "*.adoc" | xargs codespell -L hart
	@echo "No spelling errors found"
endif

rev:
	@echo ":revdate: Updated: `date +%Y-%b-%d`" > rev.adoc

$(TOP).pdf: $(DEPS) rev
	asciidoctor-pdf -a compress $(TOP).adoc

# data-uri attribute: embed images etc in the HTML as base64. Fine as they are
# small, means the whole doc is one file.
$(TOP).html: $(DEPS) rev
	asciidoctor --section-numbers -a HTMLBUILD $(TOP).adoc

$(TOP).txt: $(DEPS) rev
	asciidoctor-reducer -o $@ -a HTMLBUILD $(TOP).adoc
