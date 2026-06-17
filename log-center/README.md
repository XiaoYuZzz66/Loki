# gaobao 日志中心（Loki + Grafana + Fluent Bit）

仅采集 **gaobao 应用文件日志**（`/work/projectData/gaobao/api/*/data/logs/*/*.log`），不采集 Docker stdout。

部署在**服务器 A**（本机）。服务器 B 仅运行 Fluent Bit，将日志转发到 A 的 Loki `3100` 端口。

## 目录结构

```
log-center/
├── docker-compose.yml
├── loki/loki-config.yaml
├── fluent-bit/
│   ├── fluent-bit.conf           # 服务器 A
│   ├── fluent-bit-serverB.conf   # 服务器 B
│   ├── map_app_labels.lua
│   └── parsers.conf
└── grafana/provisioning/datasources/loki.yaml
```

## 服务器 A 启动

```bash
cd /test/cursor/log-center
mkdir -p loki/data grafana/data
docker compose up -d
docker compose ps
```

Grafana：http://\<服务器A-IP\>:3000（`admin` / `admin123`）

**重建 gaobao 容器**：无需改 Fluent Bit 配置（日志仍在宿主机同一目录）。

## 服务器 B 部署采集端

1. 复制到 B 机：`fluent-bit.conf`（用 `fluent-bit-serverB.conf` 内容）、`parsers.conf`、`map_app_labels.lua`
2. 确认 `fluent-bit-serverB.conf` 中 `Host` 为 **服务器 A 内网 IP**（默认 `192.168.1.185`）
3. A 机防火墙放行 B 访问 `3100/tcp`
4. 运行示例：

```bash
docker run -d --name fluent-bit-gaobao \
  -e GAOBAO_HOST=server-b \
  -e GAOBAO_ENV=pre \
  -v /opt/fluent-bit/fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf:ro \
  -v /opt/fluent-bit/parsers.conf:/fluent-bit/etc/parsers.conf:ro \
  -v /opt/fluent-bit/map_app_labels.lua:/fluent-bit/etc/map_app_labels.lua:ro \
  -v /work/projectData/gaobao:/work/projectData/gaobao:ro \
  --restart unless-stopped \
  fluent/fluent-bit:3.0.7
```

## Grafana 查询示例

```logql
{job="gaobao", source="app_file"}
{job="gaobao", container="gaobao-auth", source="app_file"}
{job="gaobao", container="gaobao-pay"}
{job="gaobao", host="server-a"}
{job="gaobao"} |= "ERROR"
```

说明：请优先加 `source="app_file"`，避免看到早期测试残留的 `docker_stdout` 日志。

合并两台同名服务：`{job="gaobao", container="gaobao-pay"}`
