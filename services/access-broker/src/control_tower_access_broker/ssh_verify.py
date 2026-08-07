"""OpenSSH namespace-signature verification without private-key handling."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

SIGNATURE_NAMESPACE = "copilot-control-tower"


def canonical_challenge(
    *,
    audience: str,
    login: str,
    machine_id: str,
    nonce_id: str,
    nonce: str,
) -> bytes:
    # Newline-delimited, fixed-order, versioned fields avoid JSON canonicalizer
    # drift between Python clients while binding the signature to this broker.
    values = ("1", audience, login.casefold(), machine_id, nonce_id, nonce)
    if any("\n" in value or "\r" in value for value in values):
        raise ValueError("challenge fields must be single-line")
    return ("\n".join(values) + "\n").encode("utf-8")


def verify_signature(
    *,
    login: str,
    message: bytes,
    signature: str,
    public_keys: list[str],
    executable: str | None = None,
) -> bool:
    ssh_keygen = executable or shutil.which("ssh-keygen")
    if not ssh_keygen or len(signature.encode("utf-8")) > 16_384:
        return False
    if not signature.startswith("-----BEGIN SSH SIGNATURE-----"):
        return False
    try:
        with tempfile.TemporaryDirectory(prefix="ct-broker-verify-") as directory:
            root = Path(directory)
            allowed = root / "allowed_signers"
            signature_path = root / "signature"
            allowed.write_text(
                "".join(f"{login} {key}\n" for key in public_keys),
                encoding="utf-8",
            )
            signature_path.write_text(signature, encoding="utf-8")
            allowed.chmod(0o600)
            signature_path.chmod(0o600)
            result = subprocess.run(  # noqa: S603 -- executable is resolved by shutil.which.
                [
                    ssh_keygen,
                    "-Y",
                    "verify",
                    "-f",
                    str(allowed),
                    "-I",
                    login,
                    "-n",
                    SIGNATURE_NAMESPACE,
                    "-s",
                    str(signature_path),
                ],
                input=message,
                capture_output=True,
                check=False,
                timeout=5,
                env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
            )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0
