#!/usr/bin/env python3
"""Genera los datasets sintéticos usados por los scripts k6.

- profiles_exp1.json: 1.000 client_id únicos para HA01 (cotización)
- profiles_exp2.json: 5.000 client_id + consentimiento_id para HA02 (perfilamiento)
"""
import json
import uuid
from pathlib import Path

OUT_DIR = Path(__file__).parent

N_EXP1 = 1_000
N_EXP2 = 5_000


def generate_exp1():
    data = [{"client_id": f"client-exp1-{i:05d}"} for i in range(N_EXP1)]
    (OUT_DIR / "profiles_exp1.json").write_text(json.dumps(data, indent=2))
    print(f"profiles_exp1.json: {len(data)} perfiles")


def generate_exp2():
    data = [
        {
            "client_id": f"client-exp2-{i:05d}",
            "consentimiento_id": str(uuid.uuid5(uuid.NAMESPACE_DNS, f"cons-{i}")),
        }
        for i in range(N_EXP2)
    ]
    (OUT_DIR / "profiles_exp2.json").write_text(json.dumps(data, indent=2))
    print(f"profiles_exp2.json: {len(data)} perfiles")


if __name__ == "__main__":
    generate_exp1()
    generate_exp2()
