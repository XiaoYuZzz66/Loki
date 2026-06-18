-- gaobao 项目 Lua 映射脚本（服务器 A / 185）
-- 仅处理 blm-admin-auth 子目录的日志（含日期+traceId 格式）
-- 从路径中的父模块目录提取容器名：/api/blm-auth/data/logs/blm-admin-auth/ → gaobao-auth
local map = {
    ["blm-gateway"] = "gaobao-gateway",
    ["blm-auth"]    = "gaobao-auth",
    ["blm-system"]  = "gaobao-system",
    ["blm-pay"]     = "gaobao-pay",
    ["blm-file"]    = "gaobao-file",
    ["blm-job"]     = "gaobao-job",
    ["blm-zhiyuan"] = "gaobao-zhiyuan",
}

function cb_map(tag, timestamp, record)
    local path = record["filepath"] or ""
    -- 从父模块目录提取：/api/blm-xxx/data/logs/blm-admin-auth/
    local parent = string.match(path, "/api/(blm%-[^/]+)/")
    local container = (parent and map[parent]) or "unknown"
    record["container_name"] = container
    return 2, timestamp, record
end
