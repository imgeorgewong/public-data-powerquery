# public-data-powerquery

[English](README.md) | **中文**

面向免费官方经济和统计数据源的 Excel Power Query（M 语言）连接器：央行利率与汇率、国家统计机构数据、建材价格指数、气象与电力市场数据。

每个连接器都是纯文本的 `.m` 文件，粘进 Power Query 的 Advanced Editor 即可刷新。

本仓库只包含代码和文档，**不包含任何数据**。数据版权归各发布机构所有。

## 连接器

| 数据源 | 目录 | 提供什么 | 是否需要 key |
|---|---|---|---|
| ECB Data Portal | `connectors/ecb/` | 政策利率、市场利率、欧元区与各国企业贷款利率、欧元参考汇率 | 否 |
| Bank of England IADB | `connectors/boe/` | Bank Rate、SONIA、企业贷款利率 | 否 |
| CSO PxStat（爱尔兰） | `connectors/cso/` | 任意 PxStat 表：收入、劳动力成本、职位空缺、规划许可、批发价格指数 | 否 |
| ONS 时间序列（英国） | `connectors/ons/` | 按 CDID 取 RPI、CPI、CPIH、生产者价格、收入、职位空缺 | 否 |
| 英国建材指数（DBT，经 GOV.UK） | `connectors/uk-materials/` | 月度建材价格指数，通过 GOV.UK Content API 定位当期文件 | 否 |
| Met Éireann | `connectors/met-eireann/` | 各气象站月度气候数据，含官方发布的采暖度日数 | 否 |
| ENTSO-E Transparency Platform | `connectors/entsoe/` | 日前电价、负荷、分机组类型发电 | **是（免费 token）** |

每个目录下都有一份 README，写明端点、返回结构、示例用的序列，以及该数据源自己的坑。
上表中的端点都在 2026-09-20 用 `tools/probe_endpoints.py` 实际调过；ENTSO-E 除外，因为探测它需要 token。

## 文档

- `docs/gotchas.md` —— 这些 API 和 Power Query 本身会静默产生错误数值的地方
- `docs/methodology.md` —— 链接（chainlink）、换基期、口径版本堆叠、代用指数拼接
- `docs/patterns.md` —— tidy long format、冻结历史 + 实时窗口、零成本 QA 查询、hub-and-spoke 工作簿结构

## 运行环境

Windows 版 Excel（Microsoft 365）。Mac 版 Excel 的 Power Query 不支持网络数据源。

## 安装

```
git clone https://github.com/imgeorgewong/public-data-powerquery.git
cd public-data-powerquery
git config core.hooksPath .githooks
```

## 开发

每个克隆都需要启用一次敏感内容检查：

```
git config core.hooksPath .githooks
```

此后每次提交都会运行 `tools/check_sensitive.py`，它会拦下 Office 和数据文件、内部 URL 与路径、GUID，以及看起来像凭据的字符串。

仓库公开之前，再跑一次全量扫描：

```
python3 tools/check_sensitive.py --all
```

另有一个端点探测脚本，用来确认每个连接器依赖的端点还在正常返回，并打印行数、真实起止日期和最后一个值：

```
python3 tools/probe_endpoints.py          # 全部数据源
python3 tools/probe_endpoints.py ecb      # 只跑一组
```

它会标出"返回 200、但数据早已停更"的序列——只看状态码是发现不了这种情况的。

## 相关仓库

[report-collector](https://github.com/imgeorgewong/report-collector) —— 采集公开报告的 Python 框架。

## 作者

Jingbo Wang（[@imgeorgewong](https://github.com/imgeorgewong)）· [imgeorgewong.github.io](https://imgeorgewong.github.io)

## 许可

MIT，见 `LICENSE`。
