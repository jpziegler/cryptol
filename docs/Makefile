MARKDOWN = Syntax.pdf CryptolPrims.pdf Version2Changes.pdf Semantics.pdf
BOOK = Cryptol.pdf

.PHONY: all
all: markdown book

# Use sed to remove backslashes before generating PDF so Pandoc does not
# render them.  They are necessary for Github markdown, but not Pandoc
# markdown.
Version2Table.pdf: Version2Table.md
	sed "s/\\\\//g" $^ | pandoc -f markdown+tex_math_dollars -V geometry:"margin=0.25in" -o $@

Semantics.pdf: ../src/Cryptol/Eval/Reference.lhs
	pandoc -f markdown+lhs -V geometry:"margin=1.25in" $^ --toc -o $@

.PHONY: markdown
markdown: ${MARKDOWN}

.PHONY: book
book:
	(cd ProgrammingCryptol; make)
	cp ProgrammingCryptol/tmp/${BOOK} ./ProgrammingCryptol.pdf

%.pdf: %.md
	pandoc $^ --toc -o $@

.PHONY: clean
clean:
	rm -f ${MARKDOWN}
	rm -f ${BOOK}

.PHONY: squeaky
squeaky:
	rm -f ${MARKDOWN}
	(cd ProgrammingCryptol; make squeaky)
