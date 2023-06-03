
all: nostrscript/primal.wasm

nostrscript/%.wasm: nostrscript/%.ts nostrscript/nostr.ts Makefile
	asc $< --runtime stub --outFile $@  --optimize

clean:
	rm nostrscript/*.wasm
