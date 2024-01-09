all: test validate

clean:
	make -C example clean
	make -C python clean

test:
	make -C python test

validate:
	#terraform fmt -check
	make -C example validate

.PHONY: test validate
