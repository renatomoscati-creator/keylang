#!/usr/bin/env python3
"""Structural checks on LinguaKey.xcodeproj, for a machine with no Xcode.

The project file was hand-written, because there is no Xcode here to write it.
That makes it the single most likely thing in the repository to be subtly wrong,
and the failure mode is an hour lost on the one machine that can open it. These
checks catch the errors that are mechanical: dangling references, paths that do
not exist, targets missing a configuration, package products that the package
does not actually export.

What they cannot catch is whether Xcode likes the result. That needs Xcode.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import pbxproj

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "LinguaKey.xcodeproj" / "project.pbxproj"

failures: list[str] = []
passed = 0


def check(name: str, condition: bool, detail: str = "") -> None:
    global passed
    if condition:
        passed += 1
        print(f"  ok  {name}")
    else:
        failures.append(f"{name}{': ' + detail if detail else ''}")
        print(f"  FAIL {name} {detail}")


def done() -> None:
    print()
    if failures:
        print(f"FAIL: {len(failures)} of {passed + len(failures)}")
        for failure in failures:
            print(f"  - {failure}")
        sys.exit(1)
    print(f"PASS: {passed} project checks")
    sys.exit(0)


if not PROJECT.exists():
    check("LinguaKey.xcodeproj exists", False, str(PROJECT))
    done()

doc = pbxproj.load(PROJECT)
objects = doc["objects"]
check("the project file parses", True)
check("objectVersion is 77, which is what synchronized folder groups need",
      doc["objectVersion"] == "77", doc["objectVersion"])


# --------------------------------------------------------- references resolve

TOKEN = re.compile(r"^[0-9A-F]{24}$")
dangling: list[str] = []


def walk(value, where: str) -> None:
    if isinstance(value, dict):
        for item in value.values():
            walk(item, where)
    elif isinstance(value, list):
        for item in value:
            walk(item, where)
    elif isinstance(value, str) and TOKEN.match(value) and value not in objects:
        dangling.append(f"{where} -> {value}")


for oid, obj in objects.items():
    walk(obj, f"{obj.get('isa', '?')} {oid}")
check("every object reference resolves", not dangling, f"{dangling[:5]}")
check("rootObject resolves", doc["rootObject"] in objects)

project = objects[doc["rootObject"]]
check("the root object is a PBXProject", project["isa"] == "PBXProject")


# --------------------------------------------------------- targets

targets = {objects[t]["name"]: objects[t] for t in project["targets"]}
check("both targets exist", set(targets) == {"LinguaKey", "LinguaKeyShare"},
      f"{sorted(targets)}")

check("the app is an application",
      targets.get("LinguaKey", {}).get("productType") == "com.apple.product-type.application")
check("the share extension is an app extension",
      targets.get("LinguaKeyShare", {}).get("productType")
      == "com.apple.product-type.app-extension")

# An extension that is not embedded builds fine and then simply does not exist
# on the phone, which reads as "the share sheet does not show it".
app = targets["LinguaKey"]
embed = [objects[p] for p in app["buildPhases"]
         if objects[p]["isa"] == "PBXCopyFilesBuildPhase"]
check("the app has an embed phase", len(embed) == 1, f"{len(embed)}")
if embed:
    check("the embed phase targets PlugIns (dstSubfolderSpec 13)",
          embed[0]["dstSubfolderSpec"] == "13", embed[0]["dstSubfolderSpec"])
    embedded = {objects[objects[f]["fileRef"]]["path"] for f in embed[0]["files"]}
    check("the appex is what gets embedded", embedded == {"LinguaKeyShare.appex"},
          f"{embedded}")

deps = [objects[d] for d in app["dependencies"]]
check("the app depends on the extension so it builds first",
      any(objects[d["target"]]["name"] == "LinguaKeyShare" for d in deps))


# --------------------------------------------------------- synchronized groups

for name, target in targets.items():
    groups = target.get("fileSystemSynchronizedGroups", [])
    check(f"{name} uses a synchronized folder group", len(groups) == 1, f"{groups}")
    for gid in groups:
        path = ROOT / objects[gid]["path"]
        check(f"{name}'s folder exists on disk", path.is_dir(), str(path))
        swift = list(path.glob("*.swift"))
        check(f"{name}'s folder has sources", bool(swift), str(path))
        # Info.plist and the entitlements are named by build settings. If they
        # are also members of the target they get copied into the bundle as
        # resources, which is at best noise and at worst a duplicate-Info.plist
        # build failure.
        exceptions = set()
        for eid in objects[gid].get("exceptions", []):
            exceptions.update(objects[eid].get("membershipExceptions", []))
        for special in ("Info.plist", f"{name}.entitlements"):
            if (path / special).exists():
                check(f"{name} excludes {special} from its target membership",
                      special in exceptions, f"{sorted(exceptions)}")


# --------------------------------------------------------- build settings

configs = {}
for name, target in targets.items():
    for cid in objects[target["buildConfigurationList"]]["buildConfigurations"]:
        configs[(name, objects[cid]["name"])] = objects[cid]["buildSettings"]

for name in targets:
    for flavour in ("Debug", "Release"):
        check(f"{name} has a {flavour} configuration", (name, flavour) in configs)

for (name, flavour), settings in sorted(configs.items()):
    for key in ("INFOPLIST_FILE", "CODE_SIGN_ENTITLEMENTS"):
        path = settings.get(key)
        check(f"{name}/{flavour} sets {key}", path is not None)
        if path:
            check(f"{name}/{flavour} {key} exists on disk", (ROOT / path).exists(), path)
    check(f"{name}/{flavour} does not also generate an Info.plist",
          settings.get("GENERATE_INFOPLIST_FILE") == "NO",
          settings.get("GENERATE_INFOPLIST_FILE", "unset"))

project_settings = {
    objects[cid]["name"]: objects[cid]
    for cid in objects[project["buildConfigurationList"]]["buildConfigurations"]
}
for flavour, config in sorted(project_settings.items()):
    settings = config["buildSettings"]
    check(f"project/{flavour} targets iOS 26.0",
          settings.get("IPHONEOS_DEPLOYMENT_TARGET") == "26.0",
          settings.get("IPHONEOS_DEPLOYMENT_TARGET", "unset"))
    check(f"project/{flavour} builds Swift 6",
          settings.get("SWIFT_VERSION") == "6.0", settings.get("SWIFT_VERSION", "unset"))
    # Team ID and bundle prefix are per developer and must not be committed.
    base = config.get("baseConfigurationReference")
    check(f"project/{flavour} reads Local.xcconfig", base is not None)
    if base:
        check(f"project/{flavour} points at LinguaKeyApp/Local.xcconfig",
              objects[base]["path"] == "LinguaKeyApp/Local.xcconfig",
              objects[base]["path"])
    for forbidden in ("DEVELOPMENT_TEAM", "BUNDLE_PREFIX"):
        check(f"project/{flavour} does not hardcode {forbidden}",
              forbidden not in settings)

check("Local.xcconfig is not committed",
      not (ROOT / "LinguaKeyApp/Local.xcconfig").exists()
      or "LinguaKeyApp/Local.xcconfig" in
      (ROOT / ".gitignore").read_text(encoding="utf-8"))
check("Local.xcconfig.example is committed",
      (ROOT / "LinguaKeyApp/Local.xcconfig.example").exists())


# --------------------------------------------------------- packages

local = [objects[r] for r in project.get("packageReferences", [])]
check("exactly one local package is referenced", len(local) == 1, f"{len(local)}")
if local:
    package_dir = ROOT / local[0]["relativePath"]
    check("the referenced package exists", (package_dir / "Package.swift").exists(),
          str(package_dir))

    manifest = (package_dir / "Package.swift").read_text(encoding="utf-8")
    exported = set(re.findall(r'\.library\(name:\s*"([^"]+)"', manifest))
    # LinguaKeyCore is exported by the package this one depends on.
    core = (ROOT / "LinguaKeyCore" / "Package.swift")
    if core.exists():
        exported |= set(re.findall(r'\.library\(name:\s*"([^"]+)"',
                                   core.read_text(encoding="utf-8")))

    for name, target in targets.items():
        wanted = {objects[d]["productName"]
                  for d in target.get("packageProductDependencies", [])}
        check(f"{name} links at least StudyKit and StudyUI",
              {"StudyKit", "StudyUI"} <= wanted, f"{sorted(wanted)}")
        missing = sorted(wanted - exported)
        check(f"every product {name} links is actually exported", not missing,
              f"missing: {missing}, exported: {sorted(exported)}")


# --------------------------------------------------------- resources

resource_paths = set()
for name, target in targets.items():
    for pid in target["buildPhases"]:
        phase = objects[pid]
        if phase["isa"] != "PBXResourcesBuildPhase":
            continue
        for fid in phase["files"]:
            ref = objects[objects[fid]["fileRef"]]
            resource_paths.add((name, ref["path"]))

check("the app bundles the staged data root",
      ("LinguaKey", "build/LinguaKeyData") in resource_paths, f"{sorted(resource_paths)}")
check("the extension bundles no copy of its own",
      not any(n == "LinguaKeyShare" for n, _ in resource_paths),
      "the extension would carry a second 3.9 MB of identical tables")


# --------------------------------------------------------- schemes

schemes = ROOT / "LinguaKey.xcodeproj/xcshareddata/xcschemes"
check("shared schemes are committed so xcodebuild -scheme works",
      schemes.is_dir() and any(schemes.glob("*.xcscheme")))
for scheme in sorted(schemes.glob("*.xcscheme")):
    text = scheme.read_text(encoding="utf-8")
    referenced = set(re.findall(r'BlueprintIdentifier = "([^"]+)"', text))
    unknown = sorted(r for r in referenced if r not in objects)
    check(f"{scheme.name} references only real targets", not unknown, f"{unknown}")

done()
