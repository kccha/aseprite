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

local function addQuotes(value)
    return "\"" .. value .. "\""
end

local function calculatePNGName(spriteFileName, slotName, skinName, frameNumber)
    return spriteFileName .. "__" .. slotName .. "__" .. skinName .. "__" .. frameNumber
end

local function calculateAttachment(spriteFileName, slotName, skinName, pngName, width, height, frameNumber)
    return "              " ..  string.format([[ "%s": { "name": "%s", "y" : 16, "width": %d, "height": %d }]], slotName .. frameNumber, pngName, width, height)
end

local function gatherSlotLayer(output, layer, sprite, skinName, directionName, slotName)
    local attachments = {}
    local attachmentFrameIdx = 1
    local lastFrameNumber = 1
    local lastPngName = ""
    local attachmentData = {}
    local spriteFileName = app.fs.fileTitle(sprite.filename)

    for celIdx, curCel in ipairs(layer.celsNoDuplicates) do
        while attachmentFrameIdx < curCel.frameNumber do
            local pngName = lastPngName
            attachmentData[attachmentFrameIdx] = { slotName=slotName, pngName=pngName, frameIdx=lastFrameNumber, layer=layer, requiresPNGSave=false}
            attachmentFrameIdx = attachmentFrameIdx + 1
        end


        local pngName = spriteFileName .. "__" .. slotName .. "__" .. skinName .. "__"  .. directionName .. "__" .. curCel.frameNumber
        attachmentData[attachmentFrameIdx] = { slotName=slotName, pngName=pngName, frameIdx=curCel.frameNumber, layer=layer, requiresPNGSave=true}
        attachmentFrameIdx = attachmentFrameIdx + 1
        lastPngName = pngName

        lastFrameNumber = curCel.frameNumber

        -- local pngPath = outputDir .. separator .. "images" .. separator .. pngName .. ".png"
        -- -- print(pngPath)
        -- subLayer.isVisible = true
        -- sprite:saveCopyAsSpecificFrames(pngPath, curCel.frameNumber, curCel.frameNumber)
        -- subLayer.isVisible = false
    end

    while attachmentFrameIdx <= #sprite.frames do
        local pngName = lastPngName
        attachmentData[attachmentFrameIdx] = { slotName=slotName, pngName=pngName, frameIdx=lastFrameNumber, layer=layer, requiresPNGSave=false}
        attachmentFrameIdx = attachmentFrameIdx + 1
    end
    -- for i, attachData in ipairs(attachmentData) do
    --     print(attachData.pngName .. "frame:" .. attachData.attachFrameIdx)
    -- end

    return attachmentData
end

local function gatherDirectionLayer(output, layers, sprite, skinName, directionName)
    local directionData = {}
    for i, layer in ipairs(layers) do

        local slotName = string.match(layer.name, "%](%w+)$")
        if (not slotName) then
            goto dircontinue
        end

        local refName = string.match(layer.name, "%[ref:(%w+)%]")
        if (refName) then
            print("Have reference: " .. refName)
        end

        if (directionData[slotName]) then
            print(string.format([[ Has duplicate slot(%s) for skin(%s) direction(%s) ]], slotName, skinName, directionName))
            goto dircontinue
        end

        local attachmentData = gatherSlotLayer(output, layer, sprite, skinName, directionName, slotName)

        directionData[slotName] = attachmentData
        ::dircontinue::
    end

    return directionData
end

local function gatherSkinLayer(output, layers, sprite, skinName)
    local skinData = {}
    for i, layer in ipairs(layers) do
        if (not layer.isGroup) then
            goto skincontinue
        end

        local directionName = string.match(layer.name, "%[dir%](%a+)")
        if (not directionName) then
            goto skincontinue
        end
        if (skinData[directionName]) then
            print(string.format([[ Has duplicate direction(%s) for skin(%s) ]], directionName, skinName))
            goto skincontinue
        end

        local directionData = gatherDirectionLayer(output, layer.layers, sprite, skinName, directionName)
        skinData[directionName] = directionData
        ::skincontinue::
    end

    return skinData
end
local function gatherAllSlots(skelData)
    local slotData = {}
    local slotMap = {}
    for skinName, skinData in pairs(skelData) do
        for directionName, directionData in pairs(skinData) do

            for slotName, attachmentData in pairs(directionData) do
                if (not slotMap[slotName]) then
                    slotMap[slotName] = true
                    table.insert(slotData, slotName)
                end
            end
        end
    end

    return slotData
end
local function tabs(count)
    local str = ""
    for i = 1, count do
        str = str .. "  "
    end
    return str
end
local function calculateBonesJson(allSlots)
    local boneStrings = {}

	table.insert(boneStrings, tabs(1) .. '{ "name": "root" }')
    for i, slotName in ipairs(allSlots) do
        table.insert(boneStrings, tabs(1) .. string.format([[{ "name": "%s", "parent": "root"}]], slotName))
    end

    local finalBoneString = '"bones": [\n'
    finalBoneString = finalBoneString ..  table.concat(boneStrings, ",\n")
    finalBoneString = finalBoneString .. '\n]'

    return finalBoneString
end

local function calculateSlotJson(allSlots)
    local slotStrings = {}

    for i, slotName in ipairs(allSlots) do
        table.insert(slotStrings, tabs(1) .. string.format([[{ "name": "%s", "bone": "%s"}]], slotName, slotName))
    end

    local finalSlotString = '"slots": [\n'
    finalSlotString = finalSlotString ..  table.concat(slotStrings, ",\n")
    finalSlotString = finalSlotString .. '\n]'

    return finalSlotString
end

local function calculateSkinSlotJson(sprite, skinName, directionName, slotName, attachmentData)
    local attachmentStrings = {}
    for attachmentIdx, curAttachmentData in ipairs(attachmentData) do

        local curString = tabs(4) .. string.format([["%s%d": { "name": "%s", "y": %d, "width": %d, "height": %d}]], slotName, attachmentIdx, curAttachmentData["pngName"], sprite.bounds.height / 4, sprite.bounds.width, sprite.bounds.height)

        table.insert(attachmentStrings, curString)
    end

    local finalSlotString = tabs(3) .. string.format('"%s": {\n',  slotName)
    finalSlotString = finalSlotString ..  table.concat(attachmentStrings, ",\n")
    finalSlotString = finalSlotString .. '\n'
    finalSlotString = finalSlotString .. tabs(3) .. '}'
    -- print(finalSlotString)

    return finalSlotString

end

local function calculateSkinDirectionJson(sprite, skinName, directionName, directionData)
    local slotStrings = {}
    for slotName, attachmentData in pairs(directionData) do
        table.insert(slotStrings, calculateSkinSlotJson(sprite, skinName, directionName, slotName, attachmentData))
    end

    local finalDirSkinString = tabs(1) .. "{\n"
    finalDirSkinString = finalDirSkinString .. tabs(2) .. string.format('"name": "%s_%s",\n', skinName, directionName)
    finalDirSkinString = finalDirSkinString .. tabs(2) .. '"attachments": {\n'
    finalDirSkinString = finalDirSkinString .. table.concat(slotStrings, ",\n")
    finalDirSkinString = finalDirSkinString .. "\n"
    finalDirSkinString = finalDirSkinString .. tabs(2) .. '}\n'
    finalDirSkinString = finalDirSkinString .. tabs(1) .. '}'
    return finalDirSkinString
end

local function calculateSkinJson(sprite, skinName, skinData)
    local directionStrings = {}
    for directionName, directionData in pairs(skinData) do
        -- print(skinName .. "   " .. directionName)
        local dirSkinString = calculateSkinDirectionJson(sprite, skinName, directionName, directionData)
        table.insert(directionStrings, dirSkinString)
    end

    return directionStrings
end

local function calculateSkeletonSkinJson(sprite, skelData)
    local skinStrings = {}

    for skinName, skinData in pairs(skelData) do
        local curSkinStrings = calculateSkinJson(sprite, skinName, skinData)
        table.move(curSkinStrings, 1, #curSkinStrings, #skinStrings + 1, skinStrings)
    end

    local finalSkelSkinString = '"skins": [\n'
    finalSkelSkinString = finalSkelSkinString ..  table.concat(skinStrings, ",\n")
    finalSkelSkinString = finalSkelSkinString .. '\n]'

    return finalSkelSkinString
end

local function processJson(skelData, sprite)
    local outputDir = app.fs.filePath(sprite.filename)
    local spriteFileName = app.fs.fileTitle(sprite.filename)
    local jsonFileName = outputDir .. app.fs.pathSeparator .. spriteFileName .. ".json"
    local allSlots = gatherAllSlots(skelData)



    json = io.open(jsonFileName, "w")

    json:write('{\n')

    -- skeleton
    json:write([["skeleton": { "images": "images/" }, ]] .. "\n")

    local jsonCategories = {}
    table.insert(jsonCategories, calculateBonesJson(allSlots))
    table.insert(jsonCategories, calculateSlotJson(allSlots))
    table.insert(jsonCategories, calculateSkeletonSkinJson(sprite, skelData))
    json:write(table.concat(jsonCategories, ",\n"))

    -- close the json
    json:write("\n}")

    json:close()

    app.alert("Export completed!  Use file '" .. jsonFileName .. "' for importing into Spine.")
end

local function processSkinSlotSprite(sprite, skinName, directionName, slotName, attachmentData)
    local separator = app.fs.pathSeparator
    local outputDir = app.fs.filePath(sprite.filename)
    for attachmentIdx, curAttachmentData in ipairs(attachmentData) do
        if (not curAttachmentData.requiresPNGSave) then
        -- print(string.format('No PNG Save skinName(%s), dirName(%s), slotName(%s)', skinName, directionName, slotName))
            goto spritecontinue
        end

        -- print(string.format('Has PNG Save skinName(%s), dirName(%s), slotName(%s)', skinName, directionName, slotName))
        local pngPath = outputDir .. separator .. "images" .. separator .. curAttachmentData.pngName .. ".png"
        local curLayer = curAttachmentData["layer"]
        local curFrameNumber = curAttachmentData.attachFrameIdx
        curLayer.isVisible = true
        -- print(string.format('PNG Save skinName(%s), dirName(%s), slotName(%s), pngPath(%s), frameNumber(%d)', skinName, directionName, slotName, pngPath, frameNumber))
        --curLayer:saveCopyAsSpecificFrames(pngPath, curFrameNumber, curFrameNumber)
        curLayer.isVisible = false
        ::spritecontinue::
    end
end
local function processSkinDirectionSprite(sprite, skinName, directionName, directionData)
    for slotName, attachmentData in pairs(directionData) do
        processSkinSlotSprite(sprite, skinName, directionName, slotName, attachmentData)
    end
end

local function processSkinSprite(sprite, skinName, skinData)
    for directionName, directionData in pairs(skinData) do
        processSkinDirectionSprite(sprite, skinName, directionName, directionData)
    end
end

local function processSkeletonSkinSprite(sprite, skelData)
    local separator = app.fs.pathSeparator
    local outputDir = app.fs.filePath(sprite.filename)
    for skinName, skinData in pairs(skelData) do
        for directionName, directionData in pairs(skinData) do
            for slotName, attachmentData in pairs(directionData) do
                for i, attachData in ipairs(attachmentData) do
                    -- print(string.format('slotName(%s), layerName(%s), pngName(%s), frameIdx(%d)', attachData.slotName, attachData.layer.name, attachData.pngName, attachData.frameIdx))
                    -- print(attachData.layer.name ..  slotName .. "  ".. attachData.pngName .. "frame:" .. attachData.attachFrameIdx)
                    if (attachData.requiresPNGSave) then
                        -- print(string.format('No PNG Save skinName(%s), dirName(%s), slotName(%s)', skinName, directionName, slotName))
                        -- goto spritecontinue
                        local pngPath = outputDir .. separator .. "images" .. separator .. attachData.pngName .. ".png"
                        local curLayer = attachData.layer
                        local curFrameNumber = attachData.frameIdx
                        curLayer.isVisible = true
                        -- print(string.format('PNG Save skinName(%s), dirName(%s), slotName(%s), pngPath(%s), frameNumber(%d)', skinName, directionName, slotName, pngPath, frameNumber))
                        sprite:saveCopyAsSpecificFrames(pngPath, curFrameNumber, curFrameNumber)
                        curLayer.isVisible = false
                    end
                    -- print(string.format('Has PNG Save skinName(%s), dirName(%s), slotName(%s)', skinName, directionName, slotName))

                    -- ::spritecontinue::
                end
            end

            -- for slotName, attachmentData in pairs(directionData) do
            --     if (not slotMap[slotName]) then
            --         slotMap[slotName] = true
            --         table.insert(slotData, slotName)
            --     end
            -- end
        end
        -- processSkinSprite(sprite, skinName, skinData)
    end

end
local function processSprites(skelData, sprite)
    local outputDir = app.fs.filePath(sprite.filename)
    local spriteFileName = app.fs.fileTitle(sprite.filename)
    local jsonFileName = outputDir .. app.fs.pathSeparator .. spriteFileName .. ".json"

    processSkeletonSkinSprite(sprite, skelData)
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
    
    local separator = app.fs.pathSeparator
    
    local layerCels = {}

    local skinData = {}
    local skinDirections = {}
    local output = {}
    output["slot_names"] = {}
    skelData = {}
    for i, layer in ipairs(layers) do
        if (not layer.isGroup) then
            goto continue
        end

        if (string.match(layer.name, "%[ignore%]")) then
            goto continue
        end

        local skinName = string.match(layer.name, "%[skin%](%a+)")
        if (not skinName) then
            goto continue
        end

        if (skelData[skinName]) then
            print(string.format([[ Have duplicate skins(%s) ]], skinName))
            goto continue
        end
        local skinData = gatherSkinLayer(output, layer.layers, sprite, skinName)
        skelData[skinName] = skinData

        ::continue::
    end
    processJson(skelData, sprite)
    -- processSprites(skelData, sprite)

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