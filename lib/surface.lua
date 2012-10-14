module("surface")

-- default surfaces for the different highway types
function get_surface(tags)
    local highway = tags:Find("highway")

    if (highway == "track") then
        local grade = tags:Find("tracktype")
        if grade == "grade1" then
            return "paved"
        elseif grade == "grade3" then
            return "gravel"
        elseif grade == "grade4" then
            return "ground"
        elseif grade == "grade5" then
            return "grass"
        else
            return "unpaved"
        end
    elseif highway == "path" then
        return "ground"
    end
    return "paved"
end
