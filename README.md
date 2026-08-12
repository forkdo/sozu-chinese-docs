# Sōzu 中文文档

本文档使用 AI 翻译

## 项目流程

### 首次使用
1. 创建空分支
```bash
git switch --orphan docs
```

2. 首次提交
```bash
git add README.md
git commit -am init
git push origin docs
```

3. 拉取上游源码
```bash
mkdir -p docsite
pushd docsite
if [[ -d .git ]]; then
    git remote set-url upstream https://github.com/sozu-proxy/sozu.git
else
    git init
    git remote add upstream https://github.com/sozu-proxy/sozu.git
fi
git reset --hard
git fetch upstream main
git merge upstream/main
git rev-parse --short HEAD > ../commit.txt
popd
```

4. 复制源文档
```bash
rm -rf docs
cp -r docsite/doc ./docs
```

5. 全量翻译
```bash
aitr
```

6. 本地测试与构建
```bash
git clone https://github.com/forkdo/sozu-chinese-docs.git docsite
cp -r docs_zh/* ./docsite/doc
cd docsite
```

8. 启动或构建
```bash
# pip install zensical
uv tool install zensical

zensical build --clean
...
```

### 2. AI 翻译
- 安装 [**CLI**](https://git.jetsung.com/jetsung/ai-translator) 工具 （增量更新直接使用 AI CLI 工具直接对比）
```bash
curl -L https://fx4.cn/aitr | bash
```

1. 设置环境变量 [`config.toml`](config.example.toml)
```bash
...
[[providers]]
enabled = true
name = "grok"
api_key = "xxx"
base_url = "https://api.x.ai/v1"
model = "grok-3"
concurrency = 1 # 线程数
rate_delay = 3.0 # 每个请求后等待 1.0 秒（可根据限流调整）
```

2. AI 翻译
```bash
aitr
```
