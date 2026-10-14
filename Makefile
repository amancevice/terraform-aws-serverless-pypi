all: test validate

clean lock:
	make -C example $@
	make -C python $@

test:
	make -C python test

validate:
	make -C example validate

.PHONY: lock test validate
