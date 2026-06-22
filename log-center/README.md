# 日志中心（Loki + Grafana + Fluent Bit）

统一采集 **gaobao** 和 **huiyuce_app** 两个项目的 Java 服务文件日志，不采集 Docker stdout。

**生产环境部署目录：`/work/projectData/log-center`**

## 架构

```
┌──────────────────────────────────────────────────────┐
│  日志中心服务端 (129.204.182.195)                     │
│                                                      │
│  Loki (3100) ←── Fluent Bit (本地采集 huiyuce_app)   │
│  Grafana (3000)     job=huiyuce_app                  │
│                     容器: blm-gateway/auth/...        │
│                     日志: /work/projectData/api/...   │
└───────────────────────▲───────────────────────────────┘
                        │ 3100
       ┌────────────────┼────────────────┐
       │                │                │
┌──────┴───────┐ ┌──────┴───────┐ ┌──────┴───────┐
│ gaobao 服务器│ │ gaobao 服务器│ │ gaobao 服务器│
│ 139.199.219.96│ │ 106.52.179.14│ │ 192.168.1.185│
│ Fluent Bit   │ │ Fluent Bit   │ │ Fluent Bit   │
│ job=gaobao   │ │ job=gaobao   │ │ job=gaobao   │
│ gaobao-* 容器│ │ gaobao-* 容器│ │ gaobao-* 容器│
└──────────────┘ └──────────────┘ └──────────────┘

┌──────────────────────────────────────────────────────┐
│  huiyuce_app 服务器 (123.207.51.127)                 │
│  Fluent Bit (远程转发)                                │
│  job=huiyuce_app                                     │
│  容器: blm-gateway/auth/user/...                      │
│  日志: /work/projectData/api/ 和 admin/...            │
└──────────────────────────────────────────────────────┘
```

## 项目与日志格式

| 项目 | 容器名前缀 | Loki job 标签 | 日志格式 | 生产服务器 |
|------|-----------|---------------|----------|------------|
| gaobao | `gaobao-*` | `job=gaobao` | 无日期前缀：`10:57:03.099 [线程] LEVEL ...` | 96, 14, 185 |
| huiyuce_app | `blm-*` | `job=huiyuce_app` | 有日期+traceId：`2026-06-17 10:50:40.214 [线程] traceId=[] LEVEL ...` | 195, 127 |

## 目录结构

```
log-center/
├── docker-compose.yml                           # 服务端编排配置
├── loki/
│   ├── loki-config.yaml                         # Loki 配置（多机适配）
│   └── data/                                    # Loki 数据（gitignore）
├── grafana/
│   ├── provisioning/datasources/loki.yaml       # Grafana 数据源
│   └── data/                                    # Grafana 数据（gitignore）
├── fluent-bit/
│   ├── parsers.conf                             # 两种日志解析器
│   ├── fluent-bit.conf                          # 195 本地采集配置（huiyuce_app）
│   ├── fluent-bit-gaobao-prod.conf.template     # gaobao 远程配置模板
│   ├── fluent-bit-huiyuce-prod.conf.template    # huiyuce_app 远程配置模板
│   ├── map_gaobao_labels.lua                    # gaobao 容器名映射
│   └── map_huiyuce_labels.lua                   # huiyuce_app 容器名映射
└── scripts/
    ├── deploy-gaobao.sh                         # gaobao 远程部署脚本
    ├── deploy-huiyuce.sh                        # huiyuce_app 远程部署脚本
    └── inventory.conf                           # 机器清单
```

## 服务端启动（129.204.182.195）

```bash
cd /work/projectData/log-center
mkdir -p loki/data grafana/data
docker compose up -d
docker compose ps
```

**服务清单：**

| 服务 | 端口 | 说明 |
|------|------|------|
| loki | 3100 | 日志存储引擎 |
| grafana | 3000 | 日志查询界面 |
| fluent-bit | 2020 | 本地 huiyuce_app 日志采集 |

Grafana 登录：`admin` / `admin123`

## 远程服务器部署采集端

**gaobao 项目**（96、14、185）：

```bash
# 在服务器 A 上执行
scp -r /work/projectData/log-center root@<远程IP>:/work/projectData/
ssh root@<远程IP> "bash /work/projectData/log-center/scripts/deploy-gaobao.sh --loki-host 129.204.182.195 --hostname <hostname> --env prod"
```

**huiyuce_app 项目**（127）：

```bash
# 在服务器 A 上执行
scp -r /work/projectData/log-center root@<远程IP>:/work/projectData/
ssh root@<远程IP> "bash /work/projectData/log-center/scripts/deploy-huiyuce.sh --loki-host 129.204.182.195 --hostname <hostname> --env prod"
```

部署参数：

| 参数 | 说明 | 示例 |
|------|------|------|
| `--loki-host` | Loki 所在服务器 IP | `129.204.182.195` |
| `--hostname` | 机器标识（写入 Loki host 标签） | `server-b` |
| `--env` | 环境标识（写入 Loki env 标签） | `prod` |

## Loki 标签体系

| 标签 | 说明 | 可选值 |
|------|------|--------|
| `job` | 项目名 | `gaobao` / `huiyuce_app` |
| `host` | 服务器标识 | `server-a` ~ `server-e` |
| `env` | 环境 | `prod` |
| `container` | 容器名 | `gaobao-gateway` / `blm-gateway` 等 |
| `source` | 数据来源 | `app_file` |

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
{job="gaobao", host="server-b", source="app_file"}
{job="huiyuce_app", host="server-a", source="app_file"}
```

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

## 接入新服务（开发侧）

**gaobao 项目**：容器名须以 `gaobao-` 开头，日志挂载到 `/work/projectData/gaobao/api/blm-<模块>/data/logs/`

**huiyuce_app 项目**：容器名须以 `blm-` 开头，日志挂载到 `/work/projectData/api/<模块>/data/logs/` 或 `/work/projectData/admin/<模块>/data/logs/`

## 维护

**Loki 配置调整**（限流、保留期等）：编辑 `loki/loki-config.yaml` 后重启

```bash
cd /work/projectData/log-center
docker compose restart loki
```

**重建业务容器**：无需修改 Fluent Bit 配置，日志目录不变，Fluent Bit 自动跟踪新文件

**远程配置更新**：修改本地模板后重新部署

```bash
# gaobao 项目
scp /work/projectData/log-center/fluent-bit/fluent-bit-gaobao-prod.conf.template root@<远程IP>:/work/projectData/log-center/fluent-bit/
ssh root@<远程IP> "bash /work/projectData/log-center/scripts/deploy-gaobao.sh --loki-host 129.204.182.195 --hostname <hostname> --env prod"

# huiyuce_app 项目
scp /work/projectData/log-center/fluent-bit/fluent-bit-huiyuce-prod.conf.template root@<远程IP>:/work/projectData/log-center/fluent-bit/
ssh root@<远程IP> "bash /work/projectData/log-center/scripts/deploy-huiyuce.sh --loki-host 129.204.182.195 --hostname <hostname> --env prod"
```
