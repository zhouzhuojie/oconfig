#!/usr/bin/env python3
"""Unit tests for oconfig, modeled on omarchy-config-sync's isolated git fixtures."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "bin" / "oconfig"


def git_test_env() -> dict[str, str]:
    env = os.environ.copy()
    env["GIT_AUTHOR_NAME"] = "Test"
    env["GIT_AUTHOR_EMAIL"] = "test@example.com"
    env["GIT_COMMITTER_NAME"] = "Test"
    env["GIT_COMMITTER_EMAIL"] = "test@example.com"
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_TERMINAL_PROMPT"] = "0"
    return env


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=check,
        env=git_test_env(),
    )


class Fixture:
    def __init__(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.home = self.root / "home"
        self.omarchy = self.root / "omarchy"
        self.home.mkdir()
        (self.home / ".config" / "hypr").mkdir(parents=True)
        (self.home / ".config" / "omarchy").mkdir(parents=True)
        (self.home / ".config" / "chromium" / "Default").mkdir(parents=True)
        pkg = self.omarchy / "config"
        (pkg / "hypr").mkdir(parents=True)
        (pkg / "omarchy").mkdir(parents=True)
        (pkg / "chromium" / "Default").mkdir(parents=True)
        (pkg / "hypr" / "bindings.lua").write_text("stock bindings\n")
        (pkg / "hypr" / "hyprland.lua").write_text("stock hyprland\n")
        (pkg / "hypr" / "monitors.lua").write_text("stock monitors\n")
        (pkg / "omarchy" / "shell.json").write_text('{"bar":{}}\n')
        (pkg / "chromium" / "Default" / "Preferences").write_text("{}\n")
        shutil.copy(pkg / "hypr" / "bindings.lua", self.home / ".config" / "hypr" / "bindings.lua")
        shutil.copy(pkg / "hypr" / "hyprland.lua", self.home / ".config" / "hypr" / "hyprland.lua")
        shutil.copy(pkg / "hypr" / "monitors.lua", self.home / ".config" / "hypr" / "monitors.lua")
        (self.home / ".config" / "hypr" / "bindings.lua").write_text("my bindings\n")
        (self.home / ".config" / "hypr" / "monitors.lua").write_text("hdmi layout\n")
        (self.home / ".config" / "omarchy" / "shell.json").write_text('{"version":1}\n')
        (self.home / ".config" / "chromium" / "Default" / "Preferences").write_text("cookies\n")

    def close(self) -> None:
        self._tmp.cleanup()

    def __enter__(self) -> "Fixture":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def env(self) -> dict[str, str]:
        env = git_test_env()
        env["HOME"] = str(self.home)
        env["XDG_CONFIG_HOME"] = str(self.home / ".config")
        env["XDG_STATE_HOME"] = str(self.home / ".local" / "state")
        env["XDG_DATA_HOME"] = str(self.home / ".local" / "share")
        env["OMARCHY_PATH"] = str(self.omarchy)
        env["PATH"] = os.environ.get("PATH", "/usr/bin")
        return env

    def run(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(CLI), *args],
            capture_output=True,
            text=True,
            check=check,
            env=self.env(),
        )

    def store(self) -> Path:
        cfg = json.loads((self.home / ".config" / "oconfig" / "config.json").read_text())
        return Path(cfg["repo"])


class CheckSaveRestoreTests(unittest.TestCase):
    def test_check_save_restore_skips_hardware_and_chromium(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            status = json.loads(fx.run("--json", "status").stdout)
            self.assertTrue(status["initialized"])

            check = fx.run("check").stdout
            self.assertIn(".config/hypr/bindings.lua", check)
            self.assertIn(".config/omarchy/shell.json", check)
            self.assertNotIn("monitors.lua", check)
            self.assertNotIn("chromium", check)

            fx.run("save")
            self.assertIn("no untracked", fx.run("check").stdout)
            store = fx.store()
            self.assertEqual((store / ".config" / "hypr" / "bindings.lua").read_text(), "my bindings\n")
            self.assertFalse((store / ".config" / "hypr" / "monitors.lua").exists())

            live = fx.home / ".config" / "hypr" / "bindings.lua"
            live.write_text("stock bindings\n")
            fx.run("restore")
            self.assertEqual(live.read_text(), "my bindings\n")
            self.assertFalse(live.is_symlink())

    def test_restore_replaces_symlink_without_following_it(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            fx.run("save")
            live = fx.home / ".config" / "hypr" / "bindings.lua"
            canary = fx.home / "outside.txt"
            canary.write_text("precious\n")
            live.unlink()
            live.symlink_to(canary)
            fx.run("restore")
            self.assertFalse(live.is_symlink())
            self.assertEqual(live.read_text(), "my bindings\n")
            self.assertEqual(canary.read_text(), "precious\n")

    def test_adopt_rejects_non_config_paths(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            proc = fx.run("adopt", ".gitconfig", check=False)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn(".config/", proc.stderr)

    def test_ignore_add(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            fx.run("ignore", "add", ".config/hypr/bindings.lua")
            check = fx.run("check").stdout
            self.assertNotIn("bindings.lua", check)


class RemoteTests(unittest.TestCase):
    def test_push_pull_via_bare_origin(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            fx.run("save")
            bare = fx.root / "origin.git"
            subprocess.run(
                ["git", "init", "--bare", "-b", "main", str(bare)],
                check=True,
                capture_output=True,
                env=git_test_env(),
            )
            set_out = fx.run("remote", str(bare))
            self.assertIn("origin", set_out.stdout)
            fx.run("push")
            heads = subprocess.run(
                ["git", "--git-dir", str(bare), "rev-parse", "HEAD"],
                capture_output=True,
                text=True,
                check=True,
                env=git_test_env(),
            )
            self.assertTrue(heads.stdout.strip())

            other = Fixture()
            try:
                other.run("init", "--repo", str(other.home / "store"), "--remote", str(bare))
                other.run("pull")
                bindings = other.store() / ".config" / "hypr" / "bindings.lua"
                self.assertTrue(bindings.is_file(), "pulled store should contain saved bindings")
                self.assertEqual(bindings.read_text(), "my bindings\n")
                other.run("restore")
                self.assertEqual(
                    (other.home / ".config" / "hypr" / "bindings.lua").read_text(),
                    "my bindings\n",
                )
            finally:
                other.close()

    def test_save_push_roundtrip(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            bare = fx.root / "origin.git"
            subprocess.run(
                ["git", "init", "--bare", "-b", "main", str(bare)],
                check=True,
                capture_output=True,
                env=git_test_env(),
            )
            fx.run("remote", str(bare))
            fx.run("save", "--push")
            clone = fx.root / "clone"
            subprocess.run(
                ["git", "clone", str(bare), str(clone)],
                check=True,
                capture_output=True,
                env=git_test_env(),
            )
            self.assertEqual(
                (clone / ".config" / "hypr" / "bindings.lua").read_text(),
                "my bindings\n",
            )

    def test_remote_rejects_flag_injection(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            proc = fx.run("remote", "--upload-pack=evil", check=False)
            self.assertNotEqual(proc.returncode, 0)

    def test_push_without_remote_fails(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            proc = fx.run("push", check=False)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("no remote", proc.stderr)

    def test_status_json_includes_remote(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            data = json.loads(fx.run("--json", "status").stdout)
            self.assertEqual(data["remote"], "")
            fx.run("remote", "/tmp/example.git")
            data = json.loads(fx.run("--json", "status").stdout)
            self.assertTrue(data["remote"].endswith("example.git"))


class ModelJsTests(unittest.TestCase):
    def test_parse_status_and_summary(self) -> None:
        node = shutil.which("node")
        if not node:
            self.skipTest("node not available")
        model = json.dumps(str(ROOT / "Model.js"))
        script = f"""
const fs = require('fs');
const vm = require('vm');
const code = fs.readFileSync({model}, 'utf8');
const ctx = {{}};
vm.createContext(ctx);
vm.runInContext(code, ctx);
const empty = ctx.parseStatus('not-json');
if (empty.initialized) throw new Error('bad empty');
const s = ctx.parseStatus(JSON.stringify({{
  initialized: true, repo: '/tmp/store', remote: 'git@ex:repo.git',
  untracked: 2, untrackedPaths: ['a'], ahead: 1, behind: 0, lastCommit: 'abc'
}}));
if (!s.initialized || s.untracked !== 2 || s.remote.indexOf('ex') < 0) throw new Error('parse');
if (ctx.summaryLine(s) !== '2 unsaved') throw new Error('summary ' + ctx.summaryLine(s));
const synced = ctx.parseStatus(JSON.stringify({{initialized: true, remote: 'x', untracked: 0, ahead: 0, behind: 0}}));
if (ctx.summaryLine(synced) !== 'Synced') throw new Error(ctx.summaryLine(synced));
console.log('ok');
"""
        proc = subprocess.run(
            [node, "-e", script],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("ok", proc.stdout)


class SafeWriteTests(unittest.TestCase):
    def test_init_refuses_symlink_config_json(self) -> None:
        with Fixture() as fx:
            cfg_dir = fx.home / ".config" / "oconfig"
            cfg_dir.mkdir(parents=True)
            canary = fx.root / "outside.txt"
            canary.write_text("precious\n")
            (cfg_dir / "config.json").symlink_to(canary)
            proc = fx.run("init", check=False)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("not a regular file", proc.stderr)
            self.assertEqual(canary.read_text(), "precious\n")
            self.assertTrue((cfg_dir / "config.json").is_symlink())

    def test_remote_refuses_symlink_config_json(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            cfg = fx.home / ".config" / "oconfig" / "config.json"
            canary = fx.root / "outside.txt"
            canary.write_text("precious\n")
            cfg.unlink()
            cfg.symlink_to(canary)
            proc = fx.run("remote", str(fx.root / "origin.git"), check=False)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("not a regular file", proc.stderr)
            self.assertEqual(canary.read_text(), "precious\n")

    def test_ignore_add_refuses_symlink(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            ignore = fx.home / ".config" / "oconfig" / "ignore.txt"
            canary = fx.root / "outside.txt"
            canary.write_text("precious\n")
            ignore.unlink()
            ignore.symlink_to(canary)
            proc = fx.run("ignore", "add", ".config/hypr/bindings.lua", check=False)
            self.assertNotEqual(proc.returncode, 0)
            self.assertEqual(canary.read_text(), "precious\n")

    def test_init_writes_regular_owned_config(self) -> None:
        with Fixture() as fx:
            fx.run("init")
            cfg = fx.home / ".config" / "oconfig" / "config.json"
            self.assertTrue(cfg.is_file())
            self.assertFalse(cfg.is_symlink())
            self.assertEqual(cfg.stat().st_uid, os.getuid())
            self.assertEqual(cfg.stat().st_mode & 0o777, 0o600)

    def test_readme_has_no_privilege_words(self) -> None:
        text = (ROOT / "README.md").read_text().lower()
        for word in ("sudo", "pkexec", "doas"):
            self.assertNotIn(word, text)


class ManifestTests(unittest.TestCase):
    def test_manifest_has_remote_schema(self) -> None:
        data = json.loads((ROOT / "manifest.json").read_text())
        self.assertEqual(data["schemaVersion"], 1)
        self.assertFalse(data["id"].startswith("omarchy."))
        keys = [s["key"] for s in data["barWidget"]["schema"]]
        self.assertIn("remote", keys)


if __name__ == "__main__":
    unittest.main()
