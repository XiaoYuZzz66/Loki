-- gaobao 项目专用 Lua 映射脚本（服务器 A / 185）
-- 从日志路径中提取容器名，映射为 gaobao-* 前缀
--
-- 路径示例：
--   /work/projectData/gaobao/api/blm-gateway/data/logs/blm-gateway/info.log → gaobao-gateway
--   /work/projectData/gaobao/api/blm-auth/data/logs/blm-admin-auth/blm-admin-auth-info.log → gaobao-auth
--
-- 两个 INPUT 管道共用此脚本：
--   管道1: 无日期前缀格式（大部分日志）
--   管道2: blm-admin-auth 子目录（含日期+traceId 格式）

local parent_map = {
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
    -- 提取父模块目录: /api/blm-xxx/
    local parent = string.match(path, "/api/(blm%-[^/]+)/")
    local container = (parent and parent_map[parent]) or "unknown"
    record["container_name"] = container
    return 2, timestamp, record
end
