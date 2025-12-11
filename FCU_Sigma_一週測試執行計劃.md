# FCU Sigma 後端測試 - 一週限時執行計劃

> 📅 **執行期間**: 7 天（35 有效工作小時）  
> 👤 **制定者**: 15 年經驗測試專家  
> 🎯 **目標**: 在時間限制內完成核心測試，確保安全性與業務邏輯正確性

---

## 📋 執行摘要

### 測試策略總覽

```
┌─────────────────────────────────────────────────────────────┐
│                    一週測試執行策略                          │
├─────────────────────────────────────────────────────────────┤
│  📌 核心原則：風險導向 × 增量交付 × MoSCoW 優先級           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Day 1    Day 2    Day 3    Day 4    Day 5    Day 6   Day 7│
│    ▼        ▼        ▼        ▼        ▼        ▼       ▼   │
│  ┌────┐  ┌────┐  ┌────┐  ┌────┐  ┌────┐  ┌────┐  ┌────┐   │
│  │環境│→ │RLS │→ │RLS │→ │RPC │→ │RPC │→ │整合│→ │緩衝│   │
│  │建置│  │核心│  │交易│  │交易│  │擴展│  │CI  │  │收尾│   │
│  └────┘  └────┘  └────┘  └────┘  └────┘  └────┘  └────┘   │
│                                                              │
│  ════════════════════════════════════════════════════════   │
│  必須完成 (Must Have)        ████████████████░░░░░  70%     │
│  盡量完成 (Should Have)      ░░░░░░░░░░░░░░░░████░  20%     │
│  時間允許 (Could Have)       ░░░░░░░░░░░░░░░░░░░██  10%     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 優先級矩陣

| 優先級 | 類別 | 測試項目 | 工時估算 | 風險等級 |
|:------:|------|----------|:--------:|:--------:|
| 🔴 **P0** | Must Have | 測試環境與輔助函數 | 4h | 極高 |
| 🔴 **P0** | Must Have | users/profiles RLS | 4h | 極高 |
| 🔴 **P0** | Must Have | items/transactions RLS | 5h | 極高 |
| 🔴 **P0** | Must Have | 交易 RPC 核心流程 | 6h | 極高 |
| 🟡 **P1** | Should Have | 每日簽到 RPC | 3h | 高 |
| 🟡 **P1** | Should Have | 搜尋 RPC | 2h | 高 |
| 🟡 **P1** | Should Have | Edge Functions | 3h | 中 |
| 🟢 **P2** | Could Have | API 整合測試 | 3h | 中 |
| 🟢 **P2** | Could Have | CI/CD 配置 | 3h | 低 |
| ⚪ **P3** | Won't Have | 壓力測試/滲透測試 | - | - |

---

## 📅 每日執行計劃

### Day 1（週一）- 環境建置與基礎設施

**目標**: 建立穩固的測試基礎，確保後續開發順暢

| 時段 | 任務 | 預計時長 | 交付物 |
|------|------|:--------:|--------|
| 上午 | 本地 Supabase 環境設置 | 1.5h | 可運行的本地環境 |
| 上午 | 驗證資料庫遷移與種子資料 | 1h | 驗證報告 |
| 下午 | 開發測試輔助函數 | 2h | `00_test_helpers.sql` |
| 下午 | 測試輔助函數單元驗證 | 0.5h | 驗證通過紀錄 |

**詳細檢查清單**:

```bash
# 環境驗證指令
□ docker --version              # 確認 Docker 可用
□ npx supabase --version        # 確認 CLI 版本
□ cd backend && npx supabase start   # 啟動服務
□ npx supabase status           # 確認所有服務正常
□ npx supabase db reset         # 重置並套用遷移
```

**測試輔助函數開發順序**:

```sql
-- 開發順序（依照相依性）
1. tests.create_test_user()      -- 核心函數
2. tests.authenticate_as()       -- 認證模擬
3. tests.authenticate_as_anon()  -- 匿名模擬
4. tests.create_test_location()  -- 地點輔助
5. tests.create_test_item()      -- 物品輔助
6. tests.cleanup_all()           -- 清理函數
```

**驗收標準**:
- ✅ `npx supabase start` 成功啟動
- ✅ `npx supabase test db` 可以執行（即使無測試）
- ✅ 測試輔助函數可正常建立用戶

**風險緩解**:
- 若 Docker 啟動失敗，備用方案：使用遠端 Supabase 測試環境
- 輔助函數問題：參考官方 pgTAP 範例

---

### Day 2（週二）- RLS 核心測試（users/profiles）

**目標**: 完成使用者相關資料表的權限測試

| 時段 | 任務 | 預計時長 | 測試案例數 |
|------|------|:--------:|:----------:|
| 上午 | users 表 RLS 測試開發 | 2h | 12 |
| 上午 | users 測試執行與調試 | 1h | - |
| 下午 | profiles 表 RLS 測試開發 | 2h | 8 |
| 下午 | profiles 測試執行與調試 | 0.5h | - |

**users 表測試重點**:

| 測試 ID | 場景 | 斷言 |
|---------|------|------|
| RLS-U-001 | 已登入用戶查看他人 | `ok(EXISTS(...))` |
| RLS-U-002 | 查詢 nickname 欄位 | `is(nickname, 'UserB')` |
| RLS-U-003 | 更新自己資料 | `is(nickname, 'Updated')` |
| RLS-U-004 | 無法更新他人資料 | `is(nickname, 'Original')` |
| RLS-U-005 | 無法修改 avg_rating | `is(rating, 0)` |
| RLS-U-006 | 無法直接 INSERT | `throws_ok(...)` |
| RLS-U-007 | 無法刪除記錄 | `ok(EXISTS(...))` |
| RLS-U-008~012 | 匿名用戶限制 | 多項驗證 |

**profiles 表測試重點**:

| 測試 ID | 場景 | 安全重要性 |
|---------|------|:----------:|
| RLS-P-001 | 只能查看自己餘額 | 🔴 極高 |
| RLS-P-002 | 無法查看他人餘額 | 🔴 極高 |
| RLS-P-003 | 無法直接修改 balance | 🔴 極高 |
| RLS-P-004 | 無法直接修改 carbon_saved | 🟡 高 |
| RLS-P-005~008 | INSERT/DELETE 限制 | 🔴 極高 |

**驗收標準**:
- ✅ `npx supabase test db --file 01_rls_users.test.sql` 全部通過
- ✅ `npx supabase test db --file 02_rls_profiles.test.sql` 全部通過
- ✅ 測試報告截圖保存

**常見問題排解**:

```sql
-- 問題: set_config 不生效
-- 解法: 確認使用 true 參數（僅當前事務）
PERFORM set_config('request.jwt.claims', '...', true);

-- 問題: auth.uid() 返回 NULL
-- 解法: 確認 JWT claims 格式正確
SELECT current_setting('request.jwt.claims', true)::json->>'sub';
```

---

### Day 3（週三）- RLS 進階測試（items/transactions）

**目標**: 完成商品與交易資料表的權限測試

| 時段 | 任務 | 預計時長 | 測試案例數 |
|------|------|:--------:|:----------:|
| 上午 | items 表 RLS 測試開發 | 2.5h | 14 |
| 上午 | items 測試執行與調試 | 0.5h | - |
| 下午 | transactions 表 RLS 測試開發 | 2h | 10 |
| 下午 | transactions 測試執行與調試 | 0.5h | - |

**items 表測試矩陣**:

| 操作 | 自己物品 | 他人上架 | 他人未上架 | 匿名 |
|------|:--------:|:--------:|:----------:|:----:|
| SELECT | ✅ | ✅ | ❌ | ❌ |
| INSERT | ✅ | - | - | ❌ |
| UPDATE | ✅ | ❌ | ❌ | ❌ |
| DELETE | ✅ | ❌ | ❌ | ❌ |

**transactions 表測試矩陣**:

| 角色 | SELECT | UPDATE status | UPDATE code | INSERT | DELETE |
|------|:------:|:-------------:|:-----------:|:------:|:------:|
| 賣家 (giver) | ✅ | ❌ (用RPC) | ❌ | ❌ | ❌ |
| 買家 (receiver) | ✅ | ❌ (用RPC) | ❌ | ❌ | ❌ |
| 無關人員 | ❌ | ❌ | ❌ | ❌ | ❌ |
| 匿名 | ❌ | ❌ | ❌ | ❌ | ❌ |

**驗收標準**:
- ✅ items RLS 測試 14 個案例全部通過
- ✅ transactions RLS 測試 10 個案例全部通過
- ✅ 累計通過：44 個測試案例

**里程碑 🎉**: RLS 政策測試完成！

---

### Day 4（週四）- 交易 RPC 核心測試

**目標**: 完成交易系統核心業務邏輯測試

| 時段 | 任務 | 預計時長 | 測試案例數 |
|------|------|:--------:|:----------:|
| 上午 | initiate_transaction 測試 | 2h | 5 |
| 上午 | buyer_confirm_transaction 測試 | 1.5h | 4 |
| 下午 | complete_transaction 測試 | 2h | 6 |
| 下午 | cancel_transaction 測試 | 0.5h | 2 |

**交易狀態機測試**:

```
                 initiate_transaction
    [物品上架] ─────────────────────────→ [confirming]
                                              │
                    cancel ←──────────────────┤
                      ↓                       │ buyer_confirm
                 [cancelled]                  ↓
                                          [pending]
                                              │
                    cancel ←──────────────────┤
                      ↓                       │ complete (with code)
                 [cancelled]                  ↓
                                          [completed]
```

**關鍵測試案例**:

| ID | 函數 | 測試場景 | 驗證點 |
|:--:|------|----------|--------|
| TXN-001 | initiate | 正常發起 | status='confirming' |
| TXN-002 | initiate | 生成確認碼 | LENGTH(code)=6 |
| TXN-003 | initiate | 物品自動下架 | listing_status=false |
| TXN-004 | initiate | 不可重複發起 | throws_ok |
| TXN-005 | initiate | 不可自己買自己 | throws_ok |
| TXN-006 | confirm | 狀態變更 | status='pending' |
| TXN-007 | confirm | 餘額不足檢查 | throws_ok |
| TXN-008 | complete | 錯誤碼失敗 | throws_ok |
| TXN-009 | complete | 正確碼成功 | status='completed' |
| TXN-010 | complete | 點數轉移-買家 | balance-=price |
| TXN-011 | complete | 點數轉移-賣家 | balance+=price |
| TXN-012 | complete | 碳足跡累計 | carbon_saved_kg>0 |
| TXN-013 | cancel | 物品重新上架 | listing_status=true |

**驗收標準**:
- ✅ 交易 RPC 測試 13+ 個案例全部通過
- ✅ 點數轉移邏輯正確
- ✅ 狀態機轉換正確

---

### Day 5（週五）- RPC 擴展測試

**目標**: 完成次要 RPC 功能測試

| 時段 | 任務 | 預計時長 | 測試案例數 |
|------|------|:--------:|:----------:|
| 上午 | daily_check_in RPC 測試 | 2.5h | 8 |
| 下午 | search_items RPC 測試 | 2h | 6 |
| 下午 | Edge Functions 基本測試 | 1h | 3 |

**每日簽到測試重點**:

| ID | 場景 | 預期結果 |
|:--:|------|----------|
| SIGN-001 | 首次簽到 | success=true, points=5 |
| SIGN-002 | 重複簽到 | success=false |
| SIGN-003 | 連續第 3 天 | points=10 |
| SIGN-004 | 連續第 7 天 | points=20 |
| SIGN-005 | 中斷後重置 | streak=1 |
| SIGN-006 | 餘額累計 | balance 增加 |
| SIGN-007 | 記錄寫入 | point_logs 有記錄 |
| SIGN-008 | 徽章觸發 | badges 資訊返回 |

**搜尋功能測試重點**:

| ID | 場景 | 預期結果 |
|:--:|------|----------|
| SRCH-001 | 基本搜尋 | 返回結果 |
| SRCH-002 | 只返回上架物品 | 未上架不可見 |
| SRCH-003 | 關鍵字過濾 | 正確篩選 |
| SRCH-004 | 分頁功能 | 正確限制數量 |
| SRCH-005 | 排序功能 | 順序正確 |
| SRCH-006 | 距離篩選 | 正確過濾 |

**驗收標準**:
- ✅ 簽到 RPC 測試通過
- ✅ 搜尋 RPC 測試通過
- ✅ Edge Functions 正向測試通過

---

### Day 6（週六）- 整合與 CI/CD

**目標**: 完成整合測試與自動化流程

| 時段 | 任務 | 預計時長 | 交付物 |
|------|------|:--------:|--------|
| 上午 | API 整合測試開發 | 2h | 交易流程 E2E |
| 上午 | 整合測試執行調試 | 1h | 測試報告 |
| 下午 | GitHub Actions 配置 | 2h | CI/CD 流程 |
| 下午 | 測試結果彙整 | 0.5h | 測試摘要 |

**整合測試流程**:

```typescript
// 簡化版交易流程 E2E 測試
test("完整交易流程", async () => {
  // 1. 建立測試用戶
  const seller = await createTestUser("Seller");
  const buyer = await createTestUser("Buyer");
  
  // 2. 賣家上架物品
  await signInAs(seller);
  const item = await createItem({ price: 1000 });
  
  // 3. 賣家發起交易
  const txn = await initiate(item.id, buyer.id);
  expect(txn.status).toBe("confirming");
  
  // 4. 買家確認
  await signInAs(buyer);
  await confirm(txn.id);
  
  // 5. 買家完成交易
  await complete(txn.id, txn.code);
  
  // 6. 驗證結果
  expect(await getBuyerBalance()).toBe(9000);
  expect(await getSellerBalance()).toBe(11000);
});
```

**GitHub Actions 最小配置**:

```yaml
name: Backend Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
      - run: cd backend && supabase start
      - run: cd backend && supabase test db
      - run: cd backend && supabase stop
```

**驗收標準**:
- ✅ 整合測試通過
- ✅ GitHub Actions 配置完成
- ✅ CI 可成功執行

---

### Day 7（週日）- 緩衝與收尾

**目標**: 處理遺留問題、優化文件

| 時段 | 任務 | 預計時長 | 說明 |
|------|------|:--------:|------|
| 上午 | 失敗測試修復 | 2h | 緩衝時間 |
| 上午 | 測試覆蓋率補充 | 1h | 補強弱點 |
| 下午 | 測試報告整理 | 1.5h | 彙整成果 |
| 下午 | 簡報素材準備 | 1h | Demo 截圖 |

**最終檢查清單**:

```markdown
## 提交前檢查

### 必須項目 ✅
- [ ] `npx supabase test db` 全部通過
- [ ] 所有 P0 測試案例完成
- [ ] 測試輔助函數可正常運作
- [ ] CI/CD 流程可執行

### 建議項目 🟡
- [ ] P1 測試案例完成
- [ ] Edge Functions 測試通過
- [ ] 測試報告已生成

### 加分項目 🌟
- [ ] API 整合測試完成
- [ ] 測試覆蓋率報告
- [ ] 效能基準測試
```

---

## 📊 測試案例總覽

### 最終交付目標

| 類別 | 測試檔案 | 案例數 | 優先級 | 狀態 |
|------|----------|:------:|:------:|:----:|
| 輔助函數 | `00_test_helpers.sql` | - | P0 | ⬜ |
| RLS-users | `01_rls_users.test.sql` | 12 | P0 | ⬜ |
| RLS-profiles | `02_rls_profiles.test.sql` | 8 | P0 | ⬜ |
| RLS-items | `03_rls_items.test.sql` | 14 | P0 | ⬜ |
| RLS-transactions | `05_rls_transactions.test.sql` | 10 | P0 | ⬜ |
| RPC-交易 | `10_rpc_transactions.test.sql` | 20 | P0 | ⬜ |
| RPC-簽到 | `12_rpc_daily_signin.test.sql` | 12 | P1 | ⬜ |
| RPC-搜尋 | `11_rpc_search.test.sql` | 10 | P1 | ⬜ |
| Edge Functions | `analyze-item-image.test.ts` | 3 | P1 | ⬜ |
| API 整合 | `transactions.api.test.ts` | 1 | P2 | ⬜ |
| **總計** | | **90** | | |

### 覆蓋率目標 vs 實際

```
測試覆蓋率目標（一週內）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RLS 政策
├── users       目標: 100%  預期: ████████████ 100%
├── profiles    目標: 100%  預期: ████████████ 100%
├── items       目標: 100%  預期: ████████████ 100%
└── transactions 目標: 100%  預期: ████████████ 100%

RPC 函數
├── 交易系統    目標: 100%  預期: ████████████ 100%
├── 每日簽到    目標:  80%  預期: ██████████░░  80%
└── 搜尋功能    目標:  80%  預期: ████████░░░░  70%

Edge Functions
└── AI 分析     目標:  60%  預期: ██████░░░░░░  50%

整合測試
└── 交易流程    目標:  50%  預期: ██████░░░░░░  50%
```

---

## ⚠️ 風險管理

### 高風險項目與緩解措施

| 風險 | 可能性 | 影響 | 緩解措施 |
|------|:------:|:----:|----------|
| Docker 環境問題 | 中 | 高 | 備用：使用遠端 Supabase |
| pgTAP 語法不熟 | 高 | 中 | 準備範例程式碼參考 |
| 測試輔助函數失敗 | 中 | 高 | Day 1 充分測試驗證 |
| RLS 政策與預期不符 | 中 | 高 | 先讀懂現有政策再寫測試 |
| 時間不足 | 中 | 高 | 優先完成 P0 項目 |
| CI/CD 配置失敗 | 低 | 低 | 本地測試優先，CI 次要 |

### 最小可行測試集（Fallback Plan）

若時間極度緊迫，至少完成以下項目：

```
必須完成（約 15 小時）
━━━━━━━━━━━━━━━━━━━━━
✅ 環境建置 + 輔助函數      (4h)
✅ users/profiles RLS       (3h)
✅ items RLS                 (2h)  
✅ transactions RLS          (2h)
✅ 交易 RPC 核心（5 個）     (4h)
━━━━━━━━━━━━━━━━━━━━━
測試案例總數: ~40 個
```

---

## 📝 每日站會報告模板

```markdown
## Daily Standup - Day X

### 昨日完成
- [ ] 任務 1
- [ ] 任務 2

### 今日計劃
- [ ] 任務 1
- [ ] 任務 2

### 阻礙與風險
- 問題描述
- 解決方案

### 測試進度
- 通過: XX 個
- 失敗: XX 個
- 待執行: XX 個
```

---

## 🎯 成功標準

### 一週結束時的預期成果

| 項目 | 標準 | 達成 |
|------|------|:----:|
| 測試案例總數 | ≥ 60 個 | ⬜ |
| P0 案例通過率 | 100% | ⬜ |
| P1 案例通過率 | ≥ 80% | ⬜ |
| CI/CD 可運行 | 是 | ⬜ |
| 可展示 Demo | 是 | ⬜ |

### 簡報展示準備

```
📽️ Demo 展示流程（5 分鐘）
━━━━━━━━━━━━━━━━━━━━━━

1. 展示測試目錄結構 (30s)
2. 執行 RLS 測試並展示輸出 (1min)
3. 執行交易 RPC 測試並展示 (1.5min)
4. 展示 GitHub Actions 配置 (1min)
5. 總結測試覆蓋率 (1min)
```

---

## 📎 附錄

### A. 快速參考指令

```bash
# 環境管理
npx supabase start          # 啟動
npx supabase stop           # 停止
npx supabase status         # 狀態
npx supabase db reset       # 重置

# 測試執行
npx supabase test db                     # 執行所有測試
npx supabase test db --file xxx.sql      # 執行單個檔案
npx supabase test db --debug             # 詳細輸出

# Edge Functions
npx supabase functions serve             # 啟動 Functions
cd supabase/functions && deno test       # 執行測試
```

### B. pgTAP 斷言速查表

```sql
ok(bool, msg)                    -- 驗證為真
is(got, expected, msg)           -- 驗證相等
isnt(got, expected, msg)         -- 驗證不相等
throws_ok(sql, pattern, msg)     -- 驗證拋出錯誤
lives_ok(sql, msg)               -- 驗證不拋錯誤
```

### C. 緊急聯絡

- pgTAP 文件: https://pgtap.org/documentation.html
- Supabase CLI 文件: https://supabase.com/docs/reference/cli
- Deno Test 文件: https://deno.land/manual/testing

---

**📌 備註**: 本計劃基於理想情況估算，實際執行時請根據進度靈活調整。若遇到阻礙，優先確保 P0 項目完成。

---

*文件版本: v1.0 | 制定日期: 2025*