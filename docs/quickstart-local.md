### 本地快速部署與測試（Supabase + Node）

### 1) 先決條件

- Docker Desktop 或 OrbStack（建議 macOS 使用 OrbStack）
- Node.js 18 以上
- Git 與 npm
- Supabase CLI（專案內開發依賴）
    - 安裝：`npm i -D supabase`

### 2) 一次性初始化

```bash
# 於專案根目錄
npx supabase init

# 啟動本地服務（Postgres、Studio、API）
npx supabase start
# 服務端點
# - Studio: http://localhost:54323
# - Postgres: [localhost:54322](http://localhost:54322)
# - API:     http://localhost:54321
```

### 3) 環境變數（本地）

建立 .env.local 並填入值：

```bash
# .env.local
NEXT_PUBLIC_SUPABASE_URL=http://localhost:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=你的本地 anon key
SUPABASE_SERVICE_ROLE_KEY=你的本地 service role key
NEXT_PUBLIC_APP_ENV=local
NODE_ENV=development
```

git 忽略：

```bash
# .gitignore
.env.local
.env*.local
```

### 4) 資料庫遷移與測試資料

```bash
# 產生新的 migration（修改 schema 後）
npx supabase migration new add_feature_x

# 重置資料庫並套用全部 migrations（會自動執行 supabase/seed.sql）
npx supabase db reset
```

seed 範例（僅本地與 Staging 使用）：

```sql
-- supabase/seed.sql
TRUNCATE TABLE posts, comments CASCADE;
-- ...插入測試用戶與測試資料
```

### 5) 啟動應用與測試

```bash
# 啟動應用
npm run dev

# 執行單元/整合測試
npm test
```

### 6) 常用指令速查

```bash
# 啟動/停止/狀態
npx supabase start
npx supabase stop
npx supabase status

# 開 DB shell
npx supabase db shell

# 對比本地 schema 與 migrations 差異
npx supabase db diff

# 推送 migrations 到遠端（先 link）
# npx supabase link --project-ref <your-staging-ref>
# npx supabase db push
```

### 7) IntelliJ/WebStorm 快速連線

- Local DS：host [`localhost`](http://localhost) port `54322` user `postgres` pass `postgres`
- 只勾選 `public`, `auth`, `storage` schemas
- 遠端連線務必啟用 SSL，Production 一律唯讀

### 8) 安全與保護

- Production 絕不執行 seed 或危險操作
- 所有 schema 變更都以 migrations 為單一真相來源
- 若程式內有 seed 或 truncate，先檢查環境旗標

```tsx
// 粗略範例
const isProd = [process.env.NEXT](http://process.env.NEXT)_PUBLIC_APP_ENV === 'production';
if (isProd) throw new Error('⛔ 禁止在 Production 進行此操作');
```

### 9) 快速故障排除

- 服務起不來：確認 Docker 正常，重跑 `npx supabase stop && npx supabase start`
- 連不到 DB：檢查 port 54322 是否被占用，或重啟 Docker
- env 無效：重開終端機或以 `env-cmd`/`dotenv` 正確載入
- seed 重複鍵：先 `npx supabase db reset` 再測

### 10) 一鍵清場

```bash
# 停止並清掉 local volume（謹慎使用，資料會消失）
npx supabase stop --no-backup
docker volume prune
```

如果你要，我可以把這份「快速部署本地測試」加到你正在看的文件頁面頂部，或新建 docs/[quickstart-local.md](http://quickstart-local.md)。