.PHONY: all
all: out/shalland

.PHONY: run
run: out/shalland
	out/shalland

out:
	mkdir -p out

out/shalland: out $(shell find src)
	go build -o out/shalland ./src/main
