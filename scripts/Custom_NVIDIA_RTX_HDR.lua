-- Always keeps d3d11vpp=nvidia-true-hdr at the end of the vf chain
local function fix_truehdr_position()
    local vf = mp.get_property_native("vf")
    if not vf or #vf == 0 then return end
    
    local hdr_filter = nil
    local hdr_index = nil
    
    -- Find the truehdr filter
    for i, f in ipairs(vf) do
        if f.name == "d3d11vpp" and f.params and f.params["nvidia-true-hdr"] == "" then
            hdr_filter = f
            hdr_index = i
        end
    end
    
    -- If found and not already last, move it to end
    if hdr_filter and hdr_index ~= #vf then
        table.remove(vf, hdr_index)
        table.insert(vf, hdr_filter)
        mp.set_property_native("vf", vf)
    end
end

-- Watch for any vf changes
mp.observe_property("vf", "native", fix_truehdr_position)