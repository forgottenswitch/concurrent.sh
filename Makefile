SH = sh

EXAMPLES = \
	manual.sh \
	peach.sh \
	barrier.sh \
	join.sh \
	$()

all:

run:
	for f in $(EXAMPLES) ; do \
		echo ; \
		echo "$(SH) $$f --" ; \
		$(SH) "$$f" ; \
	done

run_via_files:
	CONCURRENTSH_TRANSFER=files ; \
	for f in $(EXAMPLES) ; do \
		echo ; \
		echo "$(SH) $$f --" ; \
		$(SH) "$$f" ; \
	done

test_fifo:
	$(SH) test_fifo.sh 100 10000

.PHONY: all run run_via_files test_fifo
