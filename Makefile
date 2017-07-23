SH = sh

EXAMPLES = \
	manual.sh \
	peach.sh \
	barrier.sh \
	$()

all:

run:
	for f in $(EXAMPLES) ; do \
		echo ; \
		echo "$(SH) $$f --" ; \
		$(SH) "$$f" ; \
	done

.PHONY: all run
