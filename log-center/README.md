# 日志中心（Loki + Grafana + Fluent Bit）

统一采集 **gaobao** 和 **huiyuce_app** 两个项目的 Java 服务文件日志，不采集 Docker stdout。

## 架构

```
┌─────────────────────────────────────────────────┐
│  服务器 A (192.168.1.185)                        │
│                                                  │
│  Loki (3100) ←── Fluent Bit (本地采集)           │
│  Grafana (3000)     job=gaobao                   │
│                     容器: gaobao-gateway/auth/... │
│                     日志路径: /work/projectData/  │
│                              gaobao/api/...      │
└───────────────────────▲──────────────────────────┘
                        │ 3100
┌───────────────────────┴──────────────────────────┐
│  服务器 B (192.168.1.183)                        │
│                                                  │
│  Fluent Bit (远程转发)                           │
│  job=huiyuce_app                                 │
│  容器: blm-gateway/auth/user/...                 │
│  日志路径: /usr/projectData/api/ 和 admin/...    │
└──────────────────────────────────────────────────┘
```

## 项目与日志格式

| 项目 | 服务器 | 容器名前缀 | Loki job 标签 | 日志格式 |
|------|--------|-----------|---------------|----------|
| gaobao | 185 | `gaobao-*` | `job=gaobao` | 无日期前缀：`10:57:03.099 [线程] LEVEL 类 - [方法,行] - 消息` |
| huiyuce_app | 183 | `blm-*` | `job=huiyuce_app` | 有日期+traceId：`2026-06-17 10:50:40.214 [线程] traceId=[] LEVEL 类 - [方法,行] - 消息` |

> 注意：项目归属按**容器名**判断，不按服务器判断。185 上也有 `blm-admin-auth` 子目录的日志（gaobao 项目的历史遗留），使用 `huiyuce_app` 解析器解析后仍归入 `job=gaobao`。

## 目录结构

```
log-center/
├── docker-compose.yml                        # 服务器 A 编排配置
├── loki/
│   ├── loki-config.yaml                      # Loki 配置（多机适配）
│   └── data/                                 # Loki 数据（gitignore）
├── grafana/
│   ├── provisioning/datasources/loki.yaml    # Grafana 数据源
│   └── data/                                 # Grafana 数据（gitignore）
├── fluent-bit/
│   ├── parsers.conf                          # 两种日志解析器
│   ├── fluent-bit.conf                       # 185 本地采集配置
│   ├── fluent-bit-183.conf.template          # 183 远程配置模板
│   ├── map_gaobao_labels.lua                 # 185 容器名映射
│   ├── map_huiyuce_labels.lua                # 183 容器名映射
│   └── fluent-bit-serverB.conf               # 旧版配置（保留）
└── scripts/
    ├── deploy-183.sh                         # 183 一键部署脚本
    ├── deploy-remote.sh                      # 通用部署脚本
    ├── upgrade-remote.sh                     # 配置更新脚本
    └── inventory.conf                        # 机器清单
```

## 服务器 A 启动

```bash
cd /test/cursor/log-center
mkdir -p loki/data grafana/data
docker compose up -d
docker compose ps
```

**服务清单：**

| 服务 | 端口 | 说明 |
|------|------|------|
| loki | 3100 | 日志存储引擎 |
| grafana | 3000 | 日志查询界面 |
| fluent-bit | 2020 | 本地日志采集 |

Grafana 登录：`admin` / `admin123`

## 服务器 B（183）部署采集端

使用一键部署脚本：

```bash
# 在服务器 A 上执行
scp -r /test/cursor/log-center root@192.168.1.183:/work/
ssh root@192.168.1.183 "bash /work/log-center/scripts/deploy-183.sh --loki-host 192.168.1.185 --hostname server-b --env pre"
```

部署参数：

| 参数 | 说明 | 示例 |
|------|------|------|
| `--loki-host` | Loki 所在服务器 IP | `192.168.1.185` |
| `--hostname` | 机器标识（写入 Loki host 标签） | `server-b` |
| `--env` | 环境标识（写入 Loki env 标签） | `pre` 或 `prod` |

> 部署目录：`/work/log-center-fluent-bit/`
> 镜像：`fluent/fluent-bit:3.0.7`
> 容器名：`log-center-fluent-bit`

## Loki 标签体系

| 标签 | 说明 | 可选值 |
|------|------|--------|
| `job` | 项目名 | `gaobao` / `huiyuce_app` |
| `host` | 服务器标识 | `server-a` / `server-b` |
| `env` | 环境 | `pre` / `prod` |
| `container` | 容器名 | `gaobao-gateway` / `blm-gateway` 等 |
| `source` | 数据来源 | `app_file`（过滤测试残留日志时用） |

## Grafana 查询示例

**查询 gaobao 项目：**
```logql
{job="gaobao", source="app_file"}
{job="gaobao", container="gaobao-auth", source="app_file"}
{job="gaobao"} |= "ERROR"
```

**查询 huiyuce_app 项目：**
```logql
{job="huiyuce_app", source="app_file"}
{job="huiyuce_app", container="blm-gateway", source="app_file"}
{job="huiyuce_app"} |= "ERROR"
```

**按服务器过滤：**
```logql
{job="gaobao", host="server-a", source="app_file"}
{job="huiyuce_app", host="server-b", source="app_file"}
```

> 建议：查询时加上 `source="app_file"` 可过滤掉早期测试残留的 docker_stdout 日志。

## 解析器说明

**`gaobao_app`** — 匹配无日期前缀格式：
```
正则: ^(?<time>\d{2}:\d{2}:\d{2}\.\d{3}) \[(?<thread>[^\]]*)\] (?<level>\w+)\s+(?<logger>[^\s]+) - \[(?<method>[^\]]+)\] - (?<message>.*)$
示例: 10:33:06.894 [nacos-executor-1] INFO  c.a.n.c.r.client - [printIfInfoEnabled,63] - [traceId] 消息
```

**`huiyuce_app`** — 匹配含日期+traceId 格式：
```
正则: ^(?<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) \[(?<thread>[^\]]*)\] traceId=\[(?<trace_id>[^\]]*)\] (?<level>\w+)\s+(?<logger>[^\s]+) - \[(?<method>[^\]]+)\] - (?<message>.*)$
示例: 2026-06-17 10:50:40.214 [reactor-http-epoll-8] traceId=[] ERROR c.b.g.f.AuthFilter - [unauthorizedResponse,112] - 消息
```

## 接入新机器

1. 确认日志路径格式符合以下任一模式：
   - `/work/projectData/gaobao/api/*/data/logs/*/*.log`（gaobao 格式）
   - `/usr/projectData/api/*/data/logs/*/*.log` 和 `/usr/projectData/admin/*/data/logs/*/*.log`（huiyuce_app 格式）

2. 根据日志格式选择对应模板：
   - gaobao 格式 → 使用 `fluent-bit-remote.conf.template`
   - huiyuce_app 格式 → 使用 `fluent-bit-183.conf.template`

3. 更新 `scripts/inventory.conf` 记录机器信息

## 维护

**Loki 配置调整**（限流、保留期等）：编辑 `loki/loki-config.yaml` 后重启

```bash
docker compose restart loki
```

**重建业务容器**：无需修改 Fluent Bit 配置，日志目录不变，Fluent Bit 自动跟踪新文件

**183 配置更新**：

```bash
# 修改本地配置后重新部署
scp /test/cursor/log-center/fluent-bit/fluent-bit-183.conf.template root@192.168.1.183:/work/log-center/fluent-bit/
ssh root@192.168.1.183 "bash /work/log-center/scripts/deploy-183.sh --loki-host 192.168.1.185 --hostname server-b --env pre"
```

## 接入新服务（开发侧）

**gaobao 项目**：容器名须以 `gaobao-` 开头，日志挂载到 `/work/projectData/gaobao/api/blm-<模块>/data/logs/`

**huiyuce_app 项目**：容器名须以 `blm-` 开头，日志挂载到 `/usr/projectData/api/<模块>/data/logs/` 或 `/usr/projectData/admin/<模块>/data/logs/`
