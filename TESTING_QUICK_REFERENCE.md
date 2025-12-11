# 🚀 FCU Sigma 測試快速參考指南

> 快速查詢已實作的測試及使用方法

---

## 📦 測試檔案快速導航

### SQL 測試 (pgTAP)

| 檔案 | 目的 | 案例數 | 位置 |
|------|------|:-----:|------|
| `00_test_helpers.sql` | 測試輔助函數 | 6 個函數 | `supabase/tests/` |
| `01_rls_users.test.sql` | users 表 RLS | 12 | `supabase/tests/` |
| `02_rls_profiles.test.sql` | profiles 表 RLS | 8 | `supabase/tests/` |
| `03_rls_items.test.sql` | items 表 RLS | 14 | `supabase/tests/` |
| `05_rls_transactions.test.sql` | transactions 表 RLS | 10 | `supabase/tests/` |
| `10_rpc_transactions.test.sql` | 交易 RPC | 20 | `supabase/tests/` |
| `11_rpc_search.test.sql` | 搜尋 RPC | 6 | `supabase/tests/` |
| `12_rpc_daily_signin.test.sql` | 簽到 RPC | 8 | `supabase/tests/` |

### TypeScript 測試 (Deno)

| 檔案 | 目的 | 案例數 | 位置 |
|------|------|:-----:|------|
| `analyze-item-image.test.ts` | Edge Functions | 3 | `supabase/functions/analyze-item-image/` |
| `transactions.api.test.ts` | API E2E | 3 | `tests/` |

---

## 🔧 使用方法

### 本地運行所有測試

```bash
# 推薦：使用本地 CI 腳本（自動啟動 Supabase）
chmod +x backend/scripts/run-local-ci.sh
./backend/scripts/run-local-ci.sh
```

### 分層執行測試

```bash
# 1. 啟動 Supabase
cd backend
supabase start

# 2. 執行 SQL 測試
npx supabase test db

# 3. 執行 Edge Functions 測試
cd supabase/functions/analyze-item-image
deno test --allow-all analyze-item-image.test.ts

# 4. 執行 API 整合測試
cd ../../.. && cd tests
deno test --allow-all transactions.api.test.ts

# 5. 停止 Supabase
cd ../backend
supabase stop
```

### 執行特定測試

```bash
# 只執行某個 SQL 測試檔案
cd backend
npx supabase test db --file supabase/tests/01_rls_users.test.sql

# 只執行 SQL 測試
npx supabase test db

# 生成 lcov 覆蓋率報告
npx supabase test db --report=lcov > coverage.lcov
```

---

## 📊 測試覆蓋矩陣

### RLS 政策覆蓋 (44 案例)

```
users 表 (12)
├─ 已登入查看他人 ✓
├─ nickname 欄位查詢 ✓
├─ 自己資料更新 ✓
├─ 他人資料更新（應失敗）✓
├─ avg_rating 修改（應失敗）✓
├─ 直接 INSERT（應失敗）✓
├─ 記錄刪除（應失敗）✓
└─ 匿名用戶各項限制 (5) ✓

profiles 表 (8)
├─ 查看自己餘額 ✓
├─ 查看他人餘額（應失敗）✓
├─ 直接修改 balance（應失敗）✓
├─ 直接修改 carbon_saved（應失敗）✓
└─ INSERT/DELETE 限制 (4) ✓

items 表 (14)
├─ SELECT × 4 角色 (4) ✓
├─ INSERT × 2 角色 (2) ✓
├─ UPDATE × 4 角色 (4) ✓
├─ DELETE × 3 角色 (3) ✓
└─ listing_status 權限 ✓

transactions 表 (10)
├─ SELECT × 4 角色 (4) ✓
├─ UPDATE × 3 角色 (3) ✓
├─ INSERT 限制 ✓
├─ DELETE 限制 ✓
└─ code 欄位隱私 ✓
```

### RPC 函數覆蓋 (34 案例)

```
交易系統 (20)
├─ initiate_transaction (5)
│  ├─ 正常發起 ✓
│  ├─ 確認碼生成 ✓
│  ├─ 物品自動下架 ✓
│  ├─ 重複檢查 ✓
│  └─ 自購檢查 ✓
├─ buyer_confirm (4) ✓
├─ complete_transaction (6) ✓
└─ cancel_transaction (2) ✓

簽到系統 (8)
├─ 首次簽到 ✓
├─ 重複簽到（應失敗）✓
├─ 連續第 3 天 ✓
├─ 連續第 7 天 ✓
├─ 連續中斷 ✓
├─ 積點累計 ✓
├─ point_logs 記錄 ✓
└─ 徽章觸發 ✓

搜尋系統 (6)
├─ 基本搜尋 ✓
├─ 只返回上架 ✓
├─ 關鍵字過濾 ✓
├─ 分頁功能 ✓
├─ 排序功能 ✓
└─ 距離篩選 ✓
```

---

## 🔍 常見測試查詢

### Q: 如何測試 RLS 權限？

**A:** 使用 `tests.authenticate_as(user_id)` 模擬用戶登入

```sql
-- 模擬 UserA 登入
SELECT tests.authenticate_as('user-a-id'::uuid);

-- 查詢：UserA 現在已登入，可查看他人資訊但受 RLS 限制
SELECT * FROM public.users WHERE id = 'user-b-id'::uuid;
```

### Q: 如何測試交易流程？

**A:** 交易流程分為 4 個步驟

```
1. initiate_transaction     - 賣家發起 (status: confirming)
2. buyer_confirm_transaction - 買家確認 (status: pending)
3. complete_transaction     - 買家完成 (status: completed)
4. cancel_transaction       - 取消交易 (status: cancelled)
```

### Q: 如何驗證積點轉移？

**A:** 檢查 profiles.balance 的變化

- 買家：balance 減少交易額
- 賣家：balance 增加交易額（扣除費用後）

### Q: Edge Functions 測試如何運行？

**A:** 使用 Deno Test 框架

```bash
cd supabase/functions/analyze-item-image
deno test --allow-all analyze-item-image.test.ts
```

---

## 📈 覆蓋率查看

### 生成覆蓋率報告

```bash
# 生成 lcov 格式
cd backend
npx supabase test db --report=lcov > coverage.lcov

# 本地查看（需安裝 lcov）
lcov --summary coverage.lcov
```

### CI/CD 中的覆蓋率

覆蓋率自動上傳到 Codecov，可在 PR 中查看：
- 覆蓋率變化 (與 main 分支比較)
- 新增代碼覆蓋率
- 歷史趨勢

---

## 🐛 除錯技巧

### 查看詳細的測試輸出

```bash
# SQL 測試詳細模式
cd backend
npx supabase test db --debug

# 查看 Supabase 日誌
supabase status      # 查看連接信息
supabase logs        # 查看實時日誌
```

### 常見問題

**Q: `auth.uid()` 返回 NULL**
- 檢查 JWT claims 是否正確設定
- 使用 `current_setting('request.jwt.claims', true)` 驗證

**Q: 測試超時**
- 增加 Supabase 啟動等待時間
- 檢查 Docker 資源是否充足

**Q: RLS 測試失敗**
- 驗證 RLS 政策是否正確部署
- 檢查測試資料是否正確建立

---

## 📚 文檔參考

| 文檔 | 說明 |
|------|------|
| `TEST_SUMMARY.md` | 完整測試案例統計 |
| `IMPLEMENTATION_COMPLETE.md` | 實作完成清單 |
| `TROUBLESHOOTING.md` | 常見問題與解決方案 |
| `.github/workflows/backend-tests.yml` | CI 流程配置 |

---

## ✅ 快速檢查清單

在提交代碼前，請執行：

```bash
# 1. 執行本地 CI
./backend/scripts/run-local-ci.sh

# 2. 確認結果
# - 所有測試通過 (✅)
# - 無新的失敗 (✓)
# - 覆蓋率未下降

# 3. 提交代碼
git add .
git commit -m "feat: add test cases for [feature]"
git push

# 4. 查看 PR
# - GitHub Actions 自動運行
# - PR 自動評論顯示測試結果
# - Codecov 顯示覆蓋率變化
```

---

## 🎯 下次新增測試時的步驟

1. **命名規則**：`NN_module_type.test.sql`
   - `NN`：序號 (01, 02, ...)
   - `module`：模組名稱
   - `type`：測試類型 (rls, rpc, integration)

2. **基本模板**：
   ```sql
   BEGIN;
   SELECT plan(N);  -- N = 測試案例數
   
   -- 測試初始化
   -- 測試案例 1
   -- 測試案例 2
   -- ...
   
   -- 清理
   SELECT tests.cleanup_all();
   
   SELECT * FROM finish();
   COMMIT;
   ```

3. **命名測試**：
   ```sql
   SELECT ok(condition, 'TEST-ID: 描述');
   ```

4. **提交 PR**
   - 更新 TEST_SUMMARY.md
   - 確認 CI 通過

---

**Happy Testing! 🎉**

更新日期：2025-12-11  
版本：v1.0

