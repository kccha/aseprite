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

local function sep()
    return "_"
end
local function calculateSkinDirectionName(skinName, directionName)
    if (string.match(directionName, "None")) then
        return skinName
    end

    return skinName .. sep() .. directionName
end

local function calculatePNGName(spriteFileName, skinName, directionName, slotName, frameNumber)
    return spriteFileName .. sep() .. calculateSkinDirectionName(skinName, directionName) .. sep() .. slotName .. sep() .. frameNumber
end


local function isLayerCelEmpty(layer, frameIdx) 
    local curCel = layer:cel(frameIdx)
    if (not curCel) then
        return true
    end
    if (not curCel.image) then
        return true
    end

    return curCel.image:isEmpty()
end

local function gatherSlotLayer(layer, sprite, skinName, directionName, slotName)
    local attachments = {}
    local attachmentFrameIdx = 1
    local lastFrameNumber = 1
    local lastPngName = ""
    local attachmentData = {}
    local spriteFileName = app.fs.fileTitle(sprite.filename)

    for celIdx, curCel in ipairs(layer.celsNoDuplicates) do
        while attachmentFrameIdx < curCel.frameNumber do
            local pngName = lastPngName
            -- Skip empty cels
            if isLayerCelEmpty(layer, attachmentFrameIdx) then
                pngName = ""
            end
            attachmentData[attachmentFrameIdx] = { slotName=slotName, pngName=pngName, frameIdx=lastFrameNumber, layer=layer, directionName=directionName, requiresPNGSave=false}
            attachmentFrameIdx = attachmentFrameIdx + 1
        end

        local pngName = calculatePNGName(spriteFileName, skinName, directionName, slotName, curCel.frameNumber)
        -- Skip empty cels
        if isLayerCelEmpty(layer, attachmentFrameIdx) then
            pngName = ""
        end
        attachmentData[attachmentFrameIdx] = { slotName=slotName, pngName=pngName, frameIdx=curCel.frameNumber, layer=layer, directionName=directionName, requiresPNGSave=true}
        attachmentFrameIdx = attachmentFrameIdx + 1
        lastPngName = pngName
        lastFrameNumber = curCel.frameNumber
    end

    while attachmentFrameIdx <= #sprite.frames do
        local pngName = lastPngName
        -- Skip empty cels
        if isLayerCelEmpty(layer, attachmentFrameIdx) then
            pngName = ""
        end
        attachmentData[attachmentFrameIdx] = { slotName=slotName, pngName=pngName, frameIdx=lastFrameNumber, layer=layer, directionName=directionName, requiresPNGSave=false}
        attachmentFrameIdx = attachmentFrameIdx + 1
    end

    return attachmentData
end

local function gatherDirectionLayer(layers, sprite, skinName, directionName)
    local directionData = {}
    for i, layer in ipairs(layers) do

        local slotName = string.match(layer.name, "%](%w+)$")
        if (not slotName) then
            goto dircontinue
        end

        local dirRefName = string.match(layer.name, "%[dref:(%w+)%]")
        local slotRefName = string.match(layer.name, "%[sref:(%w+)%]")
        local flipX = string.match(layer.name, "%[flipx%]")
        if (directionData[slotName]) then
            print(string.format([[ Has duplicate slot(%s) for skin(%s) direction(%s) ]], slotName, skinName, directionName))
            goto dircontinue
        end

        local attachmentData = gatherSlotLayer(layer, sprite, skinName, directionName, slotName)

        directionData[slotName] = {attachData=attachmentData, dirRefName=dirRefName, slotRefName=slotRefName, flipX=flipX}
        ::dircontinue::
    end

    return directionData
end

local function gatherSkinLayer(layers, sprite, skinName)
    local skinData = {}
    for i, layer in ipairs(layers) do
        if (not layer.isGroup) then
            goto skincontinue
        end

        local directionName = string.match(layer.name, "%[dir%](%w+)")
        if (not directionName) then
            goto skincontinue
        end
        if (skinData[directionName]) then
            print(string.format([[ Has duplicate direction(%s) for skin(%s) ]], directionName, skinName))
            goto skincontinue
        end

        local directionData = gatherDirectionLayer(layer.layers, sprite, skinName, directionName)
        skinData[directionName] = directionData
        ::skincontinue::
    end

    return skinData
end

local function gatherSkeletonData(outSkelData, layers, sprite)
    for i, layer in ipairs(layers) do
        if (not layer.isGroup) then
            goto groupcontinue
        end

        if (string.match(layer.name, "%[ignore%]")) then
            goto groupcontinue
        end

        local skinName = string.match(layer.name, "%[skin%]([_%w]+)")
        if (not skinName) then
            goto groupcontinue
        end

        if (outSkelData[skinName]) then
            print(string.format([[ Have duplicate skins(%s) ]], skinName))
            goto groupcontinue
        end
        local skinData = gatherSkinLayer(layer.layers, sprite, skinName)
        outSkelData[skinName] = skinData

        ::groupcontinue::
    end
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


local function calculateAnimSlotDirectionName(spriteName, slotName, directionName)
    if (string.match(directionName, "None")) then
        return spriteName .. sep() .. slotName
    end

    return spriteName .. sep() .. slotName .. sep() .. directionName
end

local function calculateSkinSlotJson(sprite, skinName, directionName, slotName, flipX, attachmentData, type)
    local attachmentStrings = {}
    local spriteFileName = app.fs.fileTitle(sprite.filename)
    for attachmentIdx, curAttachmentData in ipairs(attachmentData) do

        if (not curAttachmentData.pngName or curAttachmentData.pngName == "") then
            goto skinslotjsoncontinue
        end
        local additionalData = ''
        if (flipX) then
            additionalData = additionalData .. ' "scaleX": -1, '
        end

        local yPos = 16
        local xPos = 0
        if (string.match(type, "weapon")) then
            xPos = -0.5
            yPos = 0.5
            if (flipX) then
                xPos = xPos * -1.0
            end
            if (flipY) then
                yPos = yPos * -1.0
            end
        elseif (string.match(type, "shield")) then
            xPos = 0
            yPos = 0
        end
        additionalData = additionalData .. string.format(' "x": %f, "y": %f, ', xPos, yPos)
        local curString = tabs(4) .. string.format([["%s%s%d": { "name": "%s",%s "width": %d, "height": %d}]], calculateAnimSlotDirectionName(spriteFileName, slotName, directionName), sep(), attachmentIdx, curAttachmentData.pngName, additionalData,  sprite.bounds.width, sprite.bounds.height)
        table.insert(attachmentStrings, curString)

        ::skinslotjsoncontinue::
    end

    local finalSlotString = tabs(3) .. string.format('"%s": {\n',  slotName)
    finalSlotString = finalSlotString ..  table.concat(attachmentStrings, ",\n")
    finalSlotString = finalSlotString .. '\n'
    finalSlotString = finalSlotString .. tabs(3) .. '}'

    return finalSlotString

end

local function calculateSkinDirectionJson(sprite, skinName, directionName, directionData, skinData, type)
    local slotStrings = {}
    for slotName, dirData in pairs(directionData) do
        local curDirectionData = directionData
        local curSlotName = slotName

        if (dirData.slotRefName) then
            curSlotName = dirData.slotRefName
        end

        if (dirData.dirRefName) then
            curDirectionData = skinData[dirData.dirRefName]
        end

        if (not curDirectionData) then
            print(string.format('Unable to find direction(%s) cannot replace reference', dirData.refName))
            curDirectionData = directionData
        end

        if (not curDirectionData[curSlotName]) then
            print(string.format('Unable to find direction(%s) with slot(%s) cannot replace reference', dirData.refName, curSlotName))
            curSlotName = slotName
            curDirectionData = directionData
        end

        local curAttachData = curDirectionData[curSlotName].attachData
        table.insert(slotStrings, calculateSkinSlotJson(sprite, skinName, directionName, slotName, dirData.flipX, curAttachData, type))
    end

    local finalDirSkinString = tabs(1) .. "{\n"
    finalDirSkinString = finalDirSkinString .. tabs(2) .. string.format('"name": "%s",\n', skinName)
    finalDirSkinString = finalDirSkinString .. tabs(2) .. '"attachments": {\n'
    finalDirSkinString = finalDirSkinString .. table.concat(slotStrings, ",\n")
    finalDirSkinString = finalDirSkinString .. "\n"
    finalDirSkinString = finalDirSkinString .. tabs(2) .. '}\n'
    finalDirSkinString = finalDirSkinString .. tabs(1) .. '}'
    return finalDirSkinString
end

local function calculateSkinJson(sprite, skinName, skinData, type)
    local directionStrings = {}
    for directionName, directionData in pairs(skinData) do
        local dirSkinString = calculateSkinDirectionJson(sprite, skinName, directionName, directionData, skinData, type)
        table.insert(directionStrings, dirSkinString)
    end

    return directionStrings
end

local function calculateSkeletonSkinJson(sprite, skelData, type)
    local skinStrings = {}

    for skinName, skinData in pairs(skelData) do
        local curSkinStrings = calculateSkinJson(sprite, skinName, skinData, type)
        table.move(curSkinStrings, 1, #curSkinStrings, #skinStrings + 1, skinStrings)
    end

    local finalSkelSkinString = '"skins": [\n'
    finalSkelSkinString = finalSkelSkinString ..  table.concat(skinStrings, ",\n")
    finalSkelSkinString = finalSkelSkinString .. '\n]'

    return finalSkelSkinString
end

local function processJson(skelData, sprite, type)
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
    table.insert(jsonCategories, calculateSkeletonSkinJson(sprite, skelData, type))
    json:write(table.concat(jsonCategories, ",\n"))

    -- close the json
    json:write("\n}")

    json:close()

    app.alert("Export completed!  Use file '" .. jsonFileName .. "' for importing into Spine.")
end

local function processSkeletonSkinSprite(sprite, skelData)
    local separator = app.fs.pathSeparator
    local outputDir = app.fs.filePath(sprite.filename)
    for skinName, skinData in pairs(skelData) do
        for directionName, directionData in pairs(skinData) do
            for slotName, dirData in pairs(directionData) do
                if (not dirData.dirRefName and not dirData.slotRefName) then
                    for i, attachData in ipairs(dirData.attachData) do
                        if (attachData.requiresPNGSave) then
                            local pngPath = outputDir .. separator .. "images" .. separator .. attachData.pngName .. ".png"
                            local curLayer = attachData.layer
                            local curFrameNumber = attachData.frameIdx
                            curLayer.isVisible = true
                            sprite:saveCopyAsSpecificFrames(pngPath, curFrameNumber, curFrameNumber)
                            curLayer.isVisible = false
                        end
                    end
                end
            end

        end
    end

end

local function processSprites(skelData, sprite)
    local outputDir = app.fs.filePath(sprite.filename)
    local spriteFileName = app.fs.fileTitle(sprite.filename)
    local jsonFileName = outputDir .. app.fs.pathSeparator .. spriteFileName .. ".json"

    processSkeletonSkinSprite(sprite, skelData)
end

local function calculateType(sprite)
    local spriteFileName = app.fs.fileTitle(sprite.filename)
    if (string.match(spriteFileName, "weapons")) then
        return "weapon"
    elseif (string.match(spriteFileName, "shields")) then
        return "shield"
    end
    return "standard"
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

    skelData = {}
    gatherSkeletonData(skelData, layers, sprite)

    processSprites(skelData, sprite)
    processJson(skelData, sprite, calculateType(sprite))
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
