-- @description CW_Media_Folder_import_tool(Chinese ver.)

-- @version 1.0
-- @author ChangoW
-- @changelog
--   Initial release of the script
-- @links
--   https://github.com/realChangoW/ReaScript
-- @donate https://paypal.me/realChangoW?country.x=C2&locale.x=zh_XC
-- @about This script is an audio file import tool for REAPER, designed to simplify batch importing and organizing audio files. It supports common audio formats and offers various import modes and options for efficient workflow management in music and post-production.
--   Features:
--     - Browse and select audio files/folders
--     - View detailed file information (sample rate, bitrate, duration, file size, file type)
--     - Manage import list (add files, adjust order, remove files)
--     - Flexible import options (vertical, diagonal, horizontal)
--     - Import units: Sample Item or Folder
--     - Additional options: relative paths for track names, folder structure-based track creation
--[[ 判断操作系统类型
    说明: 获取当前REAPER运行的操作系统类型
    REAPER的GetOS()函数可能返回以下值:
      - "Win32"、"Win64" 等Windows系统标识
      - "OSX32"、"OSX64"、"macOS" 等Mac系统标识
      - "Other" 通常表示Linux或其他系统
    返回值:
        string: "Windows"、"Mac"、"Linux" 或 "Unknown OS"
]]
function getOS()
    local os_name = reaper.GetOS()
    if os_name:match("Win") then
        return "Windows"
    elseif os_name:match("OSX") or os_name:match("macOS") then
        return "Mac"
    elseif os_name:match("Other") then
        return "Linux"
    else
        return "Unknown OS"
    end
end

local OSType = getOS()
-- reaper.ShowConsoleMsg("OSType: "..OSType)

-- Check if Lokasenna_GUI library is installed
local lib_path = reaper.GetResourcePath() .. '/Scripts/ReaTeam Scripts/Development/Lokasenna_GUI v2/Library/'
local core_path = lib_path .. 'Core.lua'
local info = debug.getinfo(1,'S')
script_path = info.source:match[[^@?(.*[\/])[^\/]-$]]

if not reaper.file_exists(core_path) then
    reaper.MB('This script requires the Lokasenna_GUI v2 library. Please install it via ReaPack: ReaTeam Extensions > "Script: Lokasenna_GUI v2".', 'Error', 0)
    return
end

loadfile(core_path)()
GUI.req("Classes/Class - Button.lua")()
GUI.req("Classes/Class - Listbox.lua")()
GUI.req("Classes/Class - Options.lua")()
GUI.req("Classes/Class - Textbox.lua")()
GUI.req("Classes/Class - TextEditor.lua")()
GUI.req("Classes/Class - Menubox.lua")()
GUI.req("Classes/Class - Menubar.lua")()
GUI.req("Classes/Class - Slider.lua")()
GUI.req("Classes/Class - Frame.lua")()
GUI.req("Classes/Class - Label.lua")()
------------------Value--------------------
local importPath = ""
local importList = {}
local readyImportList={}
local fileStringList = {"文件夹中的文件..."}
local readyImportStringList={"准备导入的列表..."}



-------------------Function----------------
--[[获取文件夹路径
    通过系统对话框选择文件夹
    返回值:
        string: 选中的文件夹路径
        nil: 如果用户取消选择或发生错误
]]
function getBottonPath()
    local errorCase,dialogGetPath = reaper.JS_Dialog_BrowseForFolder( caption, initialFolder)
    if errorCase == 0 then
        return nil
    elseif errorCase == -1 then
        return nil
    end
    if (dialogGetPath == nil) then
        return nil
    end
    return dialogGetPath
end

--[[获取第一个选中轨道的序号
    返回值:
        number: 选中轨道的序号(从1开始)
        0: 如果没有选中任何轨道
]]
function getFirstTrackID()
    local strack = reaper.GetSelectedTrack(0,0)
    if strack then
        --reaper.ShowConsoleMsg("pgy")
        local trackIndex = reaper.GetMediaTrackInfo_Value(strack, "IP_TRACKNUMBER")
        return trackIndex
    end
    return 0
end

--[[获取指定路径下的所有子目录
    参数:
        path: 要搜索的目录路径
    返回值:
        table: 包含所有子目录名称的数组
]]
function getSubdirInPath(path)
    local dirs = {}
    local i = 0
    while true do
        local tmpdirname = reaper.EnumerateSubdirectories(path, i)
        if not tmpdirname then  -- 检查是否为空
            break  -- 如果没有更多子目录，跳出循环
        end
        dirs[#dirs + 1] = tmpdirname  -- 更简洁的插入方式
        i = i + 1
    end
    return dirs
end

--[[获取指定目录下的所有文件
    参数:
        dir: 要搜索的目录路径
    返回值:
        table: 按自然排序的文件名数组
]]
function getAllFileInDir(dir)
    reaper.EnumerateFiles( dir, -1 )
    local filenames = {}
    local i = 0
    while true do
        local tmpfilename = reaper.EnumerateFiles(dir, i)
        if not tmpfilename then
            table.sort(filenames, naturalSort)
            return filenames
        end
        filenames[#filenames + 1] = tmpfilename
        i = i + 1
    end
end

--[[自然排序比较函数
    用于文件名的自然排序，使"2.wav"排在"10.wav"前面
    参数:
        a,b: 要比较的两个字符串
    返回值:
        boolean: a是否应该排在b前面
]]
function naturalSort(a, b)
    local function padnum(d) return ("%012d"):format(tonumber(d)) end
    return tostring(a):gsub("%d+", padnum) < tostring(b):gsub("%d+", padnum)
end
  
--[[
表结构说明:
ImportList 是一个数组,每个元素都是一个表,用于存储文件夹和文件的信息

文件夹元素结构: {0, 文件夹名, 相对路径, 0, 0, 绝对路径}
- 第1位: 0 表示这是一个文件夹
- 第2位: 文件夹名称
- 第3位: 相对于导入根目录的路径
- 第4-5位: 预留位,值为0
- 第6位: 文件夹的绝对路径

文件元素结构: {1, 文件名, 相对路径, 文件类型, 绝对路径}
- 第1位: 1 表示这是一个文件
- 第2位: 文件名
- 第3位: 相对于导入根目录的路径
- 第4位: 文件扩展名
- 第5位: 文件的绝对路径

示例:
文件夹: {0, "音乐", "\音乐", 0, 0, "E:\音乐"}
文件: {1, "track01.wav", "\音乐\", ".wav", "E:\音乐\track01.wav"}
]]
function getImportList(dir,ImportList)
    --local ImportList = {}
    
    local subDirList=getSubdirInPath(dir)
    local fileList=getAllFileInDir(dir)
    local Dirname = remove_prefix_path(dir,importPath)
    local export_path = "\\"..remove_prefix_path(dir,importPath)
    -------组合导入数据table
        --0文件夹,文件夹名,相对路径
        if Dirname==nil then
            Dirname = "\\"
        end
    local dirInfoElement={0,Dirname,export_path,0,0,dir}
    table.insert(ImportList,dirInfoElement)

    for index,filename in ipairs(fileList) do
        if is_valid_audio_extension(filename) then
            local filetype = getFileExtension(filename)
            local export_path = "\\"..remove_prefix_path(dir,importPath).."\\"
            --reaper.ShowConsoleMsg("remove_prefix_path(dir,importPath)"..remove_prefix_path(dir,importPath).."\n")
            --reaper.ShowConsoleMsg(filename..":"..export_path.."\n")
            -------组合导入数据table
            --1文件,文件名，相对路径,文件类型,绝对路径
            local fileInfoElement = {1,filename,export_path,filetype,dir.."\\"..filename}
            table.insert(ImportList, fileInfoElement)
        end
    end

    for i, v in ipairs(subDirList) do
        --继续处理子文件夹
        getImportList(dir.."\\"..v,ImportList)
    end
end

--[[执行音频文件导入
    参数:
        readyimportlist: 要导入的文件和文件夹列表
    说明: 遍历列表，对文件夹创建新轨道，对文件执行导入
]]
function startImport(readyimportlist)
    -- 获取当前选择的导入模式
    local importMode = GUI.Val("Import Directory")
    local importUnit = GUI.Val("unit of import")
    
    -- 记录初始轨道位置
    local initialPosition = reaper.GetCursorPosition()
    local lastTrackIndex = getFirstTrackID()
    local lastPath = ""
    
    for index, value in ipairs(readyimportlist) do
        local elemType = value[1]
        local elemname = value[2]
        local currentPath = value[3]
        
        -- 根据unit of import判断是否需要处理该元素
        if (importUnit == 1 and elemType == 1) or -- Sample Item模式下只处理文件
           (importUnit == 2 and elemType == 1) then -- Folder模式下只处理文件
            
            -- 根据Import Directory模式处理
            if importMode == 1 then -- Mixing模式
                if importUnit == 1 or -- Sample模式：每个文件都新建轨道
                   (importUnit == 2 and lastPath ~= "" and currentPath ~= lastPath) then -- Folder模式：路径变化时新建轨道
                    reaper.Main_OnCommand(40001, 0) -- 新建轨道
                    reaper.SetEditCurPos(initialPosition, true, false) -- 回到起始位置
                end
            elseif importMode == 2 then -- Checking模式
                if importUnit == 1 or -- Sample模式：每个文件都新建轨道
                   (importUnit == 2 and lastPath ~= "" and currentPath ~= lastPath) then -- Folder模式：路径变化时新建轨道
                    reaper.Main_OnCommand(40001, 0) -- 新建轨道
                end
                -- 不重置位置，自动接续
            elseif importMode == 3 then -- Line模式
                -- 不新建轨道，不重置位置
                if index == 1 then
                    reaper.Main_OnCommand(40001, 0) -- 仅第一次新建轨道
                end
            end
            
            -- 执行导入
            reaper.InsertMedia(value[5], 0)
            
            -- 更新上一个文件的路径
            lastPath = currentPath
        end
        
        -- 设置轨道名称
        if GUI.Val("use relative path as track name") == true then
            local currentTrack = reaper.GetSelectedTrack(0, 0)
            if currentTrack then
                reaper.GetSetMediaTrackInfo_String(currentTrack, "P_NAME", value[3], true)
            end
        end
    end
end

--[[移除路径前缀
    参数:
        full_path: 完整路径
        prefix_path: 要移除的前缀路径
    返回值:
        string: 移除前缀后的相对路径
]]
function remove_prefix_path(full_path, prefix_path)
    -- 如果前缀路径正好是路径的开头
    if full_path:sub(1, #prefix_path) == prefix_path then
        -- 从路径中移除前缀
        local result_path = full_path:sub(#prefix_path + 1)
  
        -- 如果结果路径以斜杠开头，移除它
        if result_path:sub(1, 1) == "/" or result_path:sub(1, 1) == "\\" then
            result_path = result_path:sub(2)
        end
  
        return result_path
    else
        -- 如果路径不以前缀开头，则返回原始路径
        return full_path
    end
  end

  -- 检测文件扩展名的函数
function getFileExtension(fileName)
    
    -- 使用正则表达式匹配扩展名
    local fileExtension = fileName:match("^.+(%..+)$")
    
    if fileExtension then
        return fileExtension  -- 返回扩展名
    else
        return nil  -- 如果没有扩展名，返回nil
    end
end

function toFormantStringList(Structlist,formatnlist)
    --local FormantStringList = {}
    clearTable(formatnlist)
    local viewString = ""
    for index, value in ipairs(Structlist) do
        if(value[1] == 0)then
            viewString = value[3]
            table.insert(formatnlist,viewString)
        end
        if(value[1] == 1)then
            viewString = value[2]
            table.insert(formatnlist,viewString)
        end
    end
end

--[[清空表
    参数:
        t: 要清空的表
]]
function clearTable(t)
    while #t > 0 do
        table.remove(t)
    end
end

--[[复制表
    参数:
        src: 源表
        des: 目标表
    说明: 使用GUI库的table_copy函数进行深拷贝
]]
function TableCopy(src,des)
    des=GUI.table_copy(src)
end

--[[检查文件是否为支持的音频格式
    参数:
        filename: 文件名
    返回值:
        boolean: 是否为支持的音频文件
    说明: 支持的格式包括wav,mp3,flac,ogg,aiff,aac,wma,m4a
]]
function is_valid_audio_extension(filename)
    -- 定义常见的音频文件后缀名
    local valid_extensions = {
        ".wav",
        ".mp3",
        ".flac",
        ".ogg",
        ".aiff",
        ".aac",
        ".wma",
        ".m4a"
    }
  
    -- 获取文件名的后缀
    local extension = filename:match("^.+(%..+)$")
  
    -- 如果找不到后缀名，返回false
    if not extension then
        return false
    end
  
    -- 检查后缀名是否在有效的音频后缀名列表中
    for _, valid_extension in ipairs(valid_extensions) do
        if extension:lower() == valid_extension then
            return true
        end
    end
  
    return false
  end
--------------------UI----------------------
GUI.name = "Import Tool by ChangoW"
GUI.x, GUI.y = 128, 128
GUI.w, GUI.h = 850, 600


GUI.New({
    name="pathTextbox",
    type = "Textbox",
    z = 2,
    x = 50,
    y = 30,
    w = 300,
    h = 20,
    caption = "路径:",
    cap_pos = "left",
    font_a = 3,
    font_b = 2,
    color = "txt",
    bg = "wnd_bg",
    shadow = true,
    pad = 4
})

GUI.New({
    name = "fileImportButton",
    type = "Button",
    caption = "...",
    z = 2,
    x = 350,
    y = 30,
    w = 27,
    h = 27,
    func = function ()
        local pathtmp = getBottonPath()
        if  pathtmp== nil then
            return
        end
        importPath = pathtmp
        GUI.Val( "pathTextbox",importPath)
        clearTable(importList)
        getImportList(importPath,importList)
        toFormantStringList(importList,fileStringList)
        --reaper.ShowConsoleMsg(importList[2][2])

    end
})

--[[获取音频文件信息
    参数:
        filePath: 音频文件的完整路径
    返回值:
        table: 包含音频文件信息的表
        nil: 如果获取失败
]]
function getAudioFileInfo(filePath)
    local info = {}
    local source = reaper.PCM_Source_CreateFromFile(filePath)
    if not source then return nil end
    
    -- 获取采样率和时长
    info.samplerate = reaper.GetMediaSourceSampleRate(source)
    info.length = reaper.GetMediaSourceLength(source)
    
    -- 获取文件大小
    local file = io.open(filePath, "rb")
    if file then
        local size = file:seek("end")
        file:close()
        info.filesize = size
    end
    
    -- 获取文件类型
    info.filetype = getFileExtension(filePath)
    
    -- 计算比特率 (bits per second)
    if info.length > 0 then
        info.bitrate = math.floor((info.filesize * 8) / info.length)
    end
    
    reaper.PCM_Source_Destroy(source)
    return info
end

--[[更新文件信息标签
    参数:
        info: 音频文件信息表
]]
function updateFileInfoLabels(info)
    if not info then
        -- 如果没有信息，显示默认值
        GUI.Val("sampleRateLabel", "采样率: --")
        GUI.Val("bitrateLabel", "比特率: --")
        GUI.Val("durationLabel", "时长: --")
        GUI.Val("fileSizeLabel", "大小: --")
        GUI.Val("fileTypeLabel", "类型: --")
        return
    end
    
    -- 格式化显示信息
    GUI.Val("sampleRateLabel", string.format("采样率:%.0f Hz", info.samplerate))
    GUI.Val("bitrateLabel", string.format("比特率:%.0f kbps", info.bitrate / 1000))
    GUI.Val("durationLabel", string.format("时长:%.2f s", info.length))
    GUI.Val("fileSizeLabel", string.format("大小:%.2f MB", info.filesize / (1024 * 1024)))
    GUI.Val("fileTypeLabel", "类型:" .. info.filetype:sub(2))
end

GUI.New("fileViewListbox","Listbox",{
    caption = "文件:",
    z = 2,
    list = fileStringList,
    x = 50,
    y = 60,
    w = 300,
    h = 250,
    multi = false,
    font_b = 2,
})

GUI.New({
    name = "finalListbox",
    type = "Listbox",
    caption = "导入列表:",
    z = 2,
    list = readyImportStringList,
    x = 450,
    y = 60,
    w = 300,
    h = 250,
    font_b = 2,
    multi = false,
})


GUI.New({
    name = "sampleRateLabel",
    type = "Label",
    z = 3,
    x = 60,
    y = 340,
    caption = "采样率: --",
    font = 3,
})

GUI.New({
    name = "bitrateLabel",
    type = "Label",
    z = 3,
    x = 200,
    y = 340,
    caption = "比特率: --",
    font = 3,
})

GUI.New({
    name = "durationLabel",
    type = "Label",
    z = 3,
    x = 60,
    y = 365,
    caption = "时长: --",
    font = 3,
})

GUI.New({
    name = "fileSizeLabel",
    type = "Label",
    z = 3,
    x = 200,
    y = 365,
    caption = "大小: --",
    font = 3,
})

GUI.New({
    name = "fileTypeLabel",
    type = "Label",
    z = 3,
    x = 60,
    y = 390,
    caption = "类型: --",
    font = 3,
})

GUI.New({
    name = "finallistAddBotton",
    type = "Button",
    z=2,
    x=353,
    y=120,
    w=90,
    h=20,
    caption	= "添加-->",
    func = function()
        -- 获取选中的索引
        local selected = GUI.elms.fileViewListbox:val()      
        if selected and selected > 0 then
            -- 复制元素到准备列表
            table.insert(readyImportList, importList[selected])
            -- 从原始列表移除
            table.remove(importList, selected)
            -- 更新显示列表
            toFormantStringList(importList, fileStringList)
            toFormantStringList(readyImportList, readyImportStringList)
        end
    end
})

GUI.New({
    name = "finallistAllAddBotton",
    type = "Button",
    z=2,
    x=353,
    y=150,
    w=90,
    h=20,
    caption	= "全部添加-->",
    func = function ()
        --if importList == nil
        --reaper.ShowConsoleMsg(importList[2][2])
        readyImportList = GUI.table_copy(importList)
        toFormantStringList(readyImportList,readyImportStringList)
        clearTable(importList)
        clearTable(fileStringList)
    end,
})

GUI.New({
    name = "finallistDeleteBotton",
    type = "Button",
    z=2,
    x=353,
    y=180,
    w=90,
    h=20,
    caption	= "<--移出",
    func = function()
        -- 获取选中的索引
        local selected = GUI.elms.finalListbox:val()
        if selected and selected > 0 then
            -- 复制元素到原始列表
            table.insert(importList, readyImportList[selected])
            -- 从准备列表移除
            table.remove(readyImportList, selected)
            -- 更新显示列表
            toFormantStringList(importList, fileStringList)
            toFormantStringList(readyImportList, readyImportStringList)
        end
    end,
})

GUI.New({
    name = "finallistAllDeleteBotton",
    type = "Button",
    z=2,
    x=353,
    y=210,
    w=90,
    h=20,
    caption	= "<--全部移出",
    func = function()
        -- 将所有项目移回原始列表
        for _, item in ipairs(readyImportList) do
            table.insert(importList, item)
        end
        -- 清空准备列表
        clearTable(readyImportList)
        clearTable(readyImportStringList)
        -- 更新原始列表显示
        toFormantStringList(importList, fileStringList)
    end,
})

GUI.New({
    name = "importBotton",
    type = "Button",
    z=2,
    x=630,
    y=315,
    w=120,
    h=40,
    caption	= "导入到Reaper",
    func = function ()
        startImport(readyImportList)

    end,
})

GUI.New({
    name = "moveUpButton",
    type = "Button",
    z=2,
    x=753,
    y=120,
    w=30,
    h=20,
    caption = "↑",
    func = function()
        local selected = GUI.Val("finalListbox")
        --reaper.ShowConsoleMsg("上移按钮选中项: " .. tostring(selected) .. "\n")
        if selected and selected > 1 then
            -- 交换当前选中项与上一项
            local temp = readyImportList[selected]
            readyImportList[selected] = readyImportList[selected - 1]
            readyImportList[selected - 1] = temp
            
            -- 更新显示列表
            toFormantStringList(readyImportList, readyImportStringList)
            
            -- 创建新的选择状态表
            local newSelection = {}
            for i = 1, #readyImportStringList do
                newSelection[i] = (i == selected - 1)
            end
            -- 更新选中项
            GUI.Val("finalListbox", newSelection)
        end
    end
})

GUI.New({
    name = "moveDownButton",
    type = "Button",
    z=2,
    x=753,
    y=150,
    w=30,
    h=20,
    caption = "↓",
    func = function()
        local selected = GUI.Val("finalListbox")
        --reaper.ShowConsoleMsg("下移按钮选中项: " .. tostring(selected) .. "\n")
        if selected and selected < #readyImportList then
            -- 交换当前选中项与下一项
            local temp = readyImportList[selected]
            readyImportList[selected] = readyImportList[selected + 1]
            readyImportList[selected + 1] = temp
            
            -- 更新显示列表
            toFormantStringList(readyImportList, readyImportStringList)
            
            -- 创建新的选择状态表
            local newSelection = {}
            for i = 1, #readyImportStringList do
                newSelection[i] = (i == selected + 1)
            end
            -- 更新选中项
            GUI.Val("finalListbox", newSelection)
        end
    end
})

GUI.New({
    name = "Import Directory",
    type = "Radio",
    z = 2,
    x = 50,
    y = 430,
    w = 590,
    h = 120,
    caption = "导入方式",
    opts = {"垂直导入：所有音频单独成轨，起始位置对齐（适合混音）", 
            "对角导入：所有音频单独成轨，依次排列（适合检查）", 
            "水平导入：所有音频在同一轨道上依次排列（适合拼接）"},
    dir = "v",
    pad = 8,
    frame = true,
    font_a = 3,
    font_b = 2,
    shadow = true,
    retval = 1
})

GUI.New({
    name = "unit of import",
    type = "Radio",
    z = 2,
    x = 650,
    y = 430,
    w = 150,
    h = 120,
    caption = "导入单位",
    opts = {"音频块", "各文件夹"},
    dir = "v",
    pad = 8,
    frame = true,
    font_a = 3,
    font_b = 2,
    shadow = true,
    retval = 1
})

GUI.New({
    name = "use relative path as track name",
    type = "Checklist",
    z = 2,
    x = 50,
    y = 550,
    w = 150,
    h = 120,
    caption = "",
    opts = {"使用相对路径作为轨道名"},
    dir = "v",
    pad = 8,
    frame = false,
    font_a = 3,
    font_b = 2,
    shadow = true,

})

GUI.New({
    name = "aboutButton",
    type = "Button",
    z = 2,
    x = 800,
    y = 565,
    w = 35,  -- 减小宽度
    h = 20,  -- 减小高度
    caption = "('◡')",  -- 使用更简单的符号
    font = 3, -- 使用更小的字体
    func = function()
        reaper.MB("作者：ChangoW\n邮箱：changow@qq.com", "反馈", 0)
    end
})


GUI.Val("use relative path as track name", {[1] = true})



--[[更新文件视图列表框的音频信息显示
    说明: 当用户在文件列表中选择一个项目时触发此函数
    功能:
    1. 获取当前选中项的索引
    2. 如果选中的是音频文件(而不是文件夹):
       - 获取该文件的详细音频信息
       - 更新界面上的音频信息标签
    3. 如果选中的是文件夹或没有选中项:
       - 重置音频信息标签为默认值
]]
function fileViewListbox_Update()
    needUpdate = true
end

function updateAudioInfo()
    if not needUpdate then return end
    
    local selected = GUI.elms.fileViewListbox:val()
    if selected and selected > 0 then
        local fileInfo = importList[selected]
        if fileInfo and fileInfo[1] == 1 then -- 确保选中的是文件而不是文件夹
            local audioInfo = getAudioFileInfo(fileInfo[5]) -- 使用绝对路径
            updateFileInfoLabels(audioInfo)
        else
            updateFileInfoLabels(nil) -- 如果选中的是文件夹，显示默认值
        end
    end
    
    needUpdate = false
end


GUI.Init()

-- 在GUI.Init()之后，GUI.Main()之前添加这段代码
GUI.elms.fileViewListbox.onmousedown = fileViewListbox_Update
-- 定义textbox内容变化的监听函数
function updatePathTextbox()
    local newPath = GUI.Val("pathTextbox")
    if newPath ~= "" and newPath ~= importPath then
        importPath = newPath
        clearTable(importList)
        getImportList(importPath, importList)
        toFormantStringList(importList, fileStringList)
    end
end

-- 设置GUI更新函数
GUI.func = function()
    updateAudioInfo()
    updatePathTextbox()
end

GUI.Main()





