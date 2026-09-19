info = {
    id = "inspect_project",
    type = "project.plugin",
    title = "Manual Multicolor - Inspect current project",
    menu = "Manual Multicolor/Inspect current project"
}

local function safe_value(config, name)
    local ok, value = pcall(function()
        return config:value(name)
    end)
    if ok then
        return value
    end
    return "<unavailable>"
end

function execute(opts)
    local bed = api.project:current_bed()
    assert(bed ~= nil, "Manual Multicolor: no current bed is selected")

    local hardware = bed:printer_config()
    local printer = bed:printer_presets()
    local print_settings = bed:print_presets()

    print("=== Manual Multicolor / project inspection ===")
    print("Printer: " .. tostring(hardware.name))
    print("Hardware tool count: " .. tostring(hardware.tool_count))
    print("G-code flavor: " .. tostring(safe_value(printer, "gcode_flavor")))
    print("Single-extruder MM: " .. tostring(safe_value(printer, "single_extruder_multi_material")))
    print("Layer height: " .. tostring(safe_value(print_settings, "layer_height")))
    print("Wipe tower: " .. tostring(safe_value(print_settings, "wipe_tower")))

    local material_slot_count = 0
    for slot_index = 0, 31 do
        local ok, material = pcall(function()
            return bed:material_presets(slot_index)
        end)
        if not ok then
            break
        end
        material_slot_count = material_slot_count + 1
        print(
            "Material slot " .. tostring(slot_index + 1) ..
            " type: " .. tostring(safe_value(material, "filament_type")) ..
            ", colour: " .. tostring(safe_value(material, "filament_colour"))
        )
    end
    print("Material slot count: " .. tostring(material_slot_count))

    for tool_index = 0, hardware.tool_count - 1 do
        local tool = hardware.tools[tool_index + 1]
        local nozzle = tool and tool.nozzle_diameter or nil
        print("Tool " .. tostring(tool_index) .. " nozzle: " .. tostring(nozzle))
    end

    print("Inspection complete; no project data was modified.")
end
