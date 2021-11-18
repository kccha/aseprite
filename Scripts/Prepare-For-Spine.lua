--[[
Aseprite to Spine Exporter Script
Written by Jordan Bleu
https://github.com/jordanbleu/aseprite-to-spine
]]

-----------------------------------------------[[ Functions ]]-----------------------------------------------
--[[
Returns a flattened view of
the layers and groups of the sprite.
parent: The sprite or parent layer group
arr: The array to append to
]]
function getLayers(parent, arr)
    for i, layer in ipairs(parent.layers) do
        if (layer.isGroup) then
            arr[#arr + 1] = layer
            arr = getLayers(layer, arr)
        else
            arr[#arr + 1] = layer
        end
    end
    return arr
end

--[[
Checks for duplicate layer names, and returns true if any exist (also shows an error to the user)
layers: The flattened view of the sprite layers
]]
function containsDuplicates(layers)
    for i, layer in ipairs(layers) do
        if (layer.isVisible) then
            for j, otherLayer in ipairs(layers) do
                -- if we find a duplicate in the list that is not our index
                if (j ~= i) and (otherLayer.name == layer.name) and (otherLayer.isVisible) then
                    app.alert("Found multiple visible layers named '" .. layer.name .. "'.  Please use unique layer names or hide one of these layers.")
                    return true
                end
            end
        end
    end
    return false
end

--[[
Returns an array of each layer's visibility (true / false)
layers: the flattened view of the sprite layers
]]
function captureVisibilityStates(layers)
    local visibilities = {}
    for i, layer in ipairs(layers) do
        visibilities[i] = layer.isVisible
    end
    return visibilities
end

--[[
Hides all layers and groups
layers: The flattened view of the sprite layers
]]
function hideAllLayers(layers)
    for i, layer in ipairs(layers) do
        if (layer.isGroup) then
            layer.isVisible = true
        else
            layer.isVisible = false
        end
    end
end

local function contains (table, value)
    for _, item in ipairs(table) do
        if item == value then
            return true
        end
    end
    return false
end

local function addQuotes(value)
    return "\"" .. value .. "\""
end


local function calculatePNGName(spriteFileName, slotName, skinName, frameNumber)
    return spriteFileName .. "__" .. slotName .. "__" .. skinName .. "__" .. frameNumber
end

local function calculateAttachment(spriteFileName, slotName, skinName, pngName, width, height, frameNumber)
    return "              " ..  string.format([[ "%s": { "name": "%s", "y" : 16, "width": %d, "height": %d }]], slotName .. frameNumber, pngName, width, height)
end

local function processGroupLayer(layers, skinData, skinsJson, index, slotName, sprite)
    local outputDir = app.fs.filePath(sprite.filename)
    local spriteFileName = app.fs.fileTitle(sprite.filename)
    local separator = app.fs.pathSeparator
    for j, subLayer in ipairs(layers) do

        if (subLayer.isGroup) then
            index = processGroupLayer(subLayer.layers, skinData, skinsJson, index, slotName, sprite)
            goto subcontinue
        end


        local skinNameStart = string.find(subLayer.name, "%][^%]]*$")
        if (not skinNameStart) then
            goto subcontinue
        end

        local skinName = string.sub(subLayer.name, skinNameStart + 1)
        if (not skinData[skinName]) then
            skinData[skinName] = {}
        end


        local curSkinJson = "{\n"
        curSkinJson = curSkinJson .. "  \"name\": " .. addQuotes(skinName) .. ",\n"
        curSkinJson = curSkinJson .. "  \"attachments\": {\n"
        curSkinJson = curSkinJson .. "      " .. addQuotes(slotName) .. ": {\n"
        local attachments = {}
        local attachmentFrameIdx = 1
        local lastFrameNumber = 1
        local attachmentData = {}
        -- local attachmentDataIdx = 1

        for celIdx, curCel in ipairs(subLayer.celsNoDuplicates) do
            while attachmentFrameIdx < curCel.frameNumber do
                local pngName = calculatePNGName(spriteFileName, slotName, skinName, lastFrameNumber)
                attachments[attachmentFrameIdx] = calculateAttachment(spriteFileName, slotName, skinName, pngName, sprite.bounds.width, sprite.bounds.height, attachmentFrameIdx)
                attachmentData[attachmentFrameIdx]= { slotName, pngName, attachmentFrameIdx }

                attachmentFrameIdx = attachmentFrameIdx + 1
            end


            local pngName = spriteFileName .. "__" .. slotName .. "__" .. skinName .. "__" .. curCel.frameNumber
            attachments[attachmentFrameIdx] = calculateAttachment(spriteFileName, slotName, skinName, pngName, sprite.bounds.width, sprite.bounds.height, curCel.frameNumber)
            attachmentData[attachmentFrameIdx]= { slotName, pngName, attachmentFrameIdx }
            attachmentFrameIdx = attachmentFrameIdx + 1

            lastFrameNumber = curCel.frameNumber

            local pngPath = outputDir .. separator .. "images" .. separator .. pngName .. ".png"
            -- print(pngPath)
            subLayer.isVisible = true
            sprite:saveCopyAsSpecificFrames(pngPath, curCel.frameNumber, curCel.frameNumber)
            subLayer.isVisible = false
        end

        while attachmentFrameIdx <= #sprite.frames do
            local pngName = calculatePNGName(spriteFileName, slotName, skinName, lastFrameNumber)
            attachments[attachmentFrameIdx] = calculateAttachment(spriteFileName, slotName, skinName, pngName, sprite.bounds.width, sprite.bounds.height, attachmentFrameIdx)
            attachmentData[attachmentFrameIdx]= { slotName, pngName, attachmentFrameIdx }
            attachmentFrameIdx = attachmentFrameIdx + 1
        end

        skinData[skinName][slotName] = attachmentData

        curSkinJson = curSkinJson .. table.concat(attachments, ",\n")
        curSkinJson = curSkinJson .. "\n      }\n"
        curSkinJson = curSkinJson .. "  }\n"
        curSkinJson = curSkinJson .. "}\n"

        skinsJson[index] = curSkinJson
        index = index + 1
        ::subcontinue::
    end

    return index
end


--[[
Captures each layer as a separate PNG.  Ignores hidden layers.
layers: The flattened view of the sprite layers
sprite: The active sprite
outputDir: the directory the sprite is saved in
visibilityStates: the prior state of each layer's visibility (true / false)
]]
function captureLayers(layers, sprite, visibilityStates)
    hideAllLayers(layers)

    local outputDir = app.fs.filePath(sprite.filename)
    local spriteFileName = app.fs.fileTitle(sprite.filename)

    local jsonFileName = outputDir .. app.fs.pathSeparator .. spriteFileName .. ".json"
    json = io.open(jsonFileName, "w")

    json:write('{')

    -- skeleton
    json:write([[ "skeleton": { "images": "images/" }, ]])


    -- build arrays of json properties for skins and slots
    -- we only include layers, not groups
    local bonesJson = {}
    local slotsJson = {}
    local skinsJson = {}
    local index = 1
    local boneIdx = 1
    local slotIdx = 1
    bonesJson[boneIdx] = string.format([[ { "name": "root"}]])
    boneIdx = boneIdx + 1

    local directionVariations = {}
    if (string.match(spriteFileName, "_SE") and string.match(spriteFileName, "_NE")) then
        directionVariations[1] = "_SE"
        directionVariations[2] = "_NE"
    elseif (string.match(spriteFileName, "_SE")) then
        directionVariations[1] = "_SE"
    elseif (string.match(spriteFileName, "_NE")) then
        directionVariations[1] = "_NE"
    end
    
    
    local separator = app.fs.pathSeparator
    
    local layerCels = {}

    local skinData = {}
    local skinDirections = {}
    for i, layer in ipairs(layers) do
        if (not layer.isGroup) then
            goto continue
        end

        if (string.match(layer.name, "%[ignore%]")) then
            goto continue
        end

        local slotName = string.match(layer.name, "%[slot%](%a+)")
        if (not slotName) then
            goto continue
        end

        bonesJson[boneIdx] = string.format([[ { "name": "%s", "parent": "root"}]], slotName)
        boneIdx = boneIdx + 1

        slotsJson[slotIdx] = string.format([[ { "name": "%s", "bone": "%s"}]], slotName, slotName)
        slotIdx = slotIdx + 1

        index = processGroupLayer(layer.layers, skinData, skinsJson, index, slotName, sprite)
        -- -- print(slotName)
        -- for j, subLayer in ipairs(layer.layers) do

        --     local skinNameStart = string.find(subLayer.name, "%][^%]]*$")
        --     if (not skinNameStart) then
        --         goto subcontinue
        --     end

        --     local skinName = string.sub(subLayer.name, skinNameStart + 1)
        --     if (not skinData[skinName]) then
        --         skinData[skinName] = {}
        --     end


        --     local curSkinJson = "{\n"
        --     curSkinJson = curSkinJson .. "  \"name\": " .. addQuotes(skinName) .. ",\n"
        --     curSkinJson = curSkinJson .. "  \"attachments\": {\n"
        --     curSkinJson = curSkinJson .. "      " .. addQuotes(slotName) .. ": {\n"
        --     local attachments = {}
        --     local attachmentFrameIdx = 1
        --     local lastFrameNumber = 1
        --     local attachmentData = {}
        --     -- local attachmentDataIdx = 1

        --     for celIdx, curCel in ipairs(subLayer.celsNoDuplicates) do
        --         while attachmentFrameIdx < curCel.frameNumber do
        --             local pngName = calculatePNGName(spriteFileName, slotName, skinName, lastFrameNumber)
        --             attachments[attachmentFrameIdx] = calculateAttachment(spriteFileName, slotName, skinName, pngName, sprite.bounds.width, sprite.bounds.height, attachmentFrameIdx)
        --             attachmentData[attachmentFrameIdx]= { slotName, pngName, attachmentFrameIdx }

        --             attachmentFrameIdx = attachmentFrameIdx + 1
        --         end


        --         local pngName = spriteFileName .. "__" .. slotName .. "__" .. skinName .. "__" .. curCel.frameNumber
        --         attachments[attachmentFrameIdx] = calculateAttachment(spriteFileName, slotName, skinName, pngName, sprite.bounds.width, sprite.bounds.height, curCel.frameNumber)
        --         attachmentData[attachmentFrameIdx]= { slotName, pngName, attachmentFrameIdx }
        --         attachmentFrameIdx = attachmentFrameIdx + 1

        --         lastFrameNumber = curCel.frameNumber

        --         local pngPath = outputDir .. separator .. "images" .. separator .. pngName .. ".png"
        --         -- print(pngPath)
        --         subLayer.isVisible = true
        --         sprite:saveCopyAsSpecificFrames(pngPath, curCel.frameNumber, curCel.frameNumber)
        --         subLayer.isVisible = false
        --     end

        --     while attachmentFrameIdx <= #sprite.frames do
        --         local pngName = calculatePNGName(spriteFileName, slotName, skinName, lastFrameNumber)
        --         attachments[attachmentFrameIdx] = calculateAttachment(spriteFileName, slotName, skinName, pngName, sprite.bounds.width, sprite.bounds.height, attachmentFrameIdx)
        --         attachmentData[attachmentFrameIdx]= { slotName, pngName, attachmentFrameIdx }
        --         attachmentFrameIdx = attachmentFrameIdx + 1
        --     end

        --     -- if (not skinDirections[skinName]) then
        --     --     local directions = calculateDirections(subLayer.name)
        --     --     skinDirections[skinName] = directions
        --     -- end

        --     skinData[skinName][slotName] = attachmentData

        --     curSkinJson = curSkinJson .. table.concat(attachments, ",\n")
        --     curSkinJson = curSkinJson .. "\n      }\n"
        --     curSkinJson = curSkinJson .. "  }\n"
        --     curSkinJson = curSkinJson .. "}\n"

        --     skinsJson[index] = curSkinJson
        --     index = index + 1
        --     ::subcontinue::
        -- end

        ::continue::


    end

    -- bones
    -- json:write([[ "bones": [ { "name": "root" }	], ]])
    json:write('"bones": [\n')
    json:write(table.concat(bonesJson, ",\n"))
    json:write("\n],\n")
    -- slots
    json:write('"slots": [\n')
    json:write(table.concat(slotsJson, ",\n"))
    json:write("\n],\n")

    -- skins
    json:write('"skins": [')
    -- json:write('"default": {')
    json:write(table.concat(skinsJson, ","))
    json:write('\n]')

    -- json:write('"other-skins": [')
    -- -- json:write('"default": {')
    -- local skinStrings = {}
    -- for skinName, slotData in pairs(skinData) do
    --     local slotStrings = {}
    --     local skinDirections = skinDirections
    --     for slotName, attachmentData in pairs(slotData) do
    --         local attachmentStrings = {}
    --         for attachmentIdx, attachmentData in pairs(attachmentData) do
    --             local attachmentStr = calculateAttachment(spriteFileName, slotName, skinName, attachmentData[2], sprite.bounds.width, sprite.bounds.height, attachmentData[3])
    --             table.insert(attachmentStrings, attachmentStr)
    --         end
    --         local curSlotString = string.format([[        "%s": {]], slotName) .. "\n"
    --         curSlotString = curSlotString .. "  " .. table.concat(attachmentStrings, ",\n")
    --         curSlotString = curSlotString .. "\n      }" 
    --         table.insert(slotStrings, curSlotString)
    --     end
    --     local skinString = "{\n" .. string.format([[  "name": "%s",]], skinName) .. "\n"
    --     skinString = skinString .. '  "attachments": { \n'
    --     skinString = skinString .. table.concat(slotStrings, ",\n")
    --     skinString = skinString .. "\n}"
    --     skinString = skinString .. "\n}"
    --     table.insert(skinStrings, skinString)
    -- end

    -- json:write(table.concat(skinStrings, ",\n"))
    -- json:write('\n]')

    -- close the json
    json:write("}")

    json:close()

    app.alert("Export completed!  Use file '" .. jsonFileName .. "' for importing into Spine.")
end

--[[
Restores layers to their previous visibility state
layers: The flattened view of the sprite layers
visibilityStates: the prior state of each layer's visibility (true / false)
]]
function restoreVisibilities(layers, visibilityStates)
    for i, layer in ipairs(layers) do
        layer.isVisible = visibilityStates[i]
    end
end

-----------------------------------------------[[ Main Execution ]]-----------------------------------------------
local activeSprite = app.activeSprite


-- print("----------New Run----------------")
if (activeSprite == nil) then
    -- If user has no active sprite selected in the UI
    app.alert("Please click the sprite you'd like to export")
    return
elseif (activeSprite.filename == "") then
    -- If the user has created a sprite, but never saved it
    app.alert("Please save the current sprite before running this script")
    return
end

local flattenedLayers = getLayers(activeSprite, {})

-- if (containsDuplicates(flattenedLayers)) then
--     return
-- end

-- Get an array containing each layer index and whether it is currently visible
local visibilities = captureVisibilityStates(flattenedLayers)

-- Saves each sprite layer as a separate .png under the 'images' subdirectory
-- and write out the json file for importing into spine.
captureLayers(flattenedLayers, activeSprite, visibilities)

-- Restore the layer's visibilities to how they were before
restoreVisibilities(flattenedLayers, visibilities)