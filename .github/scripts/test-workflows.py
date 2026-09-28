#!/usr/bin/env python3

from pathlib import Path

import yaml


class WorkflowLoader(yaml.SafeLoader):
    pass


for resolver_key, resolvers in list(WorkflowLoader.yaml_implicit_resolvers.items()):
    WorkflowLoader.yaml_implicit_resolvers[resolver_key] = [
        resolver
        for resolver in resolvers
        if resolver[0] != "tag:yaml.org,2002:bool"
    ]


ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"


def load_workflow(name: str) -> dict:
    with (WORKFLOWS / name).open(encoding="utf-8") as source:
        return yaml.load(source, Loader=WorkflowLoader)


def find_step(job: dict, name: str) -> dict:
    return next(step for step in job["steps"] if step.get("name") == name)


workflow_files = sorted(path.name for path in WORKFLOWS.iterdir())
assert workflow_files == ["build-unsigned-ipa.yml", "objective-c-xcode.yml"], workflow_files

ipa = load_workflow("build-unsigned-ipa.yml")
assert set(ipa["on"]) == {"workflow_dispatch", "pull_request"}
ipa_job = ipa["jobs"]["build-unsigned-ipa"]
assert ipa_job["runs-on"] == "macos-26"
assert ipa_job["env"]["DEVELOPER_DIR"].endswith("Xcode_26.6.app/Contents/Developer")

package_step = find_step(ipa_job, "Package and validate LiveContainer IPA")
assert ".github/scripts/package-unsigned-ipa.sh" in package_step["run"]
assert "artifacts/FlashMoE-unsigned.ipa" in package_step["run"]

ipa_upload = find_step(ipa_job, "Upload unsigned IPA")
assert ipa_upload["uses"] == "actions/upload-artifact@v7"
assert ipa_upload["with"] == {
    "name": "FlashMoE-unsigned-ipa",
    "path": "artifacts/FlashMoE-unsigned.ipa",
    "if-no-files-found": "error",
}

ci = load_workflow("objective-c-xcode.yml")
assert set(ci["on"]) == {"push", "pull_request"}
ci_job = ci["jobs"]["build"]
assert ci_job["runs-on"] == "macos-26"
assert ci_job["env"]["DEVELOPER_DIR"].endswith("Xcode_26.6.app/Contents/Developer")

derived_data_upload = find_step(ci_job, "Upload Xcode DerivedData")
assert derived_data_upload["uses"] == "actions/upload-artifact@v7"
assert derived_data_upload["with"] == {
    "name": "xcode-derived-data",
    "path": "build",
    "if-no-files-found": "error",
}

print("workflow tests passed")
