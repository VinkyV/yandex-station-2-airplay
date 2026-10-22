#!/usr/bin/env python3
"""Собирает из распакованного Alpine-набора компактный бандл для колонки.

Кладёт в out/: bin/ (нужные программы), lib/ (только нужные .so + musl-загрузчик),
share/terminfo, install.sh (установка на устройстве), MANIFEST.txt (sha256 + версии).
"""
import hashlib, pathlib, shutil, struct, subprocess, json

WORK = pathlib.Path(__file__).parent
STAGE = WORK / "stage"
OUT = WORK / "out"
BINARIES = ["jq", "strace", "lsof", "tmux", "rsync", "dig", "host", "nslookup",
            "nc", "socat1", "unzip", "zstd", "pv", "less", "tree", "file"]
EXTRA_ALIASES = {"socat": "socat1"}


def dt_needed(path):
    """Читает DT_NEEDED из ELF64 aarch64 без внешних утилит."""
    data = path.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 2:
        return []
    e_phoff, = struct.unpack_from("<Q", data, 0x20)
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 0x36)
    dyn = None
    for i in range(e_phnum):
        base = e_phoff + i * e_phentsize
        p_type, = struct.unpack_from("<I", data, base)
        if p_type == 2:  # PT_DYNAMIC
            p_offset, = struct.unpack_from("<Q", data, base + 0x08)
            p_filesz, = struct.unpack_from("<Q", data, base + 0x20)
            dyn = (p_offset, p_filesz)
    if not dyn:
        return []
    off, size = dyn
    strtab = None
    needed_off = []
    for pos in range(off, off + size, 16):
        tag, val = struct.unpack_from("<qQ", data, pos)
        if tag == 0:
            break
        if tag == 5:
            strtab = val
        elif tag == 1:
            needed_off.append(val)
    if strtab is None:
        return []
    out = []
    for o in needed_off:
        end = data.index(b"\0", strtab + o)
        out.append(data[strtab + o:end].decode())
    return out


def find_lib(soname, search):
    for d in search:
        p = d / soname
        if p.is_file():
            return p
    return None


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", default="stage")
    ap.add_argument("--out", default="out")
    ap.add_argument("--bins", required=True, help="через запятую")
    ap.add_argument("--aliases", default="", help="новое=существующее,через,запятую")
    args = ap.parse_args()
    globals()["STAGE"] = WORK / args.stage
    globals()["OUT"] = WORK / args.out
    globals()["BINARIES"] = [b for b in args.bins.split(",") if b]
    globals()["EXTRA_ALIASES"] = dict(a.split("=") for a in args.aliases.split(",") if a)
    build()


def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "bin").mkdir(parents=True)
    (OUT / "lib").mkdir()
    search = [STAGE / "lib", STAGE / "usr/lib"]
    libdirs = list(search)

    libs, queue, seen = set(), [], set()
    for name in BINARIES:
        src = None
        for d in (STAGE / "usr/bin", STAGE / "bin", STAGE / "usr/sbin", STAGE / "sbin"):
            cand = d / name
            if cand.exists():
                src = cand
                break
        if src is None:
            print("нет бинарника:", name)
            continue
        shutil.copy2(src, OUT / "bin" / name)
        for need in dt_needed(src):
            queue.append(need)
    for alias, target in EXTRA_ALIASES.items():
        (OUT / "bin" / alias).symlink_to(target)

    while queue:
        soname = queue.pop()
        if soname in seen:
            continue
        seen.add(soname)
        lib = find_lib(soname, libdirs)
        if lib is None:
            print("не нашёл библиотеку:", soname)
            continue
        dest = OUT / "lib" / soname
        if not dest.exists():
            shutil.copy2(lib, dest)
        libs.add(soname)
        for need in dt_needed(lib):
            queue.append(need)

    loader = STAGE / "lib" / "ld-musl-aarch64.so.1"
    shutil.copy2(loader, OUT / "lib" / "ld-musl-aarch64.so.1")

    for src in (STAGE / "etc/terminfo", STAGE / "usr/share/terminfo"):
        if src.exists():
            shutil.copytree(src, OUT / "share/terminfo", dirs_exist_ok=True)
            break

    lines = [f"собрано: {WORK}", "", "== содержимое =="]
    for p in sorted(OUT.rglob("*")):
        if p.is_file() and not p.is_symlink():
            h = hashlib.sha256(p.read_bytes()).hexdigest()
            lines.append(f"{h}  {p.relative_to(OUT)}  {p.stat().st_size}")
    (OUT / "MANIFEST.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:6]))
    print(f"файлов: {len(lines)-3}, размер: {sum(p.stat().st_size for p in OUT.rglob('*') if p.is_file())/1e6:.1f} МБ")


if __name__ == "__main__":
    main()
