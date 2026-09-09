#!/usr/bin/env python3
"""Build and run the real NIP-808 database fixtures without modifying a user database.

Requires Python 3.9+, a C compiler and the secp256k1 sources from Damus's resolved
Swift package. --secp-dir points to Sources/bindings/secp256k1 in that checkout.
"""
import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc", default=os.environ.get("CC"))
    parser.add_argument("--secp-dir", type=Path)
    parser.add_argument("--sanitize", action="store_true", help="Enable address/undefined sanitizers on a supported compiler")
    args = parser.parse_args()
    ndb = Path(__file__).resolve().parents[1]
    repo = ndb.parent
    compiler = args.cc or shutil.which("cc") or shutil.which("gcc") or shutil.which("clang")
    if not compiler:
        parser.error("No C compiler found; pass --cc /path/to/compiler")
    secp = args.secp_dir
    if secp is None:
        candidates = [
            repo / ".build/index-build/checkouts/secp256k1.swift/Sources/bindings/secp256k1",
            repo / ".build/checkouts/secp256k1.swift/Sources/bindings/secp256k1",
            repo / "build/SourcePackages/checkouts/secp256k1.swift/Sources/bindings/secp256k1",
        ]
        secp = next((p for p in candidates if (p / "src/secp256k1.c").is_file()), None)
    if secp is None or not (secp / "src/secp256k1.c").is_file():
        parser.error("Resolve Damus packages, then pass --secp-dir with the libsecp256k1 source directory")
    secp = secp.resolve()
    relative_sources = [
        "Test/voice_native_test.c", "mdb.c", "midl.c",
        "src/base64.c", "src/binmoji.c", "src/block.c", "src/content_parser.c",
        "src/hkdf_sha256.c", "src/hmac_sha256.c", "src/invoice.c",
        "src/metadata.c", "src/nip44.c", "src/nostr_bech32.c",
        "src/sodium/crypto_stream_chacha20.c",
    ]
    relative_sources += [
        "src/bolt11/" + name + ".c"
        for name in ["amount", "bech32", "bech32_util", "bolt11", "error", "hash_u5"]
    ]
    relative_sources += [
        "ccan/ccan/" + name + ".c"
        for name in ["crypto/sha256/sha256", "htable/htable", "likely/likely", "list/list",
                     "mem/mem", "str/str", "take/take", "tal/tal", "tal/str/str", "utf8/utf8"]
    ]
    relative_sources += [
        "flatcc/" + name + ".c"
        for name in ["builder", "emitter", "json_parser", "json_printer", "refmap", "verifier"]
    ]
    sources = [ndb / name for name in relative_sources]
    sources += [secp / "src" / name for name in ["secp256k1.c", "precomputed_ecmult.c", "precomputed_ecmult_gen.c"]]
    for source in sources:
        if not source.is_file():
            parser.error("Missing required source: " + str(source))
    flags = ["-std=gnu11", "-O1", "-g", "-D_GNU_SOURCE",
             "-DECMULT_WINDOW_SIZE=15", "-DECMULT_GEN_PREC_BITS=4",
             "-DENABLE_MODULE_ECDH", "-DENABLE_MODULE_EXTRAKEYS",
             "-DENABLE_MODULE_RECOVERY", "-DENABLE_MODULE_SCHNORRSIG",
             "-Wno-deprecated-declarations"]
    # Quoted local includes must not shadow platform headers such as <io.h>.
    for include in [ndb / "src", ndb]:
        flags += ["-iquote", str(include)]
    for include in [ndb / "ccan", ndb / "flatcc", secp / "include"]:
        flags += ["-I", str(include)]
    libraries = ["-lm"]
    if sys.platform == "win32":
        libraries += ["-lbcrypt", "-lntdll"]
    else:
        flags += ["-pthread"]
        if sys.platform == "darwin":
            # Darwin uses named LMDB semaphores. Without this definition the
            # literal macro name plus the hashed suffix overflows MNAME_LEN.
            flags += ["-DMDB_SEM_NAME_PREFIX=damus-voice"]
            libraries += ["-framework", "Security"]
    if args.sanitize:
        flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    subprocess.run([compiler, "--version"], check=True)
    with tempfile.TemporaryDirectory(prefix="damus-voice-native-") as scratch:
        scratch = Path(scratch)
        binary = scratch / ("voice-tests.exe" if sys.platform == "win32" else "voice-tests")
        command = [compiler, *flags, *map(str, sources), "-o", str(binary), *libraries]
        print("BUILD:", shlex.join(command), flush=True)
        subprocess.run(command, check=True, timeout=240)
        databases = scratch / "databases"
        databases.mkdir()
        print("RUN:", binary, databases, flush=True)
        subprocess.run([str(binary), str(databases)], check=True, timeout=120)
        print("PASS: native voice regression executable completed", flush=True)


if __name__ == "__main__":
    main()
