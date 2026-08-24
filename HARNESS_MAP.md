# HARNESS_MAP

ProgrammingAIの入力からログ生成までの接続地図。

```md
学習者の質問
→ main Agent
→ config-guard
→ scope-reader
→ classifier
→ learning-term-manager(作成可否判断)
→ 回答サブAgent(feature / unit / assess / error)
→ 理解確認
→ learning-term-manager(ターム境界判定)
→ learning-log-workflow(ログ候補 / 保存許可 / Learning Case状態更新)
→ learning-cases / learning-logs / notebook
→ profile-memory
→ mentor Agent(.codex/agents/mentor/MEMORY.md)
→ mentor
```

## 見る順番

1. 質問が学習質問か、管理操作かをmain Agentが見る。
2. config-guardが設定を確認する。
3. scope-readerが参照範囲を確認する。
4. classifierが質問分類を返す。
5. learning-term-managerが、学習タームを作成する入力か、作成しない入力かを判断する。
6. 分類に応じた回答サブAgentが回答を作る。
7. main Agentが理解確認を行う。
8. 理解確認への返答や新しい学習質問への移行からターム境界候補を判断する。
9. 明示的な要約依頼なら、learning-log-workflowがログ候補を作る。
10. 保存許可後だけ確定学習ログを生成する。
11. ログ化しない場合やAgent判断では、Learning Caseに状態更新を残す。
12. 確定学習ログ保存時、mentor Agentがlearning-casesとlearning-logsから苦手候補を分析する。
13. main Agentが `.codex/agents/mentor/MEMORY.md` に分析結果を反映する。
14. `学習開始` または日付変更後の最初の学習質問で、mentorがMEMORYを使って復習と確認ポイントを出す。

## このファイルに書かないもの

- 各Skillの詳細手順
- 設定キー一覧
- 回答テンプレート全文
- 全テストケース
