# FCU Sigma 後端測試分類歸納

> 📚 **依據**: 大學資工系軟體測試課程標準分類法  
> 🎯 **目的**: 符合課程教學內容，便於報告撰寫與簡報展示

---

## 📋 測試分類總覽

```
┌─────────────────────────────────────────────────────────────────┐
│                      軟體測試分類架構                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                      系統測試                             │   │
│  │  (System Testing) - 完整系統行為驗證                      │   │
│  │  └── 交易流程 E2E、CI/CD 流程                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ▲                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                      整合測試                             │   │
│  │  (Integration Testing) - 模組間互動驗證                   │   │
│  │  └── API 整合測試、RPC 函數串接                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ▲                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                      單元測試                             │   │
│  │  (Unit Testing) - 個別函數/模組驗證                       │   │
│  │  └── 測試輔助函數、個別 RPC 函數、Edge Functions         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ════════════════════════════════════════════════════════════   │
│                                                                  │
│  ┌────────────────────────┐    ┌─────────────────────────────┐  │
│  │      黑箱測試          │    │        白箱測試              │  │
│  │  (Black-Box Testing)   │    │   (White-Box Testing)        │  │
│  │  • 等價類別劃分         │    │  • 程式碼覆蓋率             │  │
│  │  • 邊界值分析           │    │  • 路徑覆蓋                 │  │
│  │  • RLS 政策測試         │    │  • 狀態機覆蓋               │  │
│  └────────────────────────┘    └─────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔬 一、單元測試 (Unit Testing)

### 定義
針對軟體中最小可測試單元（函數、模組）進行獨立驗證，確保各元件在隔離狀態下正確運作。

### 本專案對應項目

#### 1.1 測試輔助函數單元驗證
| 函數名稱 | 測試目標 | 對應檔案 |
|----------|----------|----------|
| `tests.create_test_user()` | 驗證可正確建立測試用戶 | `00_test_helpers.sql` |
| `tests.authenticate_as()` | 驗證認證模擬功能 | `00_test_helpers.sql` |
| `tests.authenticate_as_anon()` | 驗證匿名模擬功能 | `00_test_helpers.sql` |
| `tests.create_test_location()` | 驗證地點建立功能 | `00_test_helpers.sql` |
| `tests.create_test_item()` | 驗證物品建立功能 | `00_test_helpers.sql` |
| `tests.cleanup_all()` | 驗證清理功能 | `00_test_helpers.sql` |

#### 1.2 RPC 函數單元測試
| 函數名稱 | 測試案例數 | 對應檔案 |
|----------|:----------:|----------|
| `initiate_transaction()` | 5 | `10_rpc_transactions.test.sql` |
| `buyer_confirm_transaction()` | 4 | `10_rpc_transactions.test.sql` |
| `complete_transaction()` | 6 | `10_rpc_transactions.test.sql` |
| `cancel_transaction()` | 2 | `10_rpc_transactions.test.sql` |
| `daily_check_in()` | 8 | `12_rpc_daily_signin.test.sql` |
| `search_items()` | 6 | `11_rpc_search.test.sql` |

#### 1.3 Edge Functions 單元測試
| 函數名稱 | 測試案例數 | 對應檔案 |
|----------|:----------:|----------|
| `analyze-item-image` | 3 | `analyze-item-image.test.ts` |

### 單元測試特徵
- ✅ 測試範圍小且明確
- ✅ 執行速度快
- ✅ 可獨立執行，不依賴其他模組
- ✅ 使用 Mock/Stub 隔離外部依賴

---

## ⬛ 二、黑箱測試 (Black-Box Testing)

### 定義
不考慮程式內部結構，僅依據規格說明與功能需求進行測試，驗證輸入與輸出是否符合預期。

### 本專案對應項目

#### 2.1 RLS 政策黑箱測試
RLS (Row Level Security) 政策測試完全符合黑箱測試特徵：僅驗證「輸入操作」對應的「權限結果」，不需了解政策內部實作。

##### users 表 RLS 測試 (12 案例)
| 測試 ID | 輸入（操作場景） | 預期輸出 | 測試技術 |
|---------|------------------|----------|----------|
| RLS-U-001 | 已登入用戶查看他人 | 可見 | 等價劃分 |
| RLS-U-002 | 查詢 nickname 欄位 | 返回正確值 | 正向測試 |
| RLS-U-003 | 更新自己資料 | 成功 | 正向測試 |
| RLS-U-004 | 更新他人資料 | 失敗 | 負向測試 |
| RLS-U-005 | 修改 avg_rating | 失敗 | 邊界條件 |
| RLS-U-006 | 直接 INSERT | 拋出錯誤 | 負向測試 |
| RLS-U-007 | 刪除記錄 | 失敗 | 負向測試 |
| RLS-U-008~012 | 匿名用戶各項操作 | 受限 | 等價劃分 |

##### profiles 表 RLS 測試 (8 案例)
| 測試 ID | 輸入（操作場景） | 預期輸出 | 安全等級 |
|---------|------------------|----------|:--------:|
| RLS-P-001 | 查看自己餘額 | 可見 | 🔴 |
| RLS-P-002 | 查看他人餘額 | 不可見 | 🔴 |
| RLS-P-003 | 直接修改 balance | 失敗 | 🔴 |
| RLS-P-004 | 直接修改 carbon_saved | 失敗 | 🟡 |
| RLS-P-005~008 | INSERT/DELETE 操作 | 失敗 | 🔴 |

##### items 表 RLS 測試 (14 案例)
| 操作 | 自己物品 | 他人上架 | 他人未上架 | 匿名 |
|------|:--------:|:--------:|:----------:|:----:|
| SELECT | ✅ 可見 | ✅ 可見 | ❌ 不可見 | ❌ 拒絕 |
| INSERT | ✅ 成功 | - | - | ❌ 拒絕 |
| UPDATE | ✅ 成功 | ❌ 失敗 | ❌ 失敗 | ❌ 拒絕 |
| DELETE | ✅ 成功 | ❌ 失敗 | ❌ 失敗 | ❌ 拒絕 |

##### transactions 表 RLS 測試 (10 案例)
| 角色 | SELECT | UPDATE | INSERT | DELETE |
|------|:------:|:------:|:------:|:------:|
| 賣家 (giver) | ✅ | ❌ (用RPC) | ❌ | ❌ |
| 買家 (receiver) | ✅ | ❌ (用RPC) | ❌ | ❌ |
| 無關人員 | ❌ | ❌ | ❌ | ❌ |
| 匿名 | ❌ | ❌ | ❌ | ❌ |

#### 2.2 黑箱測試技術應用

| 測試技術 | 說明 | 應用案例 |
|----------|------|----------|
| **等價類別劃分** | 將輸入分為有效/無效類別 | 用戶角色分類（擁有者/他人/匿名） |
| **邊界值分析** | 測試邊界條件 | 餘額不足檢查、連續簽到天數 |
| **決策表測試** | 條件組合測試 | RLS 權限矩陣 |
| **狀態轉換測試** | 驗證狀態變化 | 交易狀態機 |

### 黑箱測試特徵
- ✅ 基於功能規格進行測試
- ✅ 不需了解內部實作
- ✅ 模擬真實使用者操作
- ✅ 著重輸入/輸出驗證

---

## ⬜ 三、白箱測試 (White-Box Testing)

### 定義
基於程式內部結構與邏輯進行測試，需了解程式碼實作細節，確保所有路徑和分支都被覆蓋。

### 本專案對應項目

#### 3.1 交易狀態機路徑覆蓋
```
                 initiate_transaction
    [物品上架] ─────────────────────────→ [confirming]
         │                                     │
         │                   cancel ←──────────┤
         │                     ↓               │ buyer_confirm
         │                [cancelled]          ↓
         │                     ▲           [pending]
         │                     │               │
         │                   cancel ←──────────┤
         │                                     │ complete (with code)
         │                                     ↓
         │                                [completed]
         │                                     │
         └─────────────────────────────────────┘
                    （完整循環覆蓋）
```

#### 3.2 路徑覆蓋測試案例

| 路徑編號 | 狀態轉換路徑 | 測試案例 |
|:--------:|--------------|----------|
| Path-1 | 上架 → confirming → cancelled | TXN-004 取消交易 |
| Path-2 | 上架 → confirming → pending → cancelled | TXN-013 買家確認後取消 |
| Path-3 | 上架 → confirming → pending → completed | TXN-009 正常完成流程 |
| Path-4 | confirming 重複發起 | TXN-004 例外路徑 |

#### 3.3 分支覆蓋測試

| 函數 | 分支條件 | True 案例 | False 案例 |
|------|----------|-----------|------------|
| `complete_transaction` | code == transaction.code | TXN-009 | TXN-008 |
| `buyer_confirm` | balance >= price | TXN-006 | TXN-007 |
| `daily_check_in` | last_signin == today | SIGN-002 | SIGN-001 |
| `daily_check_in` | streak >= 7 | SIGN-004 | SIGN-001 |

#### 3.4 測試覆蓋率目標

```
程式碼覆蓋率目標
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RPC 函數 - 語句覆蓋 (Statement Coverage)
├── initiate_transaction    目標: 100%  ████████████
├── buyer_confirm           目標: 100%  ████████████
├── complete_transaction    目標: 100%  ████████████
├── cancel_transaction      目標: 100%  ████████████
├── daily_check_in          目標:  80%  ██████████░░
└── search_items            目標:  70%  ████████░░░░

RPC 函數 - 分支覆蓋 (Branch Coverage)
├── 交易系統                目標: 100%  ████████████
├── 每日簽到                目標:  80%  ██████████░░
└── 搜尋功能                目標:  70%  ████████░░░░
```

### 白箱測試特徵
- ✅ 基於程式碼邏輯設計測試
- ✅ 追求路徑/分支覆蓋率
- ✅ 需了解內部實作細節
- ✅ 可發現隱藏的邏輯錯誤

---

## 🔗 四、整合測試 (Integration Testing)

### 定義
將已通過單元測試的模組組合在一起進行測試，驗證模組間的介面與互動是否正確。

### 本專案對應項目

#### 4.1 RPC 函數與資料庫整合
| 整合對象 | 測試重點 | 對應檔案 |
|----------|----------|----------|
| `initiate_transaction` + `items` 表 | 發起交易後物品自動下架 | `10_rpc_transactions.test.sql` |
| `complete_transaction` + `profiles` 表 | 交易完成後點數轉移 | `10_rpc_transactions.test.sql` |
| `complete_transaction` + `carbon_saved` | 交易完成後碳足跡累計 | `10_rpc_transactions.test.sql` |
| `daily_check_in` + `profiles` + `point_logs` | 簽到點數累計與記錄 | `12_rpc_daily_signin.test.sql` |

#### 4.2 API 整合測試

```typescript
// 對應檔案: transactions.api.test.ts
// 測試 Supabase Client + RPC + Database 的整合

test("API 整合：完整交易流程", async () => {
  // 1. 建立測試用戶（整合認證系統）
  const seller = await createTestUser("Seller");
  const buyer = await createTestUser("Buyer");
  
  // 2. 賣家上架物品（整合 items 表）
  await signInAs(seller);
  const item = await createItem({ price: 1000 });
  
  // 3. 發起交易（整合 transactions RPC）
  const txn = await initiate(item.id, buyer.id);
  
  // 4. 買家確認（整合認證切換 + RPC）
  await signInAs(buyer);
  await confirm(txn.id);
  
  // 5. 完成交易（整合多個表更新）
  await complete(txn.id, txn.code);
  
  // 6. 驗證整合結果
  expect(await getBuyerBalance()).toBe(9000);
  expect(await getSellerBalance()).toBe(11000);
});
```

#### 4.3 整合測試策略

| 策略類型 | 說明 | 本專案應用 |
|----------|------|------------|
| **由下而上 (Bottom-Up)** | 先測底層模組再組合 | 先測 RLS → 再測 RPC → 最後 API |
| **增量式整合** | 逐步加入新模組 | Day 2~5 的漸進式測試計劃 |
| **功能整合** | 依功能面向整合 | 交易功能、簽到功能分別整合 |

### 整合測試特徵
- ✅ 測試模組間介面
- ✅ 驗證資料流正確性
- ✅ 發現模組互動問題
- ✅ 比單元測試範圍大

---

## 🖥️ 五、系統測試 (System Testing)

### 定義
在完整的系統環境中進行測試，驗證整個系統是否符合需求規格，包含功能性與非功能性需求。

### 本專案對應項目

#### 5.1 端對端測試 (End-to-End Testing)
| 測試場景 | 涵蓋範圍 | 驗證目標 |
|----------|----------|----------|
| 完整交易流程 | 註冊→上架→交易→完成 | 業務流程正確性 |
| 使用者旅程測試 | 全系統功能串接 | 使用者體驗 |

#### 5.2 CI/CD 系統測試
```yaml
# 對應檔案: .github/workflows/backend-tests.yml
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

#### 5.3 系統測試類型

| 測試類型 | 說明 | 本專案狀態 |
|----------|------|:----------:|
| **功能測試** | 驗證系統功能符合需求 | ✅ 執行 |
| **效能測試** | 驗證系統效能指標 | ⬜ 未規劃 |
| **安全測試** | 驗證系統安全性 | 🟡 部分 (RLS) |
| **相容性測試** | 驗證不同環境相容 | ⬜ 未規劃 |
| **可靠性測試** | 驗證系統穩定性 | ⬜ 未規劃 |

### 系統測試特徵
- ✅ 完整系統環境執行
- ✅ 模擬真實使用情境
- ✅ 驗證端對端流程
- ✅ 包含自動化 CI/CD

---

## 📊 測試分類對照總表

| 原計劃項目 | 單元測試 | 黑箱測試 | 白箱測試 | 整合測試 | 系統測試 |
|------------|:--------:|:--------:|:--------:|:--------:|:--------:|
| 測試輔助函數 | ✅ | | | | |
| users RLS (12) | | ✅ | | | |
| profiles RLS (8) | | ✅ | | | |
| items RLS (14) | | ✅ | | | |
| transactions RLS (10) | | ✅ | | | |
| initiate_transaction (5) | ✅ | | ✅ | ✅ | |
| buyer_confirm (4) | ✅ | | ✅ | ✅ | |
| complete_transaction (6) | ✅ | | ✅ | ✅ | |
| cancel_transaction (2) | ✅ | | ✅ | | |
| daily_check_in (8) | ✅ | | ✅ | ✅ | |
| search_items (6) | ✅ | | | | |
| Edge Functions (3) | ✅ | | | | |
| API 整合測試 (1) | | | | ✅ | |
| 完整交易流程 E2E | | | | | ✅ |
| CI/CD 配置 | | | | | ✅ |

---

## 📈 測試案例統計

| 測試類型 | 案例數量 | 佔比 |
|----------|:--------:|:----:|
| 單元測試 | 31 | 34% |
| 黑箱測試 | 44 | 49% |
| 白箱測試 | 17 | 19% |
| 整合測試 | 5 | 6% |
| 系統測試 | 2 | 2% |

> **註**: 部分測試案例可同時歸類於多個類別（如 RPC 測試同時具有單元/白箱/整合特徵）

---

## 🎯 簡報展示建議

### 測試金字塔說明
```
                    ╱╲
                   ╱  ╲
                  ╱ 系統 ╲          ← 少量、高成本
                 ╱ 測試  ╲
                ╱──────────╲
               ╱   整合     ╲       ← 中等數量
              ╱   測試      ╲
             ╱────────────────╲
            ╱    黑箱/白箱     ╲    ← 功能驗證
           ╱      測試         ╲
          ╱────────────────────────╲
         ╱        單元測試          ╲  ← 大量、低成本
        ╱──────────────────────────────╲
```

### 課程學習成果對應
| 課程主題 | 專案實踐 |
|----------|----------|
| 測試層級與策略 | 完整測試金字塔實作 |
| 黑箱測試技術 | 等價劃分、邊界值分析、決策表 |
| 白箱測試技術 | 路徑覆蓋、分支覆蓋 |
| 測試自動化 | pgTAP、Deno Test、GitHub Actions |
| 測試驅動開發 | 先寫測試規格再實作 |

---

## 📎 參考資源

- [pgTAP 文件](https://pgtap.org/documentation.html)
- [Supabase Testing Guide](https://supabase.com/docs/guides/cli/testing)
- [軟體測試理論 - IEEE 829 標準](https://en.wikipedia.org/wiki/Software_test_documentation)