info = {
    id = "audit_setup",
    type = "project.plugin",
    title = "Manual Multicolor - Audit setup",
    menu = "Manual Multicolor/Audit setup"
}

local function read(config, name)
    local ok, value = pcall(function()
        return config:value(name)
    end)
    if ok then
        return value
    end
    return nil
end

local function count_material_slots(bed)
    local count = 0
    for slot = 0, 31 do
        local ok = pcall(function()
            bed:material_presets(slot)
        end)
        if not ok then
            break
        end
        count = count + 1
    end
    return count
end

local function report(name, actual, expected)
    local good = actual == expected
    print((good and "PASS " or "FAIL ") .. name .. ": " .. tostring(actual))
    return good
end

function execute(opts)
    local bed = api.project:current_bed()
    assert(bed ~= nil, "Manual Multicolor: no selected bed")

    local hardware = bed:printer_config()
    local printer = bed:printer_presets()
    local printing = bed:print_presets()
    local slots = count_material_slots(bed)
    local passed = true

    print("=== Manual Multicolor / setup audit ===")
    print("Printer configuration: " .. tostring(hardware.name))
    print("Physical tool count: " .. tostring(hardware.tool_count))
    passed = report("Material slots >= 3", slots >= 3, true) and passed
    passed = report("Single Extruder Multi Material", read(printer, "single_extruder_multi_material"), true) and passed
    passed = report("Binary G-code", read(printer, "binary_gcode"), false) and passed
    passed = report("Wipe tower", read(printing, "wipe_tower"), false) and passed
    passed = report("MMU priming", read(printing, "single_extruder_multi_material_priming"), false) and passed

    local toolchange = read(printer, "toolchange_gcode")
    local marker_ok = type(toolchange) == "string" and
        string.find(toolchange, "MANUAL_COLOUR_TOOLCHANGE", 1, true) ~= nil and
        string.find(toolchange, "M600", 1, true) ~= nil
    passed = report("Manual tool-change marker and M600", marker_ok, true) and passed

    print("Material slot count: " .. tostring(slots))
    print(passed and "AUDIT RESULT: READY" or "AUDIT RESULT: NOT READY")
    if not passed then
        print("Load manual-multicolor-config.json with launch-manual-multicolor.cmd, then audit again.")
    end
end
