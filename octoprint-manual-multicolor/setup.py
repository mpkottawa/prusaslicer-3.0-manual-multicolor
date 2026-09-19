from setuptools import setup
from pathlib import Path
import runpy

release = runpy.run_path(str(Path(__file__).parent / "octoprint_manual_multicolor_ps3" / "version.py"))

plugin_identifier = "manual_multicolor_ps3"
plugin_package = "octoprint_manual_multicolor_ps3"
plugin_name = "PS3 Manual Multicolor"
plugin_version = release["VERSION"]
plugin_description = "Shows the next manual filament colour change in OctoPrint."
plugin_author = "Local PrusaSlicer workflow"
plugin_license = "AGPLv3"

setup(
    name="OctoPrint-{}".format(plugin_identifier),
    version=plugin_version,
    description=plugin_description,
    author=plugin_author,
    url="https://github.com/mpkottawa/prusaslicer-3.0-manual-multicolor",
    license=plugin_license,
    packages=[plugin_package],
    include_package_data=True,
    install_requires=["OctoPrint>=1.8.0"],
    entry_points={
        "octoprint.plugin": [
            "{} = {}".format(plugin_identifier, plugin_package)
        ]
    },
)
