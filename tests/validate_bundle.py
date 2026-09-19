import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "plugins" / "com.amade.manual-multicolor"


def main() -> None:
    manifest = json.loads((BUNDLE / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["id"] == BUNDLE.name
    assert manifest["required_apis"] == {"project.plugin": "1.0.0"}

    commands = []
    for path in sorted(BUNDLE.glob("*.lua")):
        source = path.read_text(encoding="utf-8")
        if re.search(r"\binfo\s*=\s*{", source) and re.search(
            r"\bfunction\s+execute\s*\(", source
        ):
            assert re.search(r'menu\s*=\s*"[^"\r\n]+"', source), path
            assert "require(\"api\")" not in source
            commands.append(path.name)

    assert commands == [
        "add_layer_stack_test.lua",
        "audit_setup.lua",
        "inspect_project.lua",
    ], commands

    postprocess = BUNDLE / "postprocess"
    assert (postprocess / "FlattenManualColoursAboveFirstLayer.ps1").is_file()
    assert (postprocess / "run-manual-multicolor.cmd").is_file()
    print(f"Validated {manifest['id']} {manifest['version']}: {', '.join(commands)}")


if __name__ == "__main__":
    main()
