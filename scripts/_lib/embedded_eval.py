"""Shared embedded evaluation helpers for simulation and deployment."""

from __future__ import annotations

import os
import re
import shutil
import socket
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

from .harness_common import COMPILER_ROOT, REPO_ROOT, require


STDLIB_ADA_DIR = COMPILER_ROOT / "stdlib" / "ada"
ALR_FALLBACK = Path.home() / "bin" / "alr"
RENODE_ASSETS_ROOT = REPO_ROOT / "tools" / "embedded" / "renode"
OPENOCD_ASSETS_ROOT = REPO_ROOT / "tools" / "embedded" / "openocd"
DEFAULT_TIMEOUT_SECONDS = 30.0
MONITOR_CONNECT_TIMEOUT_SECONDS = 10.0
MONITOR_COMMAND_TIMEOUT_SECONDS = 5.0
MONITOR_POLL_INTERVAL_SECONDS = 0.1
STATUS_POLL_DELAY_SECONDS = 0.01
STATUS_PASS = 1
STATUS_FAIL = 2
ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


@dataclass(frozen=True)
class BoardConfig:
    name: str
    target: str
    runtime: str
    renode_platform: Path
    openocd_config: Path
    flash_base: int
    ram_base: int


@dataclass(frozen=True)
class SymbolInfo:
    name: str
    address: int
    size: int


SUPPORTED_BOARDS = {
    "stm32f4-discovery": BoardConfig(
        name="stm32f4-discovery",
        target="stm32f4",
        runtime="light-tasking-stm32f4",
        renode_platform=RENODE_ASSETS_ROOT / "stm32f4_discovery.repl",
        openocd_config=OPENOCD_ASSETS_ROOT / "stm32f4discovery-safe.cfg",
        flash_base=0x08000000,
        ram_base=0x20000000,
    ),
}


def find_command(name: str, fallback: Path | None = None) -> str:
    found = shutil.which(name)
    if found:
        return found
    if fallback is not None and fallback.exists():
        return str(fallback)
    raise FileNotFoundError(f"required command not found: {name}")


def first_message(completed: subprocess.CompletedProcess[str]) -> str:
    for stream in (completed.stderr, completed.stdout):
        for line in stream.splitlines():
            stripped = line.strip()
            if stripped:
                return stripped
    return f"exit code {completed.returncode}"


def run_capture(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        check=False,
        timeout=timeout,
    )


def run_logged(
    argv: list[str],
    *,
    cwd: Path,
    stdout_path: Path,
    stderr_path: Path,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    stderr_path.parent.mkdir(parents=True, exist_ok=True)
    with stdout_path.open("w", encoding="utf-8") as stdout_handle:
        with stderr_path.open("w", encoding="utf-8") as stderr_handle:
            return subprocess.run(
                argv,
                cwd=cwd,
                env=env,
                text=True,
                stdout=stdout_handle,
                stderr=stderr_handle,
                check=False,
            )


def build_compiler() -> Path:
    alr = find_command("alr", ALR_FALLBACK)
    completed = run_capture([alr, "build"], cwd=COMPILER_ROOT, env=os.environ.copy())
    if completed.returncode != 0:
        raise RuntimeError(first_message(completed))
    safec = COMPILER_ROOT / "bin" / "safec"
    require(safec.exists(), f"missing safec binary at {safec}")
    return safec


def detect_arm_triplet() -> tuple[str, str]:
    for triplet in ("arm-elf", "arm-eabi"):
        gnatls = shutil.which(f"{triplet}-gnatls")
        if gnatls:
            return triplet, gnatls
    raise FileNotFoundError(
        "required cross tool not found: arm-elf-gnatls or arm-eabi-gnatls"
    )


def find_readelf(triplet: str) -> str:
    for candidate in (f"{triplet}-readelf", "readelf"):
        found = shutil.which(candidate)
        if found:
            return found
    raise FileNotFoundError(
        f"required ELF inspection tool not found: {triplet}-readelf or readelf"
    )


def require_embedded_commands(
    *,
    triplet: str,
    need_renode: bool,
    need_openocd: bool,
    need_readelf: bool,
) -> dict[str, str]:
    commands = {
        "gprbuild": find_command("gprbuild"),
        "gnatls": find_command(f"{triplet}-gnatls"),
        "nm": find_command(f"{triplet}-nm"),
    }
    if need_renode:
        commands["renode"] = find_command("renode")
    if need_openocd:
        commands["openocd"] = find_command("openocd")
    if need_readelf:
        commands["readelf"] = find_readelf(triplet)
    return commands


def supported_boards() -> list[str]:
    return sorted(SUPPORTED_BOARDS)


def resolve_board(board_name: str, target_name: str | None = None) -> BoardConfig:
    board = SUPPORTED_BOARDS.get(board_name)
    if board is None:
        choices = ", ".join(supported_boards())
        raise ValueError(f"unsupported board {board_name!r}; supported boards: {choices}")
    if target_name is not None and target_name != board.target:
        raise ValueError(
            f"board {board_name!r} requires target {board.target!r}, got {target_name!r}"
        )
    return board


def ensure_board_assets(board: BoardConfig, *, need_renode: bool, need_openocd: bool) -> None:
    if need_renode:
        require(
            board.renode_platform.exists(),
            f"missing Renode platform asset {board.renode_platform}",
        )
    if need_openocd:
        require(
            board.openocd_config.exists(),
            f"missing OpenOCD config asset {board.openocd_config}",
        )


def verify_runtime_available(
    *,
    gnatls: str,
    triplet: str,
    runtime: str,
    env: dict[str, str],
) -> tuple[bool, str]:
    completed = run_capture([gnatls, f"--RTS={runtime}", "-v"], cwd=REPO_ROOT, env=env)
    if completed.returncode == 0:
        return True, ""
    return (
        False,
        f"required runtime {runtime!r} is not available for {triplet}: {first_message(completed)}",
    )


def deploy_root(source: Path, board_name: str) -> Path:
    return source.parent / "obj" / source.stem / "deploy" / board_name


def work_paths(root: Path) -> dict[str, Path]:
    return {
        "root": root,
        "out": root / "out",
        "iface": root / "iface",
        "ada": root / "ada",
        "obj": root / "obj",
        "logs": root / "logs",
        "status_spec": root / "safe_embedded_status.ads",
        "driver": root / "embedded_main.adb",
        "gpr": root / "build.gpr",
        "resc": root / "run.resc",
        "exe": root / "embedded_main",
        "emit_stdout": root / "logs" / "emit.stdout.log",
        "emit_stderr": root / "logs" / "emit.stderr.log",
        "build_stdout": root / "logs" / "build.stdout.log",
        "build_stderr": root / "logs" / "build.stderr.log",
        "renode_stdout": root / "logs" / "renode.stdout.log",
        "renode_stderr": root / "logs" / "renode.stderr.log",
        "openocd_stdout": root / "logs" / "openocd.stdout.log",
        "openocd_stderr": root / "logs" / "openocd.stderr.log",
        "openocd_session": root / "logs" / "openocd.session.log",
    }


def reset_root(root: Path) -> None:
    shutil.rmtree(root, ignore_errors=True)


def ensure_work_dirs(paths: dict[str, Path]) -> None:
    paths["out"].mkdir(parents=True, exist_ok=True)
    paths["iface"].mkdir(parents=True, exist_ok=True)
    paths["ada"].mkdir(parents=True, exist_ok=True)
    paths["obj"].mkdir(parents=True, exist_ok=True)
    paths["logs"].mkdir(parents=True, exist_ok=True)


def temporary_root(label: str) -> Path:
    return Path(tempfile.mkdtemp(prefix=f"safe-embedded-{label}-"))


def emit_source(
    *,
    safec: Path,
    source: Path,
    paths: dict[str, Path],
    env: dict[str, str],
) -> tuple[bool, str]:
    completed = run_logged(
        [
            str(safec),
            "emit",
            str(source),
            "--out-dir",
            str(paths["out"]),
            "--interface-dir",
            str(paths["iface"]),
            "--ada-out-dir",
            str(paths["ada"]),
        ],
        cwd=REPO_ROOT,
        stdout_path=paths["emit_stdout"],
        stderr_path=paths["emit_stderr"],
        env=env,
    )
    if completed.returncode == 0:
        return True, ""
    stderr = paths["emit_stderr"].read_text(encoding="utf-8").strip()
    stdout = paths["emit_stdout"].read_text(encoding="utf-8").strip()
    return False, f"emit failed: {stderr or stdout or f'exit code {completed.returncode}'}"


def status_spec_text() -> str:
    return (
        "with Interfaces;\n"
        "\n"
        "package Safe_Embedded_Status is\n"
        "   Value : Interfaces.Unsigned_32 := 0\n"
        "     with Export,\n"
        "          Convention => C,\n"
        "          External_Name => \"safe_embedded_status\",\n"
        "          Volatile;\n"
        "end Safe_Embedded_Status;\n"
    )


def startup_driver_text(unit_name: str) -> str:
    return (
        "with Interfaces;\n"
        "with Safe_Embedded_Status;\n"
        f"with {unit_name};\n"
        "\n"
        "procedure Embedded_Main is\n"
        "begin\n"
        f"   Safe_Embedded_Status.Value := {STATUS_PASS};\n"
        "   loop\n"
        f"      delay {STATUS_POLL_DELAY_SECONDS:.2f};\n"
        "   end loop;\n"
        "end Embedded_Main;\n"
    )


def result_driver_text(unit_name: str, expected_result: int) -> str:
    return (
        "with Interfaces;\n"
        "with Safe_Embedded_Status;\n"
        f"with {unit_name};\n"
        "\n"
        "procedure Embedded_Main is\n"
        f"   Expected_Result : constant Long_Long_Integer := {expected_result};\n"
        f"   Pass_Status : constant Interfaces.Unsigned_32 := {STATUS_PASS};\n"
        f"   Fail_Status : constant Interfaces.Unsigned_32 := {STATUS_FAIL};\n"
        "begin\n"
        "   loop\n"
        "      declare\n"
        f"         Current : constant Long_Long_Integer := Long_Long_Integer ({unit_name}.result);\n"
        "      begin\n"
        "         if Current = Expected_Result then\n"
        "            Safe_Embedded_Status.Value := Pass_Status;\n"
        "         elsif Current > Expected_Result then\n"
        "            Safe_Embedded_Status.Value := Fail_Status;\n"
        "         end if;\n"
        "      end;\n"
        f"      delay {STATUS_POLL_DELAY_SECONDS:.2f};\n"
        "   end loop;\n"
        "end Embedded_Main;\n"
    )


def result_channel_driver_text(unit_name: str, expected_result: int) -> str:
    return (
        "with Interfaces;\n"
        "with Safe_Embedded_Status;\n"
        f"with {unit_name};\n"
        "\n"
        "procedure Embedded_Main is\n"
        f"   Expected_Result : constant Long_Long_Integer := {expected_result};\n"
        f"   Pass_Status : constant Interfaces.Unsigned_32 := {STATUS_PASS};\n"
        f"   Fail_Status : constant Interfaces.Unsigned_32 := {STATUS_FAIL};\n"
        f"   Current : {unit_name}.Result_Value := {unit_name}.Result_Value'First;\n"
        "   Success : Boolean := False;\n"
        "begin\n"
        "   loop\n"
        f"      {unit_name}.Result_Ch.Try_Receive (Current, Success);\n"
        "      if Success then\n"
        "         if Long_Long_Integer (Current) = Expected_Result then\n"
        "            Safe_Embedded_Status.Value := Pass_Status;\n"
        "         elsif Long_Long_Integer (Current) > Expected_Result then\n"
        "            Safe_Embedded_Status.Value := Fail_Status;\n"
        "         end if;\n"
        "      end if;\n"
        f"      delay {STATUS_POLL_DELAY_SECONDS:.2f};\n"
        "   end loop;\n"
        "end Embedded_Main;\n"
    )


def project_text(*, has_gnat_adc: bool, gnat_adc_path: Path) -> str:
    ada_switches = '("-gnatws")'
    if has_gnat_adc:
        ada_switches = ada_switches + f' & ("-gnatec={gnat_adc_path.as_posix()}")'
    return "\n".join(
        [
            "project Build is",
            f'   for Source_Dirs use (".", "ada", "{STDLIB_ADA_DIR}");',
            '   for Object_Dir use "obj";',
            '   for Exec_Dir use ".";',
            '   for Main use ("embedded_main.adb");',
            "   package Compiler is",
            f'      for Default_Switches ("Ada") use {ada_switches};',
            "   end Compiler;",
            "end Build;",
            "",
        ]
    )


def wrapper_resc_text(*, machine_name: str, platform_path: Path, elf_path: Path) -> str:
    return (
        "using sysbus\n"
        f"mach create \"{machine_name}\"\n"
        f"machine LoadPlatformDescription @{platform_path}\n"
        f"sysbus LoadELF @{elf_path}\n"
        "mach set 0\n"
        "start\n"
    )


def write_support_files(
    *,
    paths: dict[str, Path],
    driver_source: str,
    board: BoardConfig | None = None,
) -> None:
    paths["status_spec"].write_text(status_spec_text(), encoding="utf-8")
    paths["driver"].write_text(driver_source, encoding="utf-8")
    paths["gpr"].write_text(
        project_text(
            has_gnat_adc=(paths["ada"] / "gnat.adc").exists(),
            gnat_adc_path=paths["ada"] / "gnat.adc",
        ),
        encoding="utf-8",
    )
    if board is not None:
        paths["resc"].write_text(
            wrapper_resc_text(
                machine_name=f"safe_{board.target}",
                platform_path=board.renode_platform,
                elf_path=paths["exe"],
            ),
            encoding="utf-8",
        )


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as handle:
        handle.bind(("127.0.0.1", 0))
        return int(handle.getsockname()[1])


class TextSocketMonitor:
    def __init__(self, sock: socket.socket):
        self.sock = sock

    @classmethod
    def connect(cls, *, port: int, timeout: float) -> "TextSocketMonitor":
        deadline = time.monotonic() + timeout
        last_error: OSError | None = None
        while time.monotonic() < deadline:
            try:
                sock = socket.create_connection(("127.0.0.1", port), timeout=0.5)
                sock.settimeout(0.5)
                monitor = cls(sock)
                monitor._read_until_idle(timeout=0.5)
                return monitor
            except OSError as exc:
                last_error = exc
                time.sleep(0.1)
        raise RuntimeError(f"monitor not ready on port {port}: {last_error}")

    def close(self) -> None:
        self.sock.close()

    def _read_until_idle(self, *, timeout: float) -> str:
        deadline = time.monotonic() + timeout
        chunks = bytearray()
        while time.monotonic() < deadline:
            try:
                chunk = self.sock.recv(4096)
            except socket.timeout:
                if chunks:
                    return chunks.decode("utf-8", errors="replace")
                continue
            if not chunk:
                break
            chunks.extend(chunk)
            idle_deadline = time.monotonic() + 0.2
            while time.monotonic() < idle_deadline:
                try:
                    chunk = self.sock.recv(4096)
                except socket.timeout:
                    break
                if not chunk:
                    return chunks.decode("utf-8", errors="replace")
                chunks.extend(chunk)
                idle_deadline = time.monotonic() + 0.2
            return chunks.decode("utf-8", errors="replace")
        if chunks:
            return chunks.decode("utf-8", errors="replace")
        raise RuntimeError("timed out waiting for monitor response")

    def command(self, text: str, *, timeout: float = MONITOR_COMMAND_TIMEOUT_SECONDS) -> str:
        self.sock.sendall((text + "\n").encode("utf-8"))
        return self._read_until_idle(timeout=timeout)


def parse_monitor_value(text: str) -> int:
    cleaned = ANSI_ESCAPE_RE.sub("", text).replace("\r", "")
    for line in cleaned.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if ":" in stripped:
            _, _, tail = stripped.partition(":")
            value_match = re.search(
                r"\b(?:0x[0-9a-fA-F]+|[0-9a-fA-F]{2,16}|\d+)\b", tail.strip()
            )
            if value_match:
                token = value_match.group(0)
                if token.lower().startswith("0x"):
                    return int(token, 16)
                if any(ch in "abcdefABCDEF" for ch in token):
                    return int(token, 16)
                if len(token) > 1 and token.startswith("0"):
                    return int(token, 16)
                return int(token, 10)
    hex_matches = re.findall(r"0x[0-9a-fA-F]+", cleaned)
    if hex_matches:
        return int(hex_matches[-1], 16)
    int_matches = re.findall(r"\b\d+\b", cleaned)
    if not int_matches:
        raise RuntimeError(f"unable to parse numeric monitor response: {cleaned.strip()!r}")
    return int(int_matches[-1], 10)


def renode_command(renode: str, *, port: int, script_path: Path) -> list[str]:
    return [
        renode,
        "--disable-gui",
        "-P",
        str(port),
        "-e",
        f"i @{script_path}",
    ]


def openocd_command(openocd: str, *, port: int, config_path: Path) -> list[str]:
    return [
        openocd,
        "-f",
        str(config_path),
        "-c",
        f"telnet_port {port}",
        "-c",
        "gdb_port disabled",
        "-c",
        "tcl_port disabled",
    ]


def stop_process(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def build_embedded_image(
    *,
    gprbuild: str,
    triplet: str,
    runtime: str,
    paths: dict[str, Path],
    env: dict[str, str],
) -> tuple[bool, str]:
    completed = run_logged(
        [
            gprbuild,
            f"--target={triplet}",
            f"--RTS={runtime}",
            "-P",
            str(paths["gpr"]),
            "-cargs:Ada",
            "-gnatws",
        ],
        cwd=paths["root"],
        stdout_path=paths["build_stdout"],
        stderr_path=paths["build_stderr"],
        env=env,
    )
    if completed.returncode != 0:
        stderr = paths["build_stderr"].read_text(encoding="utf-8").strip()
        stdout = paths["build_stdout"].read_text(encoding="utf-8").strip()
        return False, f"build failed: {stderr or stdout or f'exit code {completed.returncode}'}"
    if not paths["exe"].exists():
        return False, f"build failed: missing executable {paths['exe']}"
    return True, ""


def resolve_symbol_address(
    *,
    nm: str,
    exe_path: Path,
    symbol_name: str,
    env: dict[str, str],
) -> int:
    completed = run_capture([nm, str(exe_path)], cwd=exe_path.parent, env=env)
    if completed.returncode != 0:
        raise RuntimeError(first_message(completed))
    for line in completed.stdout.splitlines():
        parts = line.strip().split()
        if len(parts) >= 3 and parts[-1] == symbol_name:
            return int(parts[0], 16)
    raise RuntimeError(f"unable to resolve {symbol_name} in {exe_path}")


def resolve_symbol_info(
    *,
    readelf: str,
    exe_path: Path,
    symbol_name: str,
    env: dict[str, str],
) -> SymbolInfo:
    completed = run_capture([readelf, "-sW", str(exe_path)], cwd=exe_path.parent, env=env)
    if completed.returncode != 0:
        raise RuntimeError(first_message(completed))
    for line in completed.stdout.splitlines():
        parts = line.split()
        if len(parts) < 8 or parts[-1] != symbol_name:
            continue
        try:
            address = int(parts[1], 16)
            size = int(parts[2], 10)
        except ValueError as exc:
            raise RuntimeError(f"unable to parse symbol metadata for {symbol_name}") from exc
        if size not in {1, 2, 4, 8}:
            raise RuntimeError(
                f"symbol {symbol_name!r} has unsupported size {size}; supported sizes are 1, 2, 4, or 8 bytes"
            )
        return SymbolInfo(name=symbol_name, address=address, size=size)
    raise RuntimeError(f"unable to resolve symbol metadata for {symbol_name} in {exe_path}")


def read_scalar_value(
    monitor: TextSocketMonitor,
    *,
    address: int,
    size: int,
) -> int:
    if size == 1:
        return parse_monitor_value(monitor.command(f"sysbus ReadByte {hex(address)}"))
    if size == 2:
        return parse_monitor_value(monitor.command(f"sysbus ReadWord {hex(address)}"))
    if size == 4:
        return parse_monitor_value(monitor.command(f"sysbus ReadDoubleWord {hex(address)}"))
    if size == 8:
        low = parse_monitor_value(monitor.command(f"sysbus ReadDoubleWord {hex(address)}"))
        high = parse_monitor_value(monitor.command(f"sysbus ReadDoubleWord {hex(address + 4)}"))
        return low | (high << 32)
    raise RuntimeError(f"unsupported scalar size {size}")


def signed_value(raw_value: int, *, size: int) -> int:
    bit_count = size * 8
    sign_bit = 1 << (bit_count - 1)
    full_mask = (1 << bit_count) - 1
    masked = raw_value & full_mask
    if masked & sign_bit:
        return masked - (1 << bit_count)
    return masked


def value_matches_expected(raw_value: int, *, size: int, expected_value: int) -> bool:
    if expected_value < 0:
        return signed_value(raw_value, size=size) == expected_value
    return raw_value == expected_value


def format_observed_value(raw_value: int, *, size: int) -> str:
    return f"raw={raw_value} signed={signed_value(raw_value, size=size)}"


def run_under_renode(
    *,
    renode: str,
    nm: str,
    paths: dict[str, Path],
    timeout_seconds: float,
    env: dict[str, str],
    symbol_name: str = "safe_embedded_status",
) -> tuple[bool, str]:
    port = find_free_port()
    with paths["renode_stdout"].open("w", encoding="utf-8") as stdout_handle:
        with paths["renode_stderr"].open("w", encoding="utf-8") as stderr_handle:
            process = subprocess.Popen(
                renode_command(renode, port=port, script_path=paths["resc"]),
                cwd=paths["root"],
                env=env,
                stdout=stdout_handle,
                stderr=stderr_handle,
                text=True,
            )
    try:
        bootstrap = TextSocketMonitor.connect(port=port, timeout=MONITOR_CONNECT_TIMEOUT_SECONDS)
        bootstrap.close()
        address = resolve_symbol_address(
            nm=nm, exe_path=paths["exe"], symbol_name=symbol_name, env=env
        )
        deadline = time.monotonic() + timeout_seconds
        while time.monotonic() < deadline:
            monitor = TextSocketMonitor.connect(
                port=port, timeout=MONITOR_CONNECT_TIMEOUT_SECONDS
            )
            try:
                output = monitor.command(f"sysbus ReadDoubleWord {hex(address)}")
            finally:
                monitor.close()
            status = parse_monitor_value(output)
            if status == STATUS_PASS:
                return True, ""
            if status == STATUS_FAIL:
                return False, "simulation reported failure status"
            time.sleep(MONITOR_POLL_INTERVAL_SECONDS)
        return False, f"timed out after {timeout_seconds:g}s"
    finally:
        stop_process(process)


def run_under_renode_observe(
    *,
    renode: str,
    nm: str,
    readelf: str,
    paths: dict[str, Path],
    timeout_seconds: float,
    env: dict[str, str],
    watch_symbol: str,
    expect_value: int,
    startup_symbol: str = "safe_embedded_status",
) -> tuple[bool, str]:
    port = find_free_port()
    raw_value: int | None = None
    with paths["renode_stdout"].open("w", encoding="utf-8") as stdout_handle:
        with paths["renode_stderr"].open("w", encoding="utf-8") as stderr_handle:
            process = subprocess.Popen(
                renode_command(renode, port=port, script_path=paths["resc"]),
                cwd=paths["root"],
                env=env,
                stdout=stdout_handle,
                stderr=stderr_handle,
                text=True,
            )
    try:
        bootstrap = TextSocketMonitor.connect(port=port, timeout=MONITOR_CONNECT_TIMEOUT_SECONDS)
        bootstrap.close()
        startup_address = resolve_symbol_address(
            nm=nm, exe_path=paths["exe"], symbol_name=startup_symbol, env=env
        )
        watched = resolve_symbol_info(
            readelf=readelf, exe_path=paths["exe"], symbol_name=watch_symbol, env=env
        )
        deadline = time.monotonic() + timeout_seconds
        while time.monotonic() < deadline:
            monitor = TextSocketMonitor.connect(
                port=port, timeout=MONITOR_CONNECT_TIMEOUT_SECONDS
            )
            try:
                startup_output = monitor.command(f"sysbus ReadDoubleWord {hex(startup_address)}")
                startup = parse_monitor_value(startup_output)
                if startup == STATUS_FAIL:
                    return False, "simulation reported failure status"
                if startup == STATUS_PASS:
                    raw_value = read_scalar_value(
                        monitor,
                        address=watched.address,
                        size=watched.size,
                    )
                    if value_matches_expected(
                        raw_value,
                        size=watched.size,
                        expected_value=expect_value,
                    ):
                        return True, ""
                else:
                    raw_value = None
            finally:
                monitor.close()
            time.sleep(MONITOR_POLL_INTERVAL_SECONDS)
        detail = f"timed out after {timeout_seconds:g}s while waiting for {watch_symbol}={expect_value}"
        if raw_value is not None:
            detail = (
                f"{detail}; last observed {format_observed_value(raw_value, size=watched.size)}"
            )
        return False, detail
    finally:
        stop_process(process)


def validate_elf_layout(
    *,
    readelf: str,
    exe_path: Path,
    board: BoardConfig,
    env: dict[str, str],
) -> tuple[bool, str]:
    completed = run_capture([readelf, "-lW", str(exe_path)], cwd=exe_path.parent, env=env)
    if completed.returncode != 0:
        return False, f"ELF inspection failed: {first_message(completed)}"
    flash_ok = False
    ram_ok = False
    for line in completed.stdout.splitlines():
        stripped = line.strip()
        if not stripped.startswith("LOAD"):
            continue
        parts = stripped.split()
        hex_parts = [part for part in parts if part.startswith("0x")]
        if len(hex_parts) < 2:
            continue
        vaddr = int(hex_parts[1], 16)
        if board.flash_base <= vaddr < board.flash_base + 0x1000000:
            flash_ok = True
        if board.ram_base <= vaddr < board.ram_base + 0x1000000:
            ram_ok = True
    if not flash_ok or not ram_ok:
        return (
            False,
            f"ELF layout does not match {board.name}: flash@0x{board.flash_base:08x}={flash_ok}, "
            f"ram@0x{board.ram_base:08x}={ram_ok}",
        )
    return True, ""


def command_error_text(text: str) -> str | None:
    cleaned = ANSI_ESCAPE_RE.sub("", text).replace("\r", "")
    for line in cleaned.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        lowered = stripped.lower()
        if "error" in lowered or "failed" in lowered or "target not halted" in lowered:
            return stripped
    return None


def run_under_openocd(
    *,
    openocd: str,
    nm: str,
    readelf: str,
    paths: dict[str, Path],
    board: BoardConfig,
    timeout_seconds: float,
    env: dict[str, str],
    symbol_name: str = "safe_embedded_status",
) -> tuple[bool, str]:
    ok, detail = validate_elf_layout(readelf=readelf, exe_path=paths["exe"], board=board, env=env)
    if not ok:
        return False, detail

    port = find_free_port()
    with paths["openocd_stdout"].open("w", encoding="utf-8") as stdout_handle:
        with paths["openocd_stderr"].open("w", encoding="utf-8") as stderr_handle:
            process = subprocess.Popen(
                openocd_command(openocd, port=port, config_path=board.openocd_config),
                cwd=paths["root"],
                env=env,
                stdout=stdout_handle,
                stderr=stderr_handle,
                text=True,
            )
    try:
        monitor = TextSocketMonitor.connect(port=port, timeout=MONITOR_CONNECT_TIMEOUT_SECONDS)
        address = resolve_symbol_address(
            nm=nm, exe_path=paths["exe"], symbol_name=symbol_name, env=env
        )
        with paths["openocd_session"].open("w", encoding="utf-8") as session_log:
            def send(command: str, *, timeout: float = MONITOR_COMMAND_TIMEOUT_SECONDS) -> str:
                response = monitor.command(command, timeout=timeout)
                session_log.write(f"$ {command}\n{response}\n")
                session_log.flush()
                return response

            try:
                error = command_error_text(send("init", timeout=20))
                if error is not None:
                    return False, f"OpenOCD init failed: {error}"
                flash_response = send(
                    f"program {paths['exe']} verify reset", timeout=max(60.0, timeout_seconds)
                )
                error = command_error_text(flash_response)
                if error is not None:
                    return False, f"OpenOCD flash failed: {error}"
                error = command_error_text(send("reset run", timeout=10))
                if error is not None:
                    return False, f"OpenOCD reset failed: {error}"
                error = command_error_text(send("targets sram_monitor", timeout=10))
                if error is not None:
                    return False, f"OpenOCD target switch failed: {error}"

                deadline = time.monotonic() + timeout_seconds
                while time.monotonic() < deadline:
                    response = send(f"mdw {hex(address)}", timeout=10)
                    error = command_error_text(response)
                    if error is not None:
                        return False, f"OpenOCD memory read failed: {error}"
                    status = parse_monitor_value(response)
                    if status == STATUS_PASS:
                        return True, ""
                    if status == STATUS_FAIL:
                        return False, "hardware reported failure status"
                    time.sleep(MONITOR_POLL_INTERVAL_SECONDS)
                return False, f"timed out after {timeout_seconds:g}s"
            finally:
                monitor.close()
    finally:
        stop_process(process)


__all__ = [
    "ALR_FALLBACK",
    "ANSI_ESCAPE_RE",
    "BoardConfig",
    "COMPILER_ROOT",
    "DEFAULT_TIMEOUT_SECONDS",
    "MONITOR_COMMAND_TIMEOUT_SECONDS",
    "MONITOR_CONNECT_TIMEOUT_SECONDS",
    "MONITOR_POLL_INTERVAL_SECONDS",
    "OPENOCD_ASSETS_ROOT",
    "RENODE_ASSETS_ROOT",
    "REPO_ROOT",
    "STATUS_FAIL",
    "STATUS_PASS",
    "STATUS_POLL_DELAY_SECONDS",
    "SUPPORTED_BOARDS",
    "TextSocketMonitor",
    "build_compiler",
    "build_embedded_image",
    "command_error_text",
    "deploy_root",
    "detect_arm_triplet",
    "emit_source",
    "ensure_board_assets",
    "ensure_work_dirs",
    "find_command",
    "find_free_port",
    "find_readelf",
    "first_message",
    "parse_monitor_value",
    "project_text",
    "renode_command",
    "require_embedded_commands",
    "resolve_board",
    "resolve_symbol_info",
    "resolve_symbol_address",
    "run_under_renode_observe",
    "result_channel_driver_text",
    "result_driver_text",
    "reset_root",
    "run_capture",
    "run_logged",
    "run_under_openocd",
    "run_under_renode",
    "signed_value",
    "startup_driver_text",
    "status_spec_text",
    "supported_boards",
    "temporary_root",
    "validate_elf_layout",
    "value_matches_expected",
    "verify_runtime_available",
    "work_paths",
    "write_support_files",
]
