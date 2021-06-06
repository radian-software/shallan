.PHONY: all
all: out/shalland

.PHONY: run
run: out/shalland
	out/shalland --host=localhost --port=4381 --database out/library.sqlite3

out:
	mkdir -p out

out/shalland: out $(shell find src)
	go build -o out/shalland ./src
