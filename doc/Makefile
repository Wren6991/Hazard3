.PHONY: all clean view

all:
	@echo ":revdate: Updated: `date +%Y-%b-%d`" > rev.adoc
	asciidoctor-pdf hazard3.adoc

view: all
	xdg-open hazard3.pdf

clean:
	rm -f hazard3.pdf
