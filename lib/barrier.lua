-- Functions related to barriers

local tags = require('tags')

module('barrier')

-- Checks if a node is a barrier applicable for the mode of transport.
-- First checks for any access tags, if they are they, their value is
-- applied. If not, checks for barriers and filters the ones given.
--
-- access_list - list of access tags appicable, from most to least
--               specific
-- barriers - table, mapping applicable barriers to access booelans
--            (default is false, so giving accessible ones will do)
function set_bollard(node, access_list, barriers)
	local acgrade = tags.get_access_grade(node.tags, access_list)

    if acgrade == 0 then
        local barrier = node.tags:Find ("barrier")
        if barrier ~= "" then
            if barriers[barrier] ~= nil then
                node.bollard = not barriers[barrier]
            else
                node.bollard = true
            end
        else
            node.bollard = false
        end
    else
        node.bollard = (acgrade < 0)
    end
end
