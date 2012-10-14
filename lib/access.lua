local ipairs = ipairs

module("access")

-- access values
-- designated(2), yes(1), unknown(0), destination(-1), no(-2)

tag_values = { ["yes"] = 1, 
               ["permissive"] = 1, 
               ["designated"] = 2,
               ["no"] = -2, 
               ["private"] = -2, -- should be destination, once it is implemented
               ["agricultural"] = -2, 
               ["forestery"] = -2,
               ["destination"] = -1, 
               ["delivery"] = -1 
             }


--find first tag in access hierachy which is set
function find_access_tag(source, access_tags_hierachy)
    for i,v in ipairs(access_tags_hierachy) do
        local tag = source.tags:Find(v)
        if tag ~= '' then --and tag ~= "" then
            return tag
        end
    end
    return nil
end

-- convert access value into grade
function value_to_grade(value)
    if tag_values[value] == nil then
        return 0
    else
        return tag_values[value]
    end
end

--find first tag in access hierachy which is set
function find_access_grade(source, access_tags_hierachy)
    for i,v in ipairs(access_tags_hierachy) do
        local tag = source.tags:Find(v)
        if tag ~= '' then --and tag ~= "" then
            return value_to_grade(tag)
        end
    end
    return 0
end

