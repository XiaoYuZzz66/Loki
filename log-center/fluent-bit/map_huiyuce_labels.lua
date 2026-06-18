-- huiyuce_app 项目专用 Lua 映射脚本（服务器 A / 185）
-- 从日志路径中提取容器名，映射为 huiyuce-* 前缀
--
-- 路径示例：
--   /work/projectData/gaobao/api/blm-gateway/data/logs/blm-gateway/info.log → huiyuce-gateway
--   /work/projectData/gaobao/api/blm-file/data/logs/blm-gaobao/info.log    → huiyuce-pay (特殊映射)
--
-- 注意：blm-admin-auth 子目录的日志使用 gaobao_app 解析器（格式含日期+traceId），
--       不经过此脚本。此脚本仅处理 huiyuce_app 原生格式（无日期前缀）的日志。

local parent_map = {
    ["blm-gateway"] = "huiyuce-gateway",
    ["blm-auth"]    = "huiyuce-auth",
    ["blm-system"]  = "huiyuce-system",
    ["blm-pay"]     = "huiyuce-pay",
    ["blm-file"]    = "huiyuce-file",
    ["blm-job"]     = "huiyuce-job",
    ["blm-zhiyuan"] = "huiyuce-zhiyuan",
}

-- 特殊子目录映射（当子目录名与父模块不一致时）
local subdir_map = {
    ["blm-file/blm-gaobao"] = "huiyuce-pay",
    ["blm-job/blm-gaobao"]  = "huiyuce-zhiyuan",
}

function cb_map(tag, timestamp, record)
    local path = record["filepath"] or ""

    -- 提取父模块目录: /api/blm-xxx/
    local parent = string.match(path, "/api/(blm%-[^/]+)/")
    -- 提取日志子目录: /logs/blm-xxx/
    local subdir = string.match(path, "/logs/(blm%-[^/]+)/")

    local container

    if parent and subdir then
        -- 先检查特殊子目录映射
        local key = parent .. "/" .. subdir
        container = subdir_map[key]
    end

    -- 回退到父模块映射
    if not container and parent then
        container = parent_map[parent]
    end

    record["container_name"] = container or "unknown"
    return 2, timestamp, record
end
