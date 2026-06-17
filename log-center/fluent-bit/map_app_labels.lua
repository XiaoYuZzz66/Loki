-- 根据日志路径中的 /api/blm-xxx/ 模块目录映射为 gaobao 容器名（优先于 /logs 子目录名）
local map = {
    ["blm-gateway"] = "gaobao-gateway",
    ["blm-auth"] = "gaobao-auth",
    ["blm-system"] = "gaobao-system",
    ["blm-pay"] = "gaobao-pay",
    ["blm-file"] = "gaobao-file",
    ["blm-job"] = "gaobao-job",
    ["blm-zhiyuan"] = "gaobao-zhiyuan",
}

function cb_map(tag, timestamp, record)
    local path = record["filepath"] or ""
    local module = string.match(path, "/api/(blm%-[^/]+)/")
    local container = (module and map[module]) or "unknown"
    record["container_name"] = container
    return 2, timestamp, record
end
