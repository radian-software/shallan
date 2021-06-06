.PHONY: all
all: out/shalland

.PHONY: run
run: out/shalland
	out/shalland --host=localhost --port=4381 --database out/library.sqlite3

.PHONY: watch
watch:
	watchexec -e go -r -n make run

out:
	mkdir -p out

out/shalland: out $(shell find src)
	go build -o out/shalland ./src
