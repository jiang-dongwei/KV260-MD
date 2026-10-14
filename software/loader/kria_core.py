#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verified KV260 application replacement. Invoked by Main with all UIO maps closed.

Hashes detect damaged bundles, not hostile firmware. Bundles are trusted hardware
applications. This program never unbinds a live MiSTer DMA master before draining it.
"""
import argparse
import contextlib
from dataclasses import dataclass, field
import fcntl
import hashlib
import io
import json
import mmap
import os
from pathlib import Path, PurePosixPath
import re
import struct
import stat
import shutil
import zipfile
import subprocess
import sys
import tempfile
import time

ABI = 0x00010000
MEMORY_SIZE = 0x20000000
FIRMWARE = "kria-mister/active.bit.bin"
MENU = Path("/media/fat/menu.k26")
OVERLAYS = Path("/sys/kernel/config/device-tree/overlays")
OVERLAY = OVERLAYS / "kria-mister"
STATE = Path("/run/kria-mister")
DP_DEVICE = "fd4a0000.display"
FPGA_MANAGERS = Path("/sys/class/fpga_manager")


class CoreError(Exception):
    pass


def run(*args):
    try:
        return subprocess.run(args, check=True, capture_output=True, text=True,
                              timeout=30).stdout.strip()
    except (OSError, subprocess.SubprocessError) as exc:
        raise CoreError(f"command {args[0]} failed: {exc}") from exc


def limited_read(path, limit):
    with path.open("rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise CoreError(f"not a regular bundle file: {path}")
        data = stream.read(limit + 1)
    if not data or len(data) > limit:
        raise CoreError(f"empty or oversized bundle file: {path}")
    return data


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise CoreError(f"duplicate manifest key: {key}")
        result[key] = value
    return result


def member(archive, record, limit):
    if not isinstance(record, dict) or set(record) != {"file", "sha256"}:
        raise CoreError("artifact requires file and sha256")
    name, digest = record["file"], record["sha256"]
    if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*", name):
        raise CoreError("invalid archive filename")
    if any(part in (".", "..") for part in name.split("/")):
        raise CoreError("artifact must remain inside the core file")
    if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise CoreError("invalid SHA256 digest")
    info = archive.getinfo(name)
    if not 0 < info.file_size <= limit or info.compress_type != zipfile.ZIP_STORED:
        raise CoreError("empty, oversized or unsupported archive member")
    data = archive.read(info)
    if hashlib.sha256(data).hexdigest() != digest:
        raise CoreError(f"SHA256 mismatch: {name}")
    return data


def check_overlay(data):
    # Use the exact bytes later submitted to configfs, never reopen SD artifacts.
    with tempfile.TemporaryDirectory(prefix="kria-dt-") as directory:
        path = Path(directory) / "core.dtbo"
        path.write_bytes(data)
        firmware = run("fdtget", "-t", "s", str(path),
                       "/fragment@0/__overlay__", "firmware-name")
        target = run("fdtget", "-t", "s", str(path), "/__fixups__", "fpga_full")
        if firmware != FIRMWARE or "/fragment@0:target:0" not in target.split():
            raise CoreError("overlay must program fpga_full with the fixed firmware slot")


@dataclass(frozen=True)
class Bundle:
    path: Path
    core_id: str
    bitstream: bytes
    overlay: bytes
    # Historical field name; version 2 hashes the entire single-file package.
    manifest_sha256: str
    manifest: dict = field(default_factory=dict)
    assets: dict = field(default_factory=dict)


def verify(path):
    path = Path(path).resolve(strict=True)
    if path.suffix.lower() != ".k26":
        raise CoreError("expected a .k26 core file")
    raw = limited_read(path, 82 * 1024 * 1024)
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)) or not 3 <= len(names) <= 35:
                raise CoreError("duplicate or excessive archive members")
            info = archive.getinfo("manifest.json")
            if not 0 < info.file_size <= 65536 or info.compress_type != zipfile.ZIP_STORED:
                raise CoreError("invalid manifest size or encoding")
            manifest = json.loads(archive.read(info), object_pairs_hook=unique_object)
            if not isinstance(manifest, dict):
                raise CoreError("manifest must be an object")
            if (manifest.get("format") != "kria-mister-core" or
                    type(manifest.get("version")) is not int or manifest["version"] != 2):
                raise CoreError("unsupported single-file core format/version")
            identity = manifest.get("id")
            if not isinstance(identity, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", identity):
                raise CoreError("invalid core identity")
            if manifest.get("part") != "xck26-sfvc784-2LV-c":
                raise CoreError("incompatible FPGA device")
            if type(manifest.get("abi")) is not int or manifest["abi"] != ABI:
                raise CoreError("incompatible control ABI")
            if type(manifest.get("memory_size")) is not int or manifest["memory_size"] != MEMORY_SIZE:
                raise CoreError("incompatible logical memory window")
            if manifest.get("display") != "1920x1080p60":
                raise CoreError("unsupported display profile")
            bitstream = member(archive, manifest.get("bitstream"), 64 * 1024 * 1024)
            overlay = member(archive, manifest.get("overlay"), 1024 * 1024)
            expected = {"manifest.json", manifest["bitstream"]["file"], manifest["overlay"]["file"]}
            if len(expected) != 3:
                raise CoreError("artifact names overlap")
            assets = {}
            records = manifest.get("assets", [])
            if not isinstance(records, list) or len(records) > 32:
                raise CoreError("invalid assets list")
            for asset in records:
                if not isinstance(asset, dict) or set(asset) != {"name", "file", "sha256"}:
                    raise CoreError("invalid embedded asset")
                name = asset["name"]
                if (not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", name)
                        or name in assets or not isinstance(asset["file"], str) or asset["file"] in expected):
                    raise CoreError("invalid or duplicate asset name")
                assets[name] = member(archive, {k: asset[k] for k in ("file", "sha256")}, 16*1024*1024)
                expected.add(asset["file"])
            if sum(map(len, assets.values())) > 16*1024*1024 or set(names) != expected:
                raise CoreError("unexpected or oversized package contents")
    except (zipfile.BadZipFile, KeyError, UnicodeError, RuntimeError) as exc:
        raise CoreError(f"invalid single-file core package: {exc}") from exc
    check_overlay(overlay)
    return Bundle(path, identity, bitstream, overlay, hashlib.sha256(raw).hexdigest(), manifest, assets)


def write_package(path, manifest, members):
    """Build a deterministic, uncompressed single-file core for redistribution."""
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED) as archive:
        contents = {"manifest.json": (json.dumps(manifest, indent=2, sort_keys=True)+"\n").encode(), **members}
        for name, data in sorted(contents.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    atomic_write(Path(path), output.getvalue())


def stage_assets(bundle, state=None):
    # Main is stopped and DMA drained before Platform.apply. Required helper
    # ROMs travel inside the core and are materialized only in volatile storage.
    state = STATE if state is None else Path(state)
    state.mkdir(parents=True, exist_ok=True)
    assets = state / "assets"
    if assets.exists():
        shutil.rmtree(assets)
    assets.mkdir()
    for name, data in bundle.assets.items():
        atomic_write(assets/name, data)


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".new-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(name)


def controllers():
    return [p.parent for p in Path("/sys/class/uio").glob("uio*/name")
            if p.read_text().strip() == "kria-mister"]


class Platform:
    """Board effects kept separate so failure ordering can be tested off-board."""
    def preflight(self):
        if not OVERLAYS.is_dir():
            raise CoreError("device-tree configfs is not mounted")
        if any(p.is_dir() and p != OVERLAY for p in OVERLAYS.iterdir()):
            raise CoreError("another application owns an overlay; refusing replacement")
        if len(controllers()) > 1:
            raise CoreError("ambiguous MiSTer UIO controller")
        if controllers() and not OVERLAY.exists():
            raise CoreError("MiSTer controller is not owned by this loader")
        run("modprobe", "xlnx_avpg")
        run("modprobe", "kria_mister_uio")

    def stop_display(self):
        run("systemctl", "stop", "kria-display.service")

    def drain(self):
        for uio in controllers():
            device = (uio / "device").resolve(strict=True)
            if int((device / "users").read_text()) != 0:
                raise CoreError("Main still owns a UIO file/mapping")
            # The kernel atomically closes admission and waits for all AXI responses.
            (device / "quiesce").write_text("1\n")

    def unbind_display(self):
        driver = Path("/sys/bus/platform/devices") / DP_DEVICE / "driver"
        if driver.exists():
            (driver.resolve() / "unbind").write_text(DP_DEVICE)

    def remove(self):
        if OVERLAY.exists():
            OVERLAY.rmdir()

    def reset_fpga_manager(self):
        # linux-xilinx's DMA-BUF ioctl leaves FPGA_MGR_CONFIG_DMA_BUF set after
        # it drops the buffer.  A later firmware/configfs load would then attach
        # that stale pointer and can BUG in cma_heap_attach().  This is a full,
        # unencrypted image, so mode zero is both required and safe.
        flags = list(FPGA_MANAGERS.glob("fpga*/flags"))
        if len(flags) != 1:
            raise CoreError("expected exactly one Xilinx FPGA manager flags interface")
        flags[0].write_text("0\n")
        try:
            current = int(flags[0].read_text().strip(), 16)
        except ValueError as exc:
            raise CoreError("invalid FPGA manager flags value") from exc
        if current != 0:
            raise CoreError("FPGA manager refused to leave stale DMA-BUF mode")

    def apply(self, bundle):
        stage_assets(bundle)
        # The fixed kernel firmware slot is a symlink into /run. Programming
        # stages verified bytes in RAM, never into the ext4 Linux partition.
        atomic_write(STATE / "firmware/active.bit.bin", bundle.bitstream)
        OVERLAY.mkdir()
        # configfs binary attributes require a single complete write.
        with (OVERLAY / "dtbo").open("wb", buffering=0) as stream:
            if stream.write(bundle.overlay) != len(bundle.overlay):
                raise CoreError("short overlay write")
        if (OVERLAY / "status").read_text().strip() != "applied":
            raise CoreError("kernel did not apply the FPGA overlay")

    def bind_display(self):
        if not (Path("/sys/bus/platform/devices") / DP_DEVICE / "driver").exists():
            for name in ("zynqmp-dpsub", "zynqmp-display"):
                driver = Path("/sys/bus/platform/drivers") / name
                if driver.is_dir():
                    (driver / "bind").write_text(DP_DEVICE)
                    break
            else:
                raise CoreError("ZynqMP DisplayPort driver unavailable")
        run("udevadm", "settle", "--timeout=10")

    def ready(self):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            found = controllers()
            if len(found) == 1:
                uio = found[0]
                size = int((uio / "maps/map1/size").read_text(), 0)
                if size != MEMORY_SIZE:
                    raise CoreError("incorrect DMA window size")
                fd = os.open(Path("/dev") / uio.name, os.O_RDWR | os.O_CLOEXEC)
                try:
                    with mmap.mmap(fd, mmap.PAGESIZE, flags=mmap.MAP_SHARED,
                                   prot=mmap.PROT_READ) as registers:
                        magic, abi, status = struct.unpack_from("<III", registers)
                        if magic != 0x4B4D5354 or abi != ABI:
                            raise CoreError("loaded hardware identity/ABI mismatch")
                        if status & 4:
                            return
                finally:
                    os.close(fd)
            time.sleep(0.05)
        raise CoreError("loaded hardware did not become ready")

    def start_display(self):
        run("systemctl", "start", "kria-display.service")

    def record(self, bundle):
        atomic_write(STATE / "active.json", (json.dumps({
            "id": bundle.core_id, "manifest": str(bundle.path),
            "manifest_sha256": bundle.manifest_sha256}, sort_keys=True) + "\n").encode())


def replace(platform, bundle):
    platform.preflight()
    platform.stop_display()
    platform.drain()  # Any error here MUST prevent unbind/remove/reprogramming.
    platform.unbind_display()
    platform.remove()
    platform.reset_fpga_manager()
    platform.apply(bundle)
    platform.bind_display()
    platform.ready()
    platform.start_display()
    platform.record(bundle)


def load(bundle, recovery, platform=None):
    platform = platform or Platform()
    try:
        replace(platform, bundle)
    except (CoreError, OSError) as first:
        # Recovery repeats the drain gate. A stuck master never gets removed.
        if recovery is not None and bundle.path != recovery.path:
            try:
                replace(platform, recovery)
            except (CoreError, OSError) as second:
                raise CoreError(f"load failed: {first}; Menu recovery failed: {second}") from second
            raise CoreError(f"load failed: {first}; Menu restored; restart Main") from first
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("verify", "load"))
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    try:
        bundle = verify(args.manifest)
        if args.action == "verify":
            print(f"{bundle.core_id}: verified ABI {ABI:#x} and artifact hashes")
            return 0
        if os.geteuid() != 0:
            raise CoreError("loading requires root")
        # Validate recovery before touching the running application.
        recovery = verify(MENU)
        if recovery.core_id != "Menu":
            raise CoreError("recovery bundle is not Menu")
        STATE.mkdir(parents=True, exist_ok=True)
        with (STATE / "loader.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            load(bundle, recovery)
        return 0
    except (CoreError, OSError, ValueError) as exc:
        print(f"kria-core: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
