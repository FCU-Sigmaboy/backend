# Backend

這是一個基於 Supabase 的二手交易平台後端專案。

## 功能特色

### 使用者訊息傳遞功能

本專案實現了完整的使用者訊息傳遞功能，讓買家和賣家可以針對特定物品進行即時對話。

**主要功能：**
- 建立或取得與賣家的對話
- 發送和接收即時訊息
- 標記訊息為已讀
- 查看未讀訊息數量
- Realtime 即時訊息推送

**技術細節：**
- 使用 PostgreSQL RPC 函數實現業務邏輯
- 啟用 Supabase Realtime 進行即時訊息推送
- 完整的 Row Level Security (RLS) 權限控制
- 自動化觸發器更新對話時間戳
- 優化的資料庫索引提升查詢效能

**文件：**
- [訊息功能 API 文件](./MESSAGING_API.md) - 完整的 API 使用說明
- [使用範例](./examples/messaging_usage.js) - JavaScript 客戶端範例程式碼
- [測試腳本](./supabase/tests/test_messaging_feature.sql) - SQL 測試腳本

### 交易功能

本專案實現了完整的二手交易流程，包括見面前確認和見面後完成交易。

**主要功能：**
- 賣家發起交易要約（生成確認碼）
- 買賣雙方確認交易意願
- 見面時買家輸入確認碼完成交易
- 即時交易狀態更新
- 完整的交易歷史記錄

**交易流程：**
1. **確認階段** - 賣家發起交易，雙方確認意願
2. **進行中階段** - 交易進入進行中狀態，等待見面
3. **完成階段** - 買家輸入確認碼，交易完成並結算點數

**技術細節：**
- 使用 PostgreSQL RPC 函數實現交易邏輯
- 啟用 Supabase Realtime 進行交易狀態即時推送
- 完整的交易狀態檢查和驗證
- 自動化物品狀態管理（下架/上架）
- 安全的點數結算機制

**文件：**
- [交易流程說明](./contracts/transaction/流程說明.md) - 完整的交易流程說明
- [交易 API](./contracts/transaction/) - 前後端交易介面

## 專案結構

```
backend/
├── supabase/
│   ├── migrations/          # 資料庫遷移檔案
│   │   ├── 20251029091800_setup_messaging_feature.sql
│   │   └── 20251116152605_transaction_before_meet_05_jin.sql
│   ├── seeds/              # 測試資料
│   └── tests/              # 測試腳本
├── contracts/
│   ├── conversationAPI/    # 訊息功能 API
│   ├── transaction/        # 交易功能 API
│   └── ...                 # 其他功能 API
├── examples/               # 使用範例
├── MESSAGING_API.md        # 訊息功能 API 文件
└── README.md              # 專案說明
```

## 快速開始

### 安裝依賴

```bash
npm install
```

### 啟動本地 Supabase

```bash
npx supabase start
```

### 套用資料庫遷移

```bash
npx supabase db reset
```

此命令會重置資料庫、套用所有遷移並載入測試資料。

### 測試訊息功能

在 Supabase Studio (http://localhost:54323) 中執行測試腳本：
- 開啟 SQL Editor
- 載入 `supabase/tests/test_messaging_feature.sql`
- 執行測試腳本驗證功能

## 開發

### 新增遷移

```bash
npx supabase migration new <migration_name>
```

### 推送到遠端

```bash
npx supabase db push
```

## 相關資源

- [Supabase 官方文件](https://supabase.com/docs)
- [PostgreSQL 文件](https://www.postgresql.org/docs/)

本地快速部署與測試指南（Supabase + Node.js）

## 目錄

- [先決條件](#先決條件)
- [初始化設定](#初始化設定)
- [環境變數設定](#環境變數設定)
- [資料庫遷移與測試資料](#資料庫遷移與測試資料)
- [啟動與測試](#啟動與測試)
- [常用指令速查](#常用指令速查)
- [IDE 資料庫連線](#ide-資料庫連線)
- [安全性與最佳實踐](#安全性與最佳實踐)
- [故障排除](#故障排除)

## 先決條件

- **Docker Desktop** 或 **OrbStack**（建議 macOS 使用 OrbStack）
- **Node.js** 18 或以上版本
- **Git** 與 **npm**
- **Supabase CLI**（專案內開發依賴）
  ```bash
  npm install -D supabase
  ```

## 初始化設定

### 一次性初始化步驟

```bash
# 於 backend 目錄執行
cd backend

# 初始化 Supabase
npx supabase init

# 啟動本地服務（Postgres、Studio、API）
npx supabase start
```

啟動後，服務將在以下端點運行：
- **Supabase Studio**: http://localhost:54323
- **PostgreSQL**: localhost:54322
- **API Gateway**: http://localhost:54321

## 環境變數設定

### 本地開發環境

在 `backend/` 目錄下建立 `.env.local` 檔案並填入以下值：

```bash
# Supabase 連線設定
NEXT_PUBLIC_SUPABASE_URL=http://localhost:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=你的本地 anon key
SUPABASE_SERVICE_ROLE_KEY=你的本地 service role key

# 應用環境設定
NEXT_PUBLIC_APP_ENV=local
NODE_ENV=development
```

### Git 忽略設定

確保 `.gitignore` 包含以下內容：

```gitignore
.env.local
.env*.local
```

## 資料庫遷移與測試資料

### 資料庫遷移（Migration）

```bash
# 產生新的遷移檔案（當修改資料庫架構後）
npx supabase migration new add_feature_x

# 重置資料庫並套用所有遷移
# 注意：這會自動執行 supabase/seed.sql
npx supabase db reset

# 查看本地架構與遷移檔案的差異
npx supabase db diff
```

### 測試資料（Seed）

測試資料僅用於本地開發與測試環境，**絕不**在生產環境執行。

範例檔案位置：`supabase/seed.sql`

```sql
-- supabase/seed.sql
-- 清空現有資料
TRUNCATE TABLE posts, comments CASCADE;

-- 插入測試用戶
INSERT INTO users (id, email, name) VALUES 
  ('user-1', 'test@example.com', '測試用戶');

-- 插入測試資料
INSERT INTO posts (title, content, user_id) VALUES 
  ('測試文章', '這是測試內容', 'user-1');
```

## 啟動與測試

```bash
# 啟動應用程式
npm run dev

# 執行測試
npm test

# 執行特定測試檔案
npm test -- tests/your-test.js
```

## 常用指令速查

### Supabase 服務管理

```bash
# 啟動所有服務
npx supabase start

# 停止所有服務
npx supabase stop

# 查看服務狀態與連線資訊
npx supabase status
```

### 資料庫操作

```bash
# 開啟資料庫 Shell（psql）
npx supabase db shell

# 查看本地架構與遷移檔案的差異
npx supabase db diff

# 產生新的遷移檔案
npx supabase migration new <migration_name>

# 重置資料庫（危險操作！）
npx supabase db reset
```

### 遠端部署

```bash
# 連結本地專案到遠端 Supabase 專案
npx supabase link --project-ref <your-project-ref>

# 推送遷移到遠端環境
npx supabase db push

# 從遠端拉取遷移
npx supabase db pull
```

## IDE 資料庫連線

### IntelliJ IDEA / WebStorm / DataGrip

**本地開發環境連線設定：**

- **Host**: `localhost`
- **Port**: `54322`
- **Database**: `postgres`
- **User**: `postgres`
- **Password**: `postgres`

**建議設定：**
- 只勾選 `public`, `auth`, `storage` schemas
- 遠端連線務必啟用 SSL
- **Production 環境一律設為唯讀**

### 其他工具

- **pgAdmin**: 使用相同的連線資訊
- **DBeaver**: 支援 PostgreSQL，使用相同設定
- **TablePlus**: macOS 推薦工具

## 安全性與最佳實踐

### 環境保護

⚠️ **重要規則：**

1. **Production 環境絕不執行 seed 或危險操作**
2. **所有架構變更必須透過 migrations**
3. **敏感資料不可提交到版本控制**

### 程式碼範例：環境檢查

```javascript
// 在執行危險操作前檢查環境
const isProd = process.env.NEXT_PUBLIC_APP_ENV === 'production';

if (isProd) {
  throw new Error('⛔ 禁止在 Production 環境進行此操作');
}

// 安全：可以繼續執行
await truncateTestData();
```

### 最佳實踐

- 使用環境變數管理敏感資訊
- 定期備份資料庫
- 在 CI/CD 中執行測試
- 使用 RLS (Row Level Security) 保護資料
- 遵循最小權限原則

## 故障排除

### 常見問題與解決方案

#### 問題：Supabase 服務無法啟動

**解決方法：**
```bash
# 確認 Docker 正在運行
docker ps

# 重新啟動 Supabase 服務
npx supabase stop
npx supabase start
```

#### 問題：無法連接到資料庫

**可能原因與解決方法：**
1. 檢查 Port 54322 是否被其他程式占用
2. 重啟 Docker 服務
3. 檢查防火牆設定

```bash
# macOS/Linux 檢查 port 占用
lsof -i :54322

# 重啟 Docker
# Docker Desktop: 從選單重啟
# OrbStack: orbstack restart
```

#### 問題：環境變數未生效

**解決方法：**
1. 重新開啟終端機
2. 確認 `.env.local` 檔案位置正確
3. 使用 `env-cmd` 或 `dotenv` 正確載入環境變數

```bash
# 使用 env-cmd
npm install -D env-cmd
env-cmd -f .env.local npm run dev
```

#### 問題：Seed 資料重複鍵錯誤

**解決方法：**
```bash
# 重置資料庫（會清空所有資料並重新執行 seed）
npx supabase db reset
```

#### 問題：遷移檔案衝突

**解決方法：**
```bash
# 查看差異
npx supabase db diff

# 產生新的遷移檔案包含所有變更
npx supabase db diff --schema public > supabase/migrations/YYYYMMDDHHMMSS_fix_conflicts.sql
```

### 一鍵清空本地環境

⚠️ **警告：以下操作會永久刪除本地資料，請謹慎使用！**

```bash
# 停止服務並清除所有本地資料（不建立備份）
npx supabase stop --no-backup

# 清除 Docker volumes（可選）
docker volume prune
```

## 進階主題

### 自訂函式與觸發器

在 `supabase/migrations/` 目錄下建立遷移檔案：

```sql
-- 範例：建立更新時間戳記的觸發器
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_posts_modtime
  BEFORE UPDATE ON posts
  FOR EACH ROW
  EXECUTE PROCEDURE update_modified_column();
```

### Row Level Security (RLS)

```sql
-- 啟用 RLS
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;

-- 建立政策：用戶只能查看自己的文章
CREATE POLICY "用戶只能查看自己的文章"
  ON posts
  FOR SELECT
  USING (auth.uid() = user_id);

-- 建立政策：用戶只能更新自己的文章
CREATE POLICY "用戶只能更新自己的文章"
  ON posts
  FOR UPDATE
  USING (auth.uid() = user_id);
```

### 即時訂閱

```javascript
// 訂閱資料表變更
const subscription = supabase
  .channel('posts')
  .on('postgres_changes', 
    { event: '*', schema: 'public', table: 'posts' },
    (payload) => {
      console.log('資料變更：', payload)
    }
  )
  .subscribe()
```

## 相關資源

- [Supabase 官方文件](https://supabase.com/docs)
- [PostgreSQL 官方文件](https://www.postgresql.org/docs/)
- [Supabase CLI 參考](https://supabase.com/docs/reference/cli)
- [Supabase 最佳實踐](https://supabase.com/docs/guides/platform/best-practices)

## 貢獻

歡迎提交 Issue 和 Pull Request！

## 授權

請參閱專案根目錄的 LICENSE 檔案。