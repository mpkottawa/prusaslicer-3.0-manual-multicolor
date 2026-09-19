$(function () {
    function ManualColourPromptsViewModel(parameters) {
        var self = this;
        self.updateMessage = ko.observable("");
        var updateSettings = parameters[0], updateLogin = parameters[1], updatePrinter = parameters[2];
        var updateAccess = parameters[3], updateManager = parameters[4];
        self.updateBlockedReason = ko.pureComputed(function () {
            if (!updateManager || typeof updateManager.showRepository !== "function") return "OctoPrint Plugin Manager is unavailable.";
            var permissions = updateAccess && updateAccess.permissions;
            if (!permissions || !permissions.PLUGIN_PLUGINMANAGER_INSTALL || !permissions.PLUGIN_PLUGINMANAGER_MANAGE ||
                !updateLogin || !updateLogin.hasPermission(permissions.PLUGIN_PLUGINMANAGER_INSTALL) ||
                !updateLogin.hasPermission(permissions.PLUGIN_PLUGINMANAGER_MANAGE)) return "Log in with permission to install plugins.";
            if (!updatePrinter || typeof updatePrinter.isBusy !== "function" || updatePrinter.isBusy()) return "Finish or cancel the print before updating (paused prints also count).";
            if (typeof updateManager.working !== "function" || updateManager.working()) return "Plugin Manager is busy. Wait for it to finish.";
            if (typeof updateManager.pipAvailable !== "function" || updateManager.pipAvailable() !== true) return "Plugin installer is not ready.";
            if ((updateManager.safeMode && updateManager.safeMode()) || (updateManager.throttled && updateManager.throttled())) return "OctoPrint currently blocks plugin installation; check Plugin Manager.";
            return "";
        });
        self.canUpdatePlugin = ko.pureComputed(function () { return self.updateBlockedReason() === ""; });
        self.openPluginUpdate = function () {
            self.updateMessage("");
            var reason = self.updateBlockedReason();
            if (reason) { self.updateMessage(reason); return false; }
            try {
                if (!updateSettings || typeof updateSettings.show !== "function") throw new Error("Settings unavailable");
                updateSettings.show("settings_plugin_pluginmanager");
                // Use the normal manager entry point: it owns reauthentication
                // and repository restrictions. Never bypass either dialog.
                updateManager.showRepository();
                var dialog = $("#settings_plugin_pluginmanager_repositorydialog");
                var input = document.getElementById("settings_plugin_pluginmanager_repositorydialog_upload");
                if (!dialog.is(":visible")) {
                    self.updateMessage("Complete OctoPrint's authentication or restriction prompt, then use Browse in the installer.");
                    return false;
                }
                if (!input || input.type !== "file" || input.disabled) throw new Error("File picker unavailable");
                // Stay in this user-click call stack. Waiting for a timer/modal
                // animation can lose browser permission to open a file picker.
                if (input.scrollIntoView) input.scrollIntoView({block: "center"});
                if (typeof input.showPicker === "function") input.showPicker();
                else input.click();
                self.updateMessage("Choose the new PS3 Manual Multicolor ZIP, then click Install in Plugin Manager. If the chooser did not open, click Browse there.");
            } catch (error) {
                self.updateMessage("Use Plugin Manager > Get More > Browse to choose the ZIP. Automatic file selection is unavailable in this browser or OctoPrint version.");
            }
            // Selecting a file does not install it. OctoPrint retains its own
            // Install button, permissions, server checks and restart prompt.
            return false;
        };
        self.colourStatus = ko.observable("Manual colours ready");
        self.colourDetail = ko.observable("Waiting for a colour-change command");
        self.initialColour = ko.observable("Not read yet");
        self.nextColour = ko.observable("None");
        self.bulbColour = ko.observable("#777");
        self.bulbFlashing = ko.observable(false);
        self.bulbTitle = ko.observable("No manual colour change in progress");
        self.activeLabel = ko.observable("NO FILE");
        self.activeTextColour = ko.observable("#fff");
        self.currentChange = ko.observable(0);
        self.schedule = ko.observableArray([]);
        self.layerRows = ko.observableArray([]);
        self.usedColours = ko.observableArray([]);
        self.fileColours = ko.observableArray([]);
        self.profileDetected = ko.observable(false);
        self.tabStatus = ko.observable("Start a ps3-manual-colour print to load its change plan.");
        self.colourName = function (value) {
            value = value || "Unknown";
            if (!/^#[0-9a-f]{6}$/i.test(value)) return value;
            var rgb = parseInt(value.slice(1), 16);
            var r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255;
            var max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
            if (max < 45) return "Black";
            if (min > 225) return "White";
            if (delta < 25) return "Grey";
            var hue = max === r ? ((g - b) / delta) % 6 : (max === g ? (b - r) / delta + 2 : (r - g) / delta + 4);
            hue = (hue * 60 + 360) % 360;
            if (hue < 15 || hue >= 345) return "Red";
            if (hue < 45) return (max + min) / 510 < 0.45 ? "Brown" : "Orange";
            if (hue < 70) return "Yellow";
            if (hue < 165) return "Green";
            if (hue < 195) return "Cyan";
            if (hue < 265) return "Blue";
            if (hue < 295) return "Purple";
            return "Pink";
        };
        self.progressPercent = ko.pureComputed(function () {
            var total = self.schedule().length;
            return total ? Math.min(100, ((self.currentChange() + 1) / total) * 100) + "%" : "0%";
        });
        self.swatchFor = function (colour) {
            var known = {black: "#111", white: "#fff", blue: "#1565ff", red: "#e53935", green: "#27a844", yellow: "#ffde00", orange: "#ff8c00", purple: "#7e57c2", pink: "#ec6aa6", grey: "#888", gray: "#888", brown: "#795548"};
            var value = (colour || "").toLowerCase();
            return /^#[0-9a-f]{6}$/.test(value) ? value : (known[value] || "#777");
        };
        self.textForSwatch = function (swatch) {
            var hex = (swatch || "#777").replace("#", "");
            if (hex.length === 3) hex = hex.split("").map(function (c) { return c + c; }).join("");
            var rgb = parseInt(hex, 16);
            var luminance = 0.299 * ((rgb >> 16) & 255) + 0.587 * ((rgb >> 8) & 255) + 0.114 * (rgb & 255);
            return luminance > 150 ? "#111" : "#fff";
        };
        // Update the navbar directly.  Its template deliberately has no
        // Knockout bindings so this plugin cannot interfere with OctoPrint's
        // login/user menu binding context.
        self.updateNavbar = function (colour, flashing, title) {
            $("#ps3-manual-colour-navbar-bulb")
                .css({"background-color": colour || "#777", "color": colour || "#777"})
                .toggleClass("is-flashing", !!flashing)
                .attr("title", title || "No manual colour change in progress");
            $("#ps3-manual-colour-navbar-now")
                .text(self.activeLabel())
                .css({backgroundColor: colour || "#777", color: self.textForSwatch(colour)})
                .toggleClass("is-flashing", !!flashing)
                .attr("title", title || "Sent-command colour indicator");
            var strip = $("#ps3-manual-colour-navbar-slots").empty();
            self.fileColours().forEach(function (slot) {
                if (slot.unused) return; // Full palette stays in the tab, not the navbar.
                $("<span>").addClass("ps3-manual-colour-slot")
                    .toggleClass("is-flashing", slot.flashing)
                    .toggleClass("is-current", slot.current)
                    .toggleClass("is-unused", slot.unused)
                    .css({backgroundColor: slot.swatch, color: slot.textColour})
                    .attr("title", slot.title).text(slot.label).appendTo(strip);
            });
        };
        self.applyState = function (data) {
            if (!data) return;
            self.initialColour(self.colourName(data.initial_colour || "Initial filament"));
            var used = data.used_colours || [];
            if (!used.length) {
                var seen = {};
                [data.initial_colour].concat((data.schedule || []).map(function (s) { return s.colour; })).forEach(function (c) {
                    if (c && !seen[c.toLowerCase()]) { seen[c.toLowerCase()] = true; used.push({colour: c}); }
                });
            }
            self.usedColours(used.map(function (c) { return {label: self.colourName(c.label || c.colour), swatch: self.swatchFor(c.colour)}; }));
            var upcoming = (data.schedule || [])[data.current_change || 0];
            self.nextColour(self.colourName(data.next_colour || (upcoming && upcoming.colour) || "None"));
            var requestedColour = ((data.schedule || [])[Math.max(0, (data.current_change || 1) - 1)] || {}).colour;
            var activeColour = data.waiting_for_change ? requestedColour : (data.loaded_colour || data.initial_colour);
            var palette = data.file_colours && data.file_colours.length ? data.file_colours : used;
            var matches = palette.filter(function (slot) {
                return slot.used !== false && ((slot.colour || "").toLowerCase() === (activeColour || "").toLowerCase() ||
                    self.colourName(slot.label || slot.colour).toLowerCase() === self.colourName(activeColour).toLowerCase());
            });
            var usedMatches = matches.filter(function (slot) { return slot.used !== false; });
            if (usedMatches.length) matches = usedMatches;
            // Do not guess between identically labelled slots. Highlight only
            // when the file identifies a unique match for the requested colour.
            var selected = matches.length === 1 ? matches[0] : null;
            self.fileColours(palette.map(function (slot, index) {
                var current = slot === selected;
                var swatch = self.swatchFor(slot.colour);
                var label = self.colourName(slot.label || slot.colour);
                return {label: label, swatch: swatch, textColour: self.textForSwatch(swatch), current: current, unused: slot.used === false,
                    flashing: current && (!!data.print_active || !!data.waiting_for_change),
                    title: label + (slot.used === false ? " — Not used in this print" : "") + (current ? (data.waiting_for_change ? " — Load (M600 sent)" : " — Current (sent-command tracking)") : "")};
            }));
            self.bulbColour(self.swatchFor(selected ? selected.colour : activeColour));
            self.activeTextColour(self.textForSwatch(self.bulbColour()));
            self.activeLabel(activeColour ? ((data.waiting_for_change ? "LOAD: " : (data.print_active ? "PRINTING: " : "READY: ")) + self.colourName(activeColour)) : "NO FILE");
            self.bulbFlashing(!!data.waiting_for_change || !!data.print_active);
            self.bulbTitle(data.waiting_for_change ? ("LOAD " + self.colourName(activeColour) + " — M600 sent; parking not confirmed") : "Colour follows sent commands, not verified physical completion");
            self.currentChange(data.current_change || 0);
            self.profileDetected(!!data.profile_detected);
            var changeItems = (data.schedule || []).map(function (item) {
                var z = item.z === null || item.z === undefined ? "" : " / Z " + Number(item.z).toFixed(2) + " mm";
                var state = item.number < self.currentChange() ? "Done" : (item.number === self.currentChange() ? "Change now" : "Upcoming");
                return {number: item.number + 1, changeNumber: item.number, colour: self.colourName(item.colour), layerText: "Layer " + item.layer + z, status: state, swatch: self.swatchFor(item.colour)};
            });
            var initial = self.initialColour();
            var items = [{number: 1, changeNumber: 0, colour: initial, layerText: "Start / Layer 1", status: self.currentChange() ? "Started" : "Loaded at start", swatch: self.swatchFor(data.initial_colour)}].concat(changeItems);
            self.schedule(items);
            var rawSchedule = data.schedule || [];
            var reached = data.current_change || 0;
            var currentLayer = reached > 0 && rawSchedule[reached - 1] ? rawSchedule[reached - 1].layer : 1;
            var requested = data.waiting_for_change && reached > 0 ? rawSchedule[reached - 1] : null;
            var rows = (data.layer_colours || []).slice().reverse().map(function (row) {
                var colours = (row.colours || []).map(function (colour, index) {
                    var swatch = self.swatchFor(colour);
                    var segmentNumber = index + 1;
                    return {
                        colour: self.colourName(colour),
                        swatch: swatch,
                        textColour: self.textForSwatch(swatch),
                        active: row.layer === data.active_layer && segmentNumber === data.active_segment,
                        requested: !!requested && row.layer === requested.layer && colour.toLowerCase() === (requested.colour || "").toLowerCase(),
                        title: "Layer " + row.layer + " — " + segmentNumber + ": " + self.colourName(colour) + " (" + colour + ")"
                    };
                });
                var hasChange = colours.length > 1 || rawSchedule.some(function (event) { return event.layer === row.layer; });
                return {layer: row.layer, label: "L" + row.layer, colours: colours, singleColour: !hasChange, current: row.layer === (data.active_layer || currentLayer)};
            });
            self.layerRows(rows);
            var namedActive = self.colourName(activeColour);
            self.tabStatus(changeItems.length ?
                ((data.waiting_for_change ? "Load: " : "Current: ") + namedActive +
                 " | Next: " + self.nextColour() + " | Change " + self.currentChange() + " of " + changeItems.length) :
                ("Initial filament: " + initial + ". No manual colour changes found in this print."));
            self.updateNavbar(self.bulbColour(), self.bulbFlashing(), data.waiting_for_change ? ("LOAD " + namedActive + " (M600 sent)") : ("Current: " + namedActive));
        };
        self.loadState = function () { $.get(API_BASEURL + "plugin/manual_multicolor_ps3", function (data) { self.applyState(data); }); };
        self.onStartupComplete = function () { self.loadState(); };
        self.onTabChange = function (current, previous) { if (current === "#tab_plugin_manual_multicolor_ps3") self.loadState(); };
        self.onDataUpdaterPluginMessage = function (plugin, data) {
            if (plugin !== "manual_multicolor_ps3" || !data) return;
            if (data.action === "next") {
                self.colourStatus("Next: " + self.colourName(data.colour));
                self.colourDetail("The printer will pause to load " + self.colourName(data.colour) + ".");
                self.nextColour(self.colourName(data.colour));
            } else if (data.action === "prompt") {
                self.colourStatus("CHANGE: " + self.colourName(data.colour));
                self.colourDetail("Load " + self.colourName(data.colour) + " on the printer, then confirm on its screen.");
                self.bulbColour(self.swatchFor(data.colour));
                self.activeLabel("LOAD: " + self.colourName(data.colour));
                self.activeTextColour(self.textForSwatch(self.bulbColour()));
                self.bulbFlashing(true);
                self.bulbTitle("LOAD " + self.colourName(data.colour) + " — M600 sent; parking not confirmed");
                self.updateNavbar(self.bulbColour(), true, self.bulbTitle());
            } else if (data.action === "schedule" || data.action === "change" || data.action === "clear" || data.action === "resumed" || data.action === "segment") {
                self.applyState(data);
            }
        };
    }
    OCTOPRINT_VIEWMODELS.push({construct: ManualColourPromptsViewModel,
        dependencies: ["settingsViewModel", "loginStateViewModel", "printerStateViewModel", "accessViewModel", "pluginManagerViewModel"],
        optional: ["pluginManagerViewModel"], elements: ["#tab_plugin_manual_multicolor_ps3"]});
});
