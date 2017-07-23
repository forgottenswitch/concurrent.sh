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

test_fifo:
	$(SH) test_fifo.sh 100 10000

.PHONY: all run test_fifo
