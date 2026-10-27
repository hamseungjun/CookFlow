"""Write local Xcode pairing settings; the generated file is ignored by Git."""
from pathlib import Path
import os

def write_pairing(root: Path, base: str, token: str) -> None:
    if not (base.startswith("http://") or base.startswith("https://")) or "\n" in base or "\n" in token:
        raise ValueError("Invalid pairing settings")
    # xcconfig treats // as a comment, so expand an empty variable between slashes.
    escaped_base = base.replace("://", ":/$()/", 1)
    config = root / "CookFlow/Local.xcconfig"
    config.write_text(f"COOKFLOW_SERVER_BASE = {escaped_base}\nCOOKFLOW_CLIENT_TOKEN = {token}\n")
    os.chmod(config, 0o600)
