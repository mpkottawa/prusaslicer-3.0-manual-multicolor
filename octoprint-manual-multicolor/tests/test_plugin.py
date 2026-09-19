"""Offline integration tests with minimal OctoPrint host doubles."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import types
import unittest

host = types.ModuleType('octoprint')
host.plugin = types.ModuleType('octoprint.plugin')
for name in ('AssetPlugin', 'EventHandlerPlugin', 'SimpleApiPlugin', 'TemplatePlugin'):
    setattr(host.plugin, name, type(name, (), {}))
events = types.ModuleType('octoprint.events')
events.Events = types.SimpleNamespace(**{n: n for n in (
    'PRINT_STARTED', 'FILE_SELECTED', 'UPLOAD', 'PRINT_DONE', 'PRINT_CANCELLED', 'PRINT_FAILED')})
sys.modules.update({'octoprint': host, 'octoprint.plugin': host.plugin, 'octoprint.events': events})
sys.modules['flask'] = types.SimpleNamespace(jsonify=lambda x: x)
source = Path(__file__).parents[1] / 'octoprint_manual_multicolor_ps3' / '__init__.py'
spec = importlib.util.spec_from_file_location('companion', source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PluginTests(unittest.TestCase):
    def setUp(self):
        self.plugin = module.ManualColourPromptsPlugin()
        self.plugin.initialize()
        self.plugin._identifier = 'manual_multicolor_ps3'
        self.messages = []
        self.plugin._plugin_manager = types.SimpleNamespace(send_plugin_message=lambda _, x: self.messages.append(x))
        self.plugin._file_manager = types.SimpleNamespace(path_on_disk=lambda origin, path: path)
        self.plugin._logger = types.SimpleNamespace(exception=lambda msg: self.fail(msg))

    def test_used_slots_and_events(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.gcode'
            path.write_text('; MANUAL_COLOUR_USED_SLOTS=1,3,5\n'
                            ';LAYER_CHANGE\n;Z:0.2\n; MANUAL_COLOUR_INITIAL=#000AFF\n'
                            'M117 Load #E92233\nM600 C"#E92233"\n'
                            ';LAYER_CHANGE\n;Z:0.4\nM600 C"#00FF00"\n'
                            '; extruder_colour = #000AFF;#FFFFFF;#E92233;#FFFF00;#00FF00\n')
            self.plugin._load_schedule({'path': str(path)})
            self.assertEqual([c['slot'] for c in self.plugin._used_colours], [1, 3, 5])
            self.assertEqual(len(self.plugin._file_colours), 5)
            self.assertFalse(self.plugin._file_colours[1]['used'])
            self.plugin.on_event('PRINT_STARTED', {'path': str(path)})
            self.assertTrue(self.plugin._print_active)
            self.assertEqual(len(self.plugin._schedule), 2)
            self.assertEqual(len(self.plugin._layer_colours), 2)
            self.plugin.on_event('UPLOAD', {'path': 'unrelated.gcode'})
            self.assertEqual(self.plugin._loaded_path, str(path))
            self.plugin.gcode_sending(None, None, 'M600', None, 'M600')
            self.assertEqual(self.plugin._pending_load_colour, '#E92233')
            self.assertEqual(self.plugin._current_change, 1)
            self.plugin.on_event('PRINT_DONE', {})
            self.assertFalse(self.plugin._print_active)

    def test_schedule_across_top_and_bottom_layers(self):
        with tempfile.TemporaryDirectory() as directory:
            sample = Path(directory) / 'synthetic.gcode'
            lines = ['; MANUAL_COLOUR_INITIAL=Black']
            for layer in range(1, 18):
                lines.extend([';LAYER_CHANGE', f';Z:{layer * 0.2:.2f}'])
                if layer in (1, 2, 16, 17):
                    colour = 'Green' if layer in (1, 16) else 'Black'
                    lines.extend([f'M117 Load {colour}', f'M600 C"{colour}"'])
            sample.write_text('\n'.join(lines))
            self.plugin._load_schedule({'path': str(sample)})
            self.assertTrue(self.plugin._profile_detected)
            self.assertEqual(len(self.plugin._schedule), 4)
            self.assertEqual(len(self.plugin._layer_colours), 17)
            self.assertEqual([s['layer'] for s in self.plugin._schedule], [1, 2, 16, 17])

    def test_no_commands_sent_or_rewritten(self):
        self.assertIsNone(self.plugin.gcode_sending(None, None, 'M600', None, 'M600'))
        self.assertEqual(self.messages, [])


if __name__ == '__main__':
    unittest.main()
