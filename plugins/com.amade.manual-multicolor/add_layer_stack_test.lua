info = {
    id = "add_layer_stack_test",
    type = "project.plugin",
    title = "Manual Multicolor - Add visual layer-stack test",
    menu = "Manual Multicolor/Add visual layer-stack test",
    params = {
        {name = "bottom_layers", label = "Multicolor bottom layers", type = "int", default = 2},
        {name = "top_layers", label = "Multicolor top layers", type = "int", default = 2},
        {name = "layer_height", label = "Layer height (mm)", type = "string", default = "0.20"}
    }
}

local function whole_number(value, name)
    local number = tonumber(value)
    assert(number ~= nil and number >= 0 and number == math.floor(number), name .. " must be a whole number")
    return number
end

local function material_slot_count(bed)
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

local function solid(mesh, x, z, extruder)
    return {
        mesh = mesh,
        type = VolumeType.Solid,
        translate = {x = x, z = z},
        params = {extruder = extruder}
    }
end

function execute(opts)
    local bottom_layers = whole_number(opts.bottom_layers, "Bottom layers")
    -- Fixed spacing for this generated sample only; real model height is independent.
    local body_layers = 6
    local top_layers = whole_number(opts.top_layers, "Top layers")
    local layer_height = tonumber(opts.layer_height)

    assert(layer_height ~= nil and layer_height > 0 and layer_height <= 1, "Layer height must be between 0 and 1 mm")
    assert(bottom_layers > 0 or top_layers > 0, "At least one multicolor zone is required")

    local bed = api.project:current_bed()
    assert(bed ~= nil, "Manual Multicolor: no selected bed")
    local slots = material_slot_count(bed)
    assert(slots >= 3, "This test requires at least three material slots; load the manual multicolor setup first")

    local width = 60
    local depth = 24
    local stripe_width = width / 3
    local bottom_height = bottom_layers * layer_height
    local body_height = body_layers * layer_height
    local top_height = top_layers * layer_height
    local top_z = bottom_height + body_height
    local volumes = {}

    if bottom_height > 0 then
        for stripe = 0, 2 do
            volumes[#volumes + 1] = solid(
                api.make_cube(stripe_width, depth, bottom_height),
                stripe * stripe_width,
                0,
                stripe + 1
            )
        end
    end

    if top_height > 0 then
        for stripe = 0, 2 do
            volumes[#volumes + 1] = solid(
                api.make_cube(stripe_width, depth, top_height),
                stripe * stripe_width,
                top_z,
                stripe + 1
            )
        end
    end

    api.project:add_object {
        mesh = api.make_cube(width, depth, body_height),
        translate = {z = bottom_height},
        params = {extruder = 1},
        other_volumes = volumes
    }

    print("Added native three-color layer-stack test")
    print("Bottom multicolor layers: " .. tostring(bottom_layers))
    print("Sample body spacing is automatic; real models determine their own middle-layer count.")
    print("Top multicolor layers: " .. tostring(top_layers))
    print("Layer height: " .. tostring(layer_height))
    print("Slice and select Preview by Tool to see each same-layer color region and transition.")
end
