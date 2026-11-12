# 文件类型目录

OpenKind 内置的列表是为日常使用整理的常见扩展名集合，不是 macOS 受支持类型或所有文件类型的完整列表。找不到的扩展名可以通过界面手动添加。前端、编程和配置类别中的常见后缀参照 [GitHub Linguist 的 languages.yml](https://github.com/github-linguist/linguist/blob/d456527fe93355baa28c3c29d542c97282b61bc7/lib/linguist/languages.yml)，按使用场景人工精选，而非完整导入；包含 Vue、Svelte、Astro、JSX/TSX 等。上游版权和许可保存在 [Linguist-LICENSE.txt](third-party/Linguist-LICENSE.txt)。

分类只是方便筛选的标签，不代表目标应用支持该格式。候选应用和实际关联由系统提供；扩展名不一定一一对应独立的系统内容类型，多个扩展名可能共享同一个类型。同一扩展名也可能被多种语言或格式使用。

初版只按单段扩展名处理，不区分 `d.ts`、`tar.gz` 这类复合后缀，也不管理 `Dockerfile`、`.gitignore` 这类无后缀或点开头的完整文件名。数据源中部分扩展名是大小写敏感的特定语言惯例，OpenKind 当前将输入规范化为小写，不适合导入全部数据；完善类型识别后再考虑可更新的完整目录。
