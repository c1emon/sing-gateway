.PHONY: all deb

all:
	@:

deb:
	dpkg-buildpackage -us -uc -b
