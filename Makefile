FRAMEWORKS = -framework Foundation

all:macos-root-installer

macos-root-installer:
		mkdir -p build
	  clang main.m -arch i386 -arch x86_64 -o build/macos-root-installer $(FRAMEWORKS) -mmacosx-version-min=10.5

clean: 
	  rm -f build/*
