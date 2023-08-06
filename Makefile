
all: nostrscript/primal.wasm

nostrscript/%.wasm: nostrscript/%.ts nostrscript/nostr.ts Makefile
	asc $< --runtime stub --outFile $@  --optimize

tags:
	find damus-c -name '*.c' -or -name '*.h' | xargs ctags

clean:
	rm nostrscript/*.wasm

.PHONY: tags
