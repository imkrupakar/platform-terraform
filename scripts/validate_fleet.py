#!/usr/bin/env python3
"""Validate that fleet.yaml and the live/ stacks agree (drift guard).

Checks, for each cluster entry in fleet.yaml:
  - the live stack directory exists at `path`
  - the pinned module `?ref` for aks/eks/gke-cluster and argocd-bootstrap in that stack's
    main.tf match module_versions.cluster / module_versions.argocd_bootstrap

Also enforces monotonic promotion: a module/chart version must not appear in a higher
environment unless the next-lower environment already runs that version.
"""
import os
import re
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_ORDER = ["sbx", "dev", "stg", "prd"]
REF_RE = re.compile(r"//modules/([a-z-]+)\?ref=([^\"']+)")


def load_fleet():
    with open(os.path.join(ROOT, "fleet.yaml")) as f:
        return yaml.safe_load(f)


def stack_refs(path):
    main = os.path.join(ROOT, path, "main.tf")
    refs = {}
    with open(main) as f:
        for mod, ref in REF_RE.findall(f.read()):
            refs[mod] = ref
    return refs


def main():
    fleet = load_fleet()
    errors = []
    for c in fleet["clusters"]:
        path = c["path"]
        if not os.path.isdir(os.path.join(ROOT, path)):
            errors.append(f"{c['name']}: live stack missing at {path}")
            continue
        refs = stack_refs(path)
        want = c["module_versions"]
        cluster_mod = next((m for m in refs if m.endswith("-cluster")), None)
        if cluster_mod and refs[cluster_mod] != want["cluster"]:
            errors.append(f"{c['name']}: {cluster_mod} ?ref={refs[cluster_mod]} != fleet cluster {want['cluster']}")
        if refs.get("argocd-bootstrap") != want["argocd_bootstrap"]:
            errors.append(f"{c['name']}: argocd-bootstrap ?ref={refs.get('argocd-bootstrap')} != fleet {want['argocd_bootstrap']}")

    # monotonic promotion: a higher env must not run a version absent from the next-lower env.
    by_env = {}
    for c in fleet["clusters"]:
        by_env.setdefault(c["environment"], []).append(c["module_versions"])
    for key in ("cluster", "argocd_bootstrap", "argocd_chart"):
        for i in range(1, len(ENV_ORDER)):
            hi, lo = ENV_ORDER[i], ENV_ORDER[i - 1]
            hi_vals = {mv[key] for mv in by_env.get(hi, [])}
            lo_vals = {mv[key] for mv in by_env.get(lo, [])}
            if not lo_vals:
                continue
            for v in hi_vals:
                if v not in lo_vals:
                    errors.append(f"promotion: {key}={v} in {hi} but not present in {lo} (promote lower env first)")

    if errors:
        print("FLEET DRIFT:")
        for e in errors:
            print("  -", e)
        sys.exit(1)
    print(f"fleet OK: {len(fleet['clusters'])} clusters consistent with live stacks")


if __name__ == "__main__":
    main()
