#!/usr/bin/env python3
"""Exercise the evaluated Home Manager skill installation plan."""

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def nix(*args):
    return subprocess.check_output(["nix", *args], cwd=ROOT, text=True)


flake = json.loads(nix("flake", "metadata", "--json", "--no-write-lock-file", "."))
pin = flake["locks"]["nodes"]["matt-pocock-skills"]
assert pin["original"]["ref"] == "v1.3.1", pin

upstream = Path(
    nix(
        "eval",
        "--raw",
        "--impure",
        "--expr",
        "(builtins.getFlake (toString ./.)).inputs.matt-pocock-skills.outPath",
    )
)
files = json.loads(
    nix(
        "eval",
        "--json",
        ".#darwinConfigurations.mac.config.home-manager.users.moiesk.home.file",
        "--apply",
        "files: builtins.mapAttrs (_: value: toString value.source) "
        '(builtins.filterAttrs (name: _: builtins.match "[.](agents/skills|claude/skills|pi/agent/skills)/.*" name != null) files)',
    )
)

groups = ("engineering", "productivity", "misc")
expected = {
    path.name: path
    for group in groups
    for path in (upstream / "skills" / group).iterdir()
    if path.is_dir() and (path / "SKILL.md").is_file()
}
canonical = {
    name.removeprefix(".agents/skills/"): Path(source)
    for name, source in files.items()
    if name.startswith(".agents/skills/") and source.startswith(f"{upstream}/skills/")
}
assert canonical == expected, {"missing": sorted(expected.keys() - canonical.keys()), "extra": sorted(canonical.keys() - expected.keys())}

new = (
    "implement-spec",
    "pr",
    "retro",
    "wizard",
    "to-questionnaire",
    "wait-what",
    "writing-for-agents",
)
removed = ("resolving-merge-conflicts", "edit-article", "obsidian-vault", "writing-great-skills")
for skill in new:
    assert skill in canonical, skill
for skill in removed:
    assert skill not in canonical, skill

for skill, source in canonical.items():
    assert (source / "SKILL.md").is_file(), source
    for harness in (".claude/skills", ".pi/agent/skills"):
        assert f"{harness}/{skill}" in files, (harness, skill)

print(f"Pinned upstream: {pin['original']['ref']} ({pin['locked']['rev']})")
print(f"Managed Matt Pocock skills: {len(canonical)} across {', '.join(groups)}")
for skill in new:
    print(f"{skill}: {canonical[skill].relative_to(upstream)} -> .agents, Claude, Pi")
print("Removed and renamed legacy skill names: absent")
