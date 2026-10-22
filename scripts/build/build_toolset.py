#!/usr/bin/env python3
"""Собирает набор aarch64-musl утилит из официального репозитория Alpine.

Цепочка доверия: подпись APKINDEX (проверена отдельно openssl) -> контрольные
суммы пакетов из индекса -> скачанный .apk.
"""
import base64, hashlib, io, json, pathlib, re, subprocess, tarfile, urllib.request, zlib

BASE = "https://dl-cdn.alpinelinux.org/alpine/latest-stable/{repo}/aarch64/{name}"
REPOS = ("main", "community")
WANTED = ["musl", "jq", "strace", "lsof", "tmux", "rsync", "bind-tools",
          "socat", "netcat-openbsd", "unzip", "zstd", "pv", "less", "file", "tree"]
WORK = pathlib.Path(__file__).parent
CACHE = WORK / "apk"
INDEX = {}


def load_index():
    for repo in REPOS:
        tf = tarfile.open(WORK / f"APKINDEX-{repo}.tar.gz")
        text = tf.extractfile("APKINDEX").read().decode()
        for block in text.split("\n\n"):
            rec = {}
            for line in block.splitlines():
                if len(line) > 2 and line[1] == ":":
                    rec[line[0]] = line[2:]
            if "P" in rec:
                rec["repo"] = repo
                INDEX.setdefault(rec["P"], []).append(rec)


def refresh():
    for repo in REPOS:
        dst = WORK / f"APKINDEX-{repo}.tar.gz"
        if not dst.exists():
            urllib.request.urlretrieve(BASE.format(repo=repo, name="APKINDEX.tar.gz"), dst)
    load_index()


def best(name):
    """Самая свежая версия пакета (Alpine отдаёт список в порядке приоритета)."""
    cands = INDEX.get(name)
    return cands[0] if cands else None


def dep_name(dep):
    dep = dep.split("@")[0]
    for sep in (">=", "<=", "=", ">", "<", "~"):
        dep = dep.split(sep)[0]
    return dep.strip()


def providers_for_so(soname):
    for name, recs in INDEX.items():
        for rec in recs:
            for prov in rec.get("p", "").split():
                if prov.split("=")[0] == soname:
                    return name
    return None


def resolve(roots):
    chosen, queue, missing = {}, list(roots), []
    while queue:
        name = queue.pop(0)
        if name in chosen:
            continue
        rec = best(name)
        if rec is None and name.startswith("so:"):
            alt = providers_for_so(name)
            rec = best(alt) if alt else None
        if rec is None:
            missing.append(name)
            continue
        chosen[rec["P"]] = rec
        real = rec["P"]
        for dep in rec.get("D", "").split():
            if dep.startswith("!") or dep.startswith("cmd:") or dep in ("/bin/sh", "so:ld-linux-aarch64.so.1"):
                continue
            dname = dep_name(dep)
            if dname.startswith("so:") or dname in INDEX:
                queue.append(dname)
    return chosen, missing


def fetch_apk(rec):
    CACHE.mkdir(exist_ok=True)
    dst = CACHE / f"{rec['P']}-{rec['V']}.apk"
    if not dst.exists():
        url = BASE.format(repo=rec["repo"], name=f"{rec['P']}-{rec['V']}.apk")
        with urllib.request.urlopen(url, timeout=120) as r, open(dst, "wb") as f:
            f.write(r.read())
    return dst


def segments(path):
    """.apk = [подпись][служебная часть][данные], каждый сегмент — свой gzip."""
    raw = path.read_bytes()
    out, rest = [], raw
    while rest:
        d = zlib.decompressobj(31)
        head = d.decompress(rest)
        used = len(rest) - len(d.unused_data)
        out.append((rest[:used], head))
        rest = d.unused_data
    return out


KEYS_DIR = WORK / "keys"


def fetch_key(name):
    KEYS_DIR.mkdir(exist_ok=True)
    p = KEYS_DIR / name
    if not p.exists():
        urllib.request.urlretrieve(f"https://alpinelinux.org/keys/{name}", p)
    return p


def checksum_ok(path, expect):
    """Подпись пакета — по служебной части; Q1 в индексе — её sha1. Обе проверки разом."""
    segs = segments(path)
    if len(segs) < 3:
        return False, "не разобрал формат"
    control = segs[1][0]
    got = "Q1" + base64.b64encode(hashlib.sha1(control).digest()).decode()
    if got != expect:
        return False, got
    with tarfile.open(fileobj=io.BytesIO(segs[0][1])) as tf:
        sig_member = [m for m in tf.getmembers() if m.name.startswith(".SIGN")][0]
        sig = tf.extractfile(sig_member).read()
    key_name = sig_member.name.split(".SIGN.RSA.", 1)[1]
    key = fetch_key(key_name)
    sig_file = path.with_suffix(".sig")
    data_file = path.with_suffix(".ctl")
    sig_file.write_bytes(sig)
    data_file.write_bytes(control)
    r = subprocess.run(["openssl", "dgst", "-sha1", "-verify", str(key),
                        "-signature", str(sig_file), str(data_file)],
                       capture_output=True, text=True)
    sig_file.unlink()
    data_file.unlink()
    return "Verified OK" in r.stdout, got


def extract_data_member(path, dest):
    segs = segments(path)
    if len(segs) < 3:
        return False
    dest = pathlib.Path(dest)
    with tarfile.open(fileobj=io.BytesIO(segs[2][1])) as tf:
        for m in tf.getmembers():
            name = m.name.lstrip("./")
            if not name or name.startswith(".") or ".." in name.split("/"):
                continue
            target = dest / name
            if m.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            if m.issym():
                link = m.linkname
                if link.startswith("/") or ".." in link.split("/"):
                    continue
                target.symlink_to(link)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with tf.extractfile(m) as src, open(target, "wb") as out:
                out.write(src.read())
            target.chmod(m.mode & 0o777)
    return True


def main(roots=None, stage_name="stage"):
    refresh()
    chosen, missing = resolve(roots or WANTED)
    print(f"пакетов в наборе: {len(chosen)}")
    if missing:
        print("не разрешено:", ", ".join(sorted(set(missing))))
    total = 0
    bad = []
    stage = WORK / stage_name
    for name, rec in sorted(chosen.items()):
        apk = fetch_apk(rec)
        total += apk.stat().st_size
        ok, got = checksum_ok(apk, rec.get("C", ""))
        if not ok:
            bad.append((name, got, rec.get("C")))
            continue
        extract_data_member(apk, stage)
    print(f"скачано: {total/1e6:.1f} МБ, распаковано в {stage}")
    if bad:
        print("НЕ СОВПАЛИ СУММЫ:", bad)
    else:
        print("суммы всех пакетов совпали с подписанным индексом")
    json.dump({n: {"version": r["V"], "repo": r["repo"], "md5index": r.get("C")}
               for n, r in chosen.items()}, open(WORK / "staged.json", "w"), indent=1)


if __name__ == "__main__":
    main()
