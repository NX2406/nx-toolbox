# NX 工具箱

Linux VPS 常用脚本合集，一个命令 `nx` 管理系统、网络、安全、Docker、应用和 LXC 小鸡。整体参考 [kejilion/sh](https://github.com/kejilion/sh) 的思路（Apache-2.0，借用部分见 [NOTICE](NOTICE)），并整合了：

- [vps-PSL](https://github.com/NX2406/vps-PSL)：端口限速
- [ovhroot](https://github.com/NX2406/ovhroot)：开启 root 登录（逻辑已在 nx 中重写增强，原版脚本也可从菜单运行）
- [nx-realm](https://github.com/NX2406/nx-realm)：Realm 转发面板 `nxr`，独立项目，主菜单单独列出

## 安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/NX2406/nx-toolbox/main/nx.sh)
```

国内机器：

```bash
bash <(curl -sL https://ghfast.top/https://raw.githubusercontent.com/NX2406/nx-toolbox/main/nx.sh)
```

首次运行会安装快捷命令，之后输入 `nx` 即可打开菜单。需要 root 权限。

已在 x86_64 上测试：Debian 12 / 13、Ubuntu 22.04 / 24.04、Rocky Linux 8 / 9、AlmaLinux 9、Alpine 3.22。其中 Debian 12 为整机（KVM）实测，含 LXC 小鸡管理、Docker 与应用市场；其余系统在 LXC 小鸡里实测，不含换内核等内核相关功能（2026-11）。Debian 11 早期测过，镜像站已下架，本轮未复测。

## 功能

| 菜单 | 内容 |
| --- | --- |
| 1-3 系统信息 / 更新 / 清理 | 硬件、负载、网络、公网 IP 与归属地；多发行版更新与清理 |
| 4 常用工具 | 常用工具与网络排障工具一键安装，自定义安装 / 卸载 |
| 5 BBR / 网络优化 | BBR + fq、代理与转发节点内核参数优化（可还原）、BBRv3 / XanMod 内核 |
| 6 Docker | 安装、容器管理、日志、清理、镜像加速、IPv6 |
| 7 测试脚本 | IP 质量、流媒体与 AI 解锁、回程路由、三网测速、TCP 延迟、bench / YABS / 融合怪 |
| 8 系统工具 | root 密码、SSH 端口与密钥、Swap、时区、主机名、DNS、IPv4/IPv6 优先、防火墙、fail2ban、定时任务、换源、DD 重装、新建 sudo 用户 |
| 9 Root 登录 | 把 sudo 用户的公钥同步给 root，或开启 root 密码登录（ovhroot 增强版） |
| 10 端口限速 | 运行 vps-PSL |
| 11 LXC 切小鸡 | 基于 Incus，见下文 |
| 12 应用市场 | 1Panel、宝塔、aaPanel、Portainer、3x-ui、sing-box、v2ray-agent、WARP、哪吒监控、Uptime Kuma、OpenList |
| 13 一条龙调优 | 12 项常用初始化一次完成，可勾选 |
| 20 Realm 转发面板 | 打开 `nxr`（未安装时自动安装） |

SSH 相关改动（端口、密码登录、root 登录）都会先备份配置，校验 `sshd -t` 并确认新配置生效，失败自动回滚；兼容 Ubuntu 24.04 的 ssh.socket 启动方式。

## LXC 切小鸡

基于 [Incus](https://linuxcontainers.org/incus/)（兼容已安装的 LXD）。每台小鸡是一个系统容器，宿主机通过 NAT 端口映射提供 SSH 和额外端口，可选独立公网 IPv6。

```bash
nx lxc install                     # 安装 Incus 并初始化存储池、网桥、镜像源
nx lxc create web1 --cpu 2 --mem 1G --swap 512 --disk 20 --net 200 --ports 30
nx lxc batch --count 10 --prefix nat --mem 256 --disk 5 --net 50 --ports 20
nx lxc list
```

可自定义的配置：

| 选项 | 说明 |
| --- | --- |
| `--image debian/12` | 系统镜像（Debian、Ubuntu、Alpine、Rocky、Alma、Arch 等） |
| `--cpu 2` / `--cpu-pin 0-1,3` | 核数，或绑定到指定核 |
| `--cpu-cap 50` | CPU 性能上限（%） |
| `--mem 1G` `--swap 512` | 内存与 Swap |
| `--disk 20` | 硬盘（GB） |
| `--net 100` / `--net-in 200 --net-out 50` | 带宽（Mbps），上下行可分开 |
| `--io 50` / `--read 100 --write 50` / `--iops 1000` | 硬盘读写限速（MB/s），读写可分开，或改为限 IOPS |
| `--procs 512` | 进程数上限 |
| `--ssh-port auto` `--ports 20` | SSH 映射端口与额外 NAT 端口段（TCP+UDP） |
| `--ipv6 on` | 从宿主的 /64 段分配独立 IPv6 |
| `--traffic 1T` | 每月流量配额，`--traffic-action limit`（超额限速，默认 1 Mbps，`--traffic-rate` 调整）或 `stop`（超额关机） |
| `--traffic-count both` `--reset-day 1` | 流量计算方式（合计 / 只计上行 / 只计下行 / 取大）与每月重置日 |
| `--expire 2026-12-31` 或 `30d` | 到期日，过期自动停机，续费后自动开机 |
| `--nesting on` `--privileged` `--autostart on` | 嵌套（小鸡里跑 Docker）、特权容器、开机自启 |

流量配额和到期由守护任务每分钟检查一次（systemd timer `nx-lxc-guard`，没有 systemd 时用 cron）。小鸡重启后流量继续累计，进入新周期自动清零并解除限制。

```bash
nx lxc set web1 --net-in 500 --net-out 100 --traffic 2T    # 在线修改，即时生效
nx lxc traffic                                              # 本月流量、配额状态与到期一览
nx lxc renew web1 30d                                       # 续费：从原到期日顺延
nx lxc info web1                                            # 配置、SSH 地址与 root 密码
```

其余命令：`start / stop / restart / delete / shell / passwd / port / snap / rebuild / overview / images / defaults / uninstall`，详见 `nx lxc help`。

注意：

- `nx lxc install` 只装开容器所需的 `incus-base`（比完整的 `incus` 少拉约 300 个虚拟机相关的包）；要开虚拟机请自行 `apt install incus`。
- 宿主机没有 swap 时，小鸡的 Swap 配额不生效；512MB 的 Rocky / Alma 小鸡运行 dnf 可能内存不足被杀，建议先在宿主执行 `nx swap 2048`。
- 小鸡里开 BBR 需要宿主机先加载 BBR 模块（宿主执行 `nx bbr`）。
- 先开小鸡、后装 Docker：Docker 会把转发链设为拒绝，小鸡会断网。用 `nx docker` 安装会自动放行小鸡网桥，并在 Docker 每次启动后补上规则（重启后仍有效）；用其他方式装的 Docker，再执行一次 `nx lxc install` 即可修复（不会重建存储和网络）。

## 应用市场

均调用各项目的官方安装脚本或官方 Docker 镜像，安装前会显示来源并确认；已安装的应用再次进入即为管理、更新或卸载。

```bash
nx app                 # 菜单
nx app 3x-ui           # 直接安装 / 管理某个应用
```

可用名称：`1panel` `bt` `aapanel` `portainer` `3x-ui` `sing-box` `v2ray-agent` `warp` `nezha` `kuma` `openlist`。Docker 类应用数据保存在 `/home/docker/应用名`，访问端口安装时可改，并自动放行本机防火墙。

## 一条龙调优

```bash
nx tune                                   # 显示将执行的项目并确认
nx tune --with ssh --ssh-port 5522 -y     # 额外改 SSH 端口
nx tune --skip update,swap -y
```

默认执行：更新系统、清理垃圾、1G Swap（已有或容器中跳过）、fail2ban、BBR、上海时区、DNS 自动优选（按是否在国内选择）、IPv4 优先、常用工具、内核网络参数优化。改 SSH 端口（`ssh`）和开放所有端口（`openall`）默认不执行，需要时用 `--with` 加上。单项失败不影响后续，最后汇总结果。

## 常用命令

```
nx                       菜单
nx info | update | clean | bbr | optimize
nx swap 1024 | ssh-port 2222 | root [--password] | f2b | docker | tz Asia/Shanghai | hostname 名称
nx tune | app [名称] | psl | lxc [子命令] | realm（转发面板 nxr） | dd
nx upgrade | uninstall
```

任意命令加 `-y`（`--yes`）跳过确认，适合脚本批量执行。`-y` 只替你确认主操作，顺带的可选操作（如卸载应用时同时删除数据目录）仍按默认不做。`nx realm` 后面的参数原样交给 `nxr`。

## 卸载

`nx uninstall` 删除 `nx` 命令和 `/etc/nx` 配置，可选还原 BBR 与网络优化；其他已做过的系统设置保持不变。Realm 面板（`nxr` → 99）、端口限速、LXC 小鸡不受影响，各自单独卸载；小鸡的月流量配额与到期守护依赖 `nx`，会一并停用。LXC 环境用 `nx lxc uninstall` 卸载（会删除全部小鸡）。

## 许可与致谢

- 部分思路与流程改写自 [kejilion/sh](https://github.com/kejilion/sh)（Apache-2.0），详见 [NOTICE](NOTICE) 与 `THIRD_PARTY_LICENSES/`。
- 测试脚本、应用市场中的第三方脚本均从各自上游下载运行，不随本项目分发。
