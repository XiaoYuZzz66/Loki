-- 183 服务器专用 Lua 映射脚本
-- 从日志路径中提取容器名（日志子目录名即为容器名，如 blm-gateway）
--
-- 路径示例：
--   /usr/projectData/api/gateway/data/logs/blm-gateway/info.log
--   /usr/projectData/admin/gateway/data/logs/blm-admin-gateway/info.log
--   /usr/projectData/admin/data/layer-activity/logs/blm-admin-layer-activity/info.log

function cb_map(tag, timestamp, record)
    local path = record["filepath"] or ""
    -- 匹配 /logs/blm-xxx/ 模式
    local container = string.match(path, "/logs/(blm%-[^/]+)/")
    if not container then
        container = "unknown"
    end
    record["container_name"] = container
    return 2, timestamp, record
end
