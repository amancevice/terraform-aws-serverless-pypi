all: test validate

clean:
	make -C example clean
	make -C python clean

test:
	make -C python test

validate:
	make -C example validate

.PHONY: test validate
