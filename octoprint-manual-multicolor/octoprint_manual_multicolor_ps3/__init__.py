"""OctoPrint display prompts for the ps3-manual-colour PrusaSlicer workflow."""
from __future__ import absolute_import

import re
from pathlib import Path

from flask import jsonify

import octoprint.plugin
from octoprint.events import Events


class ManualColourPromptsPlugin(
    octoprint.plugin.AssetPlugin,
    octoprint.plugin.EventHandlerPlugin,
    octoprint.plugin.SimpleApiPlugin,
    octoprint.plugin.TemplatePlugin,
):
    """Pair M117 Load <colour> with the following M600 and notify OctoPrint."""

    _load_message = re.compile(r"^\s*M117\s+Load\s+(.+?)\s*(?:;.*)?$", re.IGNORECASE)
    _m600_colour = re.compile(r'\bC"([^"]+)"', re.IGNORECASE)
    _extruder_colours = re.compile(r"^\s*;\s*extruder_colour\s*=\s*(.+)$", re.IGNORECASE)
    _segment_message = re.compile(r'^\s*M118\s+MCP_SEGMENT\s+L=(\d+)\s+S=(\d+)\s+C="([^"]+)"', re.IGNORECASE)

    @staticmethod
    def _colour_from_hex(value):
        """Use PrusaSlicer's first virtual-extruder colour as a safe fallback."""
        names = {
            "#000000": "Black", "#0000ff": "Blue", "#ffffff": "White",
            "#ff0000": "Red", "#00ff00": "Green", "#008000": "Green",
            "#ffff00": "Yellow", "#ff8000": "Orange", "#ffa500": "Orange",
            "#800080": "Purple", "#808080": "Grey",
        }
        return names.get((value or "").lower())

    def initialize(self):
        self._file_colours = []
        self._print_active = False
        self._loaded_path = None
        self._used_colours = []
        self._next_colour = None
        self._schedule = []
        self._initial_colour = None
        self._current_change = 0
        self._waiting_for_change = False
        self._loaded_colour = None
        self._pending_load_colour = None
        self._layer_colours = []
        self._profile_detected = False
        self._active_layer = 0
        self._active_segment = 0
        self._active_colour = None

    def get_assets(self):
        return {"js": ["js/manual_multicolor_ps3.js"], "css": ["css/manual_multicolor_ps3.css"]}

    def get_template_vars(self):
        from .version import DISPLAY_VERSION, PRUSASLICER_TARGET
        return {"release_label": DISPLAY_VERSION, "slicer_target": PRUSASLICER_TARGET}

    def get_template_configs(self):
        return [
            # Keep the navbar outside OctoPrint's shared Knockout binding tree.
            # Binding this template together with core navbar view models can
            # prevent loginStateViewModel from updating the Login/User menu.
            {"type": "navbar", "custom_bindings": True},
            {"type": "tab", "custom_bindings": False},
        ]

    def on_api_get(self, request):
        # The tab may be opened after a file was selected, so recover the
        # selected local job on demand instead of relying only on events.
        if self._loaded_path is None:
            try:
                current = self._printer.get_current_job() or {}
                file_data = current.get("file") or {}
                if file_data.get("path"):
                    self._load_schedule({"origin": file_data.get("origin"), "path": file_data.get("path")})
            except Exception:
                self._logger.exception("Could not inspect the selected job")
        return jsonify({
            "file_colours": self._file_colours,
            "print_active": self._print_active,
            "used_colours": self._used_colours,
            "initial_colour": self._initial_colour,
            "schedule": self._schedule,
            "current_change": self._current_change,
            "next_colour": self._next_colour,
            "waiting_for_change": self._waiting_for_change,
            "loaded_colour": self._loaded_colour,
            "layer_colours": self._layer_colours,
            "profile_detected": self._profile_detected,
            "active_layer": self._active_layer,
            "active_segment": self._active_segment,
            "active_colour": self._active_colour,
        })

    def _send_state(self, action="schedule"):
        self._plugin_manager.send_plugin_message(self._identifier, {
            "file_colours": self._file_colours,
            "print_active": self._print_active,
            "used_colours": self._used_colours,
            "action": action,
            "initial_colour": self._initial_colour,
            "schedule": self._schedule,
            "current_change": self._current_change,
            "next_colour": self._next_colour,
            "waiting_for_change": self._waiting_for_change,
            "loaded_colour": self._loaded_colour,
            "layer_colours": self._layer_colours,
            "profile_detected": self._profile_detected,
            "active_layer": self._active_layer,
            "active_segment": self._active_segment,
            "active_colour": self._active_colour,
        })

    def _load_schedule(self, payload):
        """Read the saved G-code once at PrintStarted, outside the serial loop."""
        self._file_colours = []
        self._print_active = False
        self._schedule = []
        self._used_colours = []
        self._next_colour = None
        self._waiting_for_change = False
        self._loaded_colour = None
        self._loaded_path = None
        self._initial_colour = None
        self._current_change = 0
        self._layer_colours = []
        self._profile_detected = False
        self._active_layer = 0
        self._active_segment = 0
        self._active_colour = None
        try:
            origin = payload.get("origin") or payload.get("target") or payload.get("storage") or "local"
            path = self._file_manager.path_on_disk(origin, payload.get("path"))
            self._loaded_path = path
            used_slots, palette_values, labels = [], [], []
            layer, z, pending_colour = 0, None, None
            fallback_initial = None
            layer_sequences = {}
            active_colour = None
            with Path(path).open("r", encoding="utf-8", errors="replace") as gcode:
                for raw in gcode:
                    line = raw.strip()
                    if line == ";LAYER_CHANGE":
                        layer += 1
                        if active_colour:
                            layer_sequences[layer] = [active_colour]
                    elif line.startswith(";Z:"):
                        try:
                            z = float(line[3:])
                        except ValueError:
                            pass
                    elif line.startswith("; MANUAL_COLOUR_INITIAL="):
                        self._initial_colour = line.split("=", 1)[1].strip()
                        active_colour = self._initial_colour
                        self._profile_detected = True
                        if layer > 0:
                            layer_sequences[layer] = [active_colour]
                    elif line.startswith("; MANUAL_COLOUR_USED_SLOTS="):
                        used_slots = [int(v) for v in line.split("=", 1)[1].split(",") if v.strip().isdigit()]
                    elif line.startswith("; MANUAL_COLOUR_LABELS="):
                        labels = [v.strip() for v in line.split("=", 1)[1].split(",")]
                    else:
                        palette = self._extruder_colours.match(line)
                        if palette:
                            palette_values = [v.strip() for v in palette.group(1).split(";")]
                        if palette and not fallback_initial:
                            first = palette.group(1).split(";", 1)[0].strip()
                            fallback_initial = first
                        match = self._load_message.match(line)
                        if match:
                            pending_colour = match.group(1).strip()
                        elif re.match(r"^M600(?:\s|;|$)", line):
                            named = self._m600_colour.search(line)
                            # Prefer the human-readable M117 label. Buddy's
                            # M600 colour token is intentionally upper-case.
                            colour = pending_colour or (named.group(1) if named else None)
                            self._schedule.append({"number": len(self._schedule) + 1, "layer": layer, "z": z, "colour": colour or "Filament change"})
                            active_colour = colour or "Filament change"
                            if layer > 0:
                                layer_sequences.setdefault(layer, [])
                                if not layer_sequences[layer] or layer_sequences[layer][-1].lower() != active_colour.lower():
                                    layer_sequences[layer].append(active_colour)
                            pending_colour = None
            # Older G-code predates MANUAL_COLOUR_INITIAL. Its first virtual
            # extruder is still the filament that must be loaded at print start.
            if not self._initial_colour:
                self._initial_colour = fallback_initial or "Initial filament"
            self._loaded_colour = self._initial_colour
            self._file_colours = [
                {"slot": i + 1, "colour": colour, "label": labels[i] if i < len(labels) else None,
                 "used": i + 1 in used_slots if used_slots else None}
                for i, colour in enumerate(palette_values) if colour
            ]
            for slot in sorted(set(used_slots)):
                if 1 <= slot <= len(palette_values):
                    self._used_colours.append({"slot": slot, "colour": palette_values[slot - 1], "label": labels[slot - 1] if slot <= len(labels) else None})
            self._pending_load_colour = None
            if self._profile_detected:
                active_colour = self._initial_colour
                for layer_number in range(1, layer + 1):
                    sequence = layer_sequences.get(layer_number)
                    if not sequence:
                        sequence = [active_colour]
                    elif sequence[0].lower() != active_colour.lower():
                        sequence.insert(0, active_colour)
                    active_colour = sequence[-1]
                    layer_sequences[layer_number] = sequence
                self._layer_colours = [
                    {"layer": layer_number, "colours": layer_sequences[layer_number]}
                    for layer_number in range(1, layer + 1)
                ]
        except Exception:
            self._logger.exception("Could not read the ps3-manual-colour schedule")

    def on_event(self, event, payload):
        if event == Events.PRINT_STARTED:
            self._next_colour = None
            self._waiting_for_change = False
            self._pending_load_colour = None
            self._load_schedule(payload or {})
            self._print_active = True
            self._send_state()
        elif event == Events.FILE_SELECTED:
            self._load_schedule(payload or {})
            self._send_state()
        elif event in (Events.PRINT_DONE, Events.PRINT_CANCELLED, Events.PRINT_FAILED):
            self._print_active = False
            self._next_colour = None
            self._current_change = 0
            self._waiting_for_change = False
            self._pending_load_colour = None
            self._send_state("clear")

    def gcode_sending(self, comm_instance, phase, cmd, cmd_type, gcode, subcode=None, tags=None, *args, **kwargs):
        """Runs in the serial loop: only small regex/state operations belong here."""
        if not self._profile_detected:
            return
        # This is sent-command progress, not proof of physical completion.
        if self._waiting_for_change and gcode not in ("M600", "M117"):
            self._waiting_for_change = False
            if self._pending_load_colour:
                self._loaded_colour = self._pending_load_colour
            self._pending_load_colour = None
            self._send_state("resumed")
        if gcode == "M117":
            match = self._load_message.match(cmd)
            if match:
                self._next_colour = match.group(1).strip()
                self._plugin_manager.send_plugin_message(
                    self._identifier,
                    {"action": "next", "colour": self._next_colour},
                )
        elif gcode == "M118":
            segment = self._segment_message.match(cmd)
            if segment:
                self._active_layer = int(segment.group(1))
                self._active_segment = int(segment.group(2))
                self._active_colour = segment.group(3).strip()
                self._send_state("segment")
        elif gcode == "M600":
            named = self._m600_colour.search(cmd)
            planned = self._schedule[self._current_change].get("colour") if self._current_change < len(self._schedule) else None
            colour = self._next_colour or (named.group(1) if named else None) or planned or "the requested filament"
            self._current_change += 1
            self._next_colour = None
            self._waiting_for_change = True
            self._pending_load_colour = colour
            self._send_state("change")
            self._plugin_manager.send_plugin_message(self._identifier, {"action": "prompt", "colour": colour})


__plugin_name__ = "PS3 Manual Multicolor"
__plugin_pythoncompat__ = ">=3.7,<4"


def __plugin_load__():
    global __plugin_implementation__
    __plugin_implementation__ = ManualColourPromptsPlugin()

    global __plugin_hooks__
    __plugin_hooks__ = {
        "octoprint.comm.protocol.gcode.sending": __plugin_implementation__.gcode_sending,
    }
