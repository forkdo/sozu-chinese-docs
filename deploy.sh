#!/usr/bin/env bash

#============================================================
# File: deploy.sh
# Description: 部署
# URL: 
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.2.0
# CreatedAt: 2025-12-16
# UpdatedAt: 2026-01-27
#============================================================


if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

DEFAULT_BRANCH="main"
HUGO_VERSION=${HUGO:-0.154.2}

DELETE_FILE="deleted_docs.txt"
ADD_FILE="new_docs.txt"
MODIFIED_FILE="modified_docs.txt"
TRANSLATE_LIST="translate_list.txt"

UPSTREAM_URL="${UPSTREAM_URL:-}"
UPSTREAM_NAME="upstream"

install_hugo() {
    curl -L https://fx4.cn/hugo | bash -s -- -v "$HUGO_VERSION" -w
}

merge_config() {
    if [[ -f config.example.toml ]]; then
        sed '/providers/,$d' ./config.example.toml | tee config.toml > /dev/null
    fi

    if [[ -f aitr.toml ]]; then
        sed -n '/logging/,$p' aitr.toml | tee -a config.toml > /dev/null
    fi
}

merge_source() {
    [[ -d docsite ]] || mkdir docsite
    
    pushd docsite
    if [[ ! -d .git ]]; then
        echo "→ 新建 git 仓库..."
        git init
        git remote add "${UPSTREAM_NAME}" "${UPSTREAM_URL}"
    else
        # 检查是否已经存在 upstream
        if ! git remote get-url "${UPSTREAM_NAME}" >/dev/null 2>&1; then
            echo "→ 添加 upstream remote..."
            git remote add "${UPSTREAM_NAME}" "${UPSTREAM_URL}"
        else
            current_url=$(git remote get-url "${UPSTREAM_NAME}")
            if [[ "${current_url}" != "${UPSTREAM_URL}" ]]; then
                echo "→ 更新 upstream URL: ${current_url} → ${UPSTREAM_URL}"
                git remote set-url "${UPSTREAM_NAME}" "${UPSTREAM_URL}"
            fi
        fi
    fi
    git reset --hard
    git fetch "${UPSTREAM_NAME}" "${DEFAULT_BRANCH}"
    git merge "${UPSTREAM_NAME}"/"${DEFAULT_BRANCH}"
    git rev-parse --short HEAD > ../commit.txt
    popd

    rm -rf docs
    if [[ -d docsite/content ]]; then
        cp -r docsite/content .
        mv content docs
    elif [[ -d docsite/docs ]]; then
        cp -r docsite/docs .
    else
        echo "docsite 目录下没有 content 或 docs 目录，无法合并文档。" >&2
        exit 1
    fi
}

# 增量更新
incremental_update() {
    if [[ -z "$UPSTREAM_URL" ]]; then
        echo "UPSTREAM_URL 未设置，无法进行增量更新。" >&2
        exit 1
    fi

    merge_source

    # 记录删除的文件
    git ls-files --deleted docs/ | tee "$DELETE_FILE"
    ROOT_DIR=$(grep root_dir config.toml | cut -d'"' -f 2 | sed 's|^\./||')
    export ROOT_DIR
    OUTPUT_DIR=$(grep output_dir config.toml | cut -d'"' -f 2 | sed 's|^\./||')
    export OUTPUT_DIR
    # sed -i "s|^$ROOT_DIR/|$OUTPUT_DIR/|g" "$DELETE_FILE"
    # 删除对应的输出文件
    while read -r file; do
        new_file="${file/$ROOT_DIR/$OUTPUT_DIR}"
        echo "$new_file"
        rm -rf "$new_file" || true
    done < "$DELETE_FILE"

    # 更新 git 索引
    git add .
    # 记录新增和修改的文件
    git diff --cached --name-only --diff-filter=A docs/ | tee "$ADD_FILE"
    git diff --cached --name-only --diff-filter=M docs/ | tee "$MODIFIED_FILE"

    cat "$ADD_FILE" "$MODIFIED_FILE" | tee "$TRANSLATE_LIST"

    # 移除以 .png .jpg .jpeg .gif .svg 结尾的文件
    sed -i '/\.\(png\|jpg\|jpeg\|gif\|svg\)$/d' "$TRANSLATE_LIST"

    # 合并 config.toml
    merge_config

    # # 翻译增量文件
    # if ! command -v aitr &> /dev/null; then
    #     echo "正在安装 aitr ..."
    #     curl -L https://fx4.cn/aitr | bash
    # fi

    # 调用 aitr 进行翻译
    if command -v aitr &> /dev/null; then
        aitr --input "$TRANSLATE_LIST" --list --output translated
        cp -r "translated/${ROOT_DIR}/"* "${OUTPUT_DIR}"/
    else
        echo "aitr 未安装，跳过构建步骤。"
    fi
}

# 复制 docs_zh 至  content
copy_docs_zh() {
    if [[ ! -d docsite ]]; then
        if [[ -z "$UPSTREAM_URL" ]]; then
            echo "UPSTREAM_URL 未设置，无法克隆文档站点。" >&2
            exit 1
        fi
        git clone "$UPSTREAM_URL" docsite
    fi
    if [[ -d "translated/docs" ]]; then
        echo "使用 translated/docs 的文档覆盖 docs_zh"
        cp -r translated/docs/* docs_zh/
    fi
    if [[ ! -d docs_zh ]]; then
        echo "docs_zh 目录不存在，无法复制。" >&2
        exit 1
    fi
    if [[ -d docsite/content ]]; then
        cp -r docs_zh/* ./docsite/content/
    elif [[ -d docsite/docs ]]; then
        cp -r docs_zh/* ./docsite/docs/
    else
        echo "docsite 目录下没有 content 或 docs 目录，无法复制。" >&2
        exit 1
    fi
}

# 调用翻译脚本
translate() {
    aitr
}

usage() {
    cat << EOF
用法: $0 [选项]

选项:
  -c --copy      复制 docs_zh
  -g --config    合并 config.toml
  -s --source    合并文档
  -i --incremental   增量更新
  -t --translate  调用翻译脚本
  -h --help      显示此帮助信息

示例:
  $0 --translate
EOF
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--copy)
                copy_docs_zh
                shift
                ;;
            -g|--config)
                merge_config
                shift
                ;;     
            -s|--source)
                merge_source
                shift
                ;;                  
            -i|--incremental)
                incremental_update
                shift
                ;;
            -t|--translate)
                translate
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "未知参数: $1" >&2
                usage
                exit 1
                ;;
        esac
    done
}

main "$@"