# FCU-Sigma Backend

這是一個基於 Supabase 的二手交易平台後端專案，提供完整的交易、訊息、積分獎勵與徽章系統。

## 功能特色

### 🔄 交易系統

完整的二手交易流程，包括見面前確認和見面後完成交易。

**主要功能：**
- 賣家發起交易要約（生成 6 位數確認碼）
- 買賣雙方確認交易意願
- 見面時買家輸入確認碼完成交易
- 即時交易狀態更新
- 完整的交易歷史記錄
- 自動化物品狀態管理（下架/上架）
- 安全的點數結算機制

**交易流程：**
1. **確認階段 (Confirming)** - 賣家發起交易，雙方確認意願並填寫備註
2. **進行中階段 (Pending)** - 買家確認後，交易進入進行中狀態，等待見面
3. **完成階段 (Completed)** - 買家輸入確認碼，交易完成並結算點數

**文件：**
- [交易流程說明](./contracts/transaction/流程說明.md)

---

### 💬 訊息傳遞系統

讓買家和賣家可以針對特定物品進行即時對話。

**主要功能：**
- 建立或取得與賣家的對話
- 發送和接收即時訊息
- 支援多種訊息類型（文字、系統通知、交易通知等）
- 標記訊息為已讀
- 查看未讀訊息數量
- Realtime 即時訊息推送
- 對話軟刪除功能

**技術細節：**
- 使用 PostgreSQL RPC 函數實現業務邏輯
- 啟用 Supabase Realtime 進行即時訊息推送
- 完整的 Row Level Security (RLS) 權限控制
- 自動化觸發器更新對話時間戳

**文件：**
- [訊息功能 API 文件](./MESSAGING_API.md)
- [訊息類型指南](./docs/message_types_guide.md)
- [訊息類型快速參考](./docs/MESSAGE_TYPES_QUICK_REF.md)
- [使用範例](./examples/messaging_usage.js)

---

### 🎯 每日簽到系統

鼓勵使用者每日登入並獲取獎勵點數。

**主要功能：**
- 每日簽到獲取點數
- 連續簽到額外獎勵
- 自動計算連續簽到天數
- 台灣時區支援

**獎勵規則：**
| 連續天數 | 獎勵點數 |
|---------|---------|
| 每日簽到 | 5 點 |
| 連續 3 天 | 10 點 |
| 連續 7 天 | 20 點 |
| 連續 14 天 | 30 點 |
| 連續 30 天 | 50 點 |
| 連續 100 天 | 200 點 |

**API 文件：**
- [每日簽到 API](./contracts/dailySignInAPI/dailySignIn.js)

---

### 🏆 徽章系統

成就徽章獎勵系統，激勵使用者參與平台活動。

**徽章類別：**
- 🔥 **連續簽到 (Streak)** - 連續簽到成就
- 💰 **交易成就 (Transaction)** - 買賣交易里程碑
- 💎 **點數累積 (Points)** - 點數收集成就
- 🌱 **環保貢獻 (Carbon)** - 碳足跡減少貢獻
- 🎉 **季節性活動 (Seasonal)** - 限時活動徽章

**稀有度等級：**
- Common（普通）
- Uncommon（罕見）
- Rare（稀有）
- Epic（史詩）
- Legendary（傳說）

**API 文件：**
- [徽章系統 API](./contracts/userBadges/getUserBadgesWithProgress.js)

---

### 💰 點數系統

完整的虛擬點數經濟系統。

**主要功能：**
- 點數餘額查詢
- 點數變動記錄
- 交易點數結算
- 簽到獎勵發放
- 徽章獎勵發放

**API 文件：**
- [點數概況 API](./contracts/getUserPointsProfileAPI/getUserPointsProfileAPI.js)
- [點數記錄 API](./contracts/get_pointLogsAPI/get_pointLogsAPI.js)

---

### 🤖 AI 物品圖片分析

使用 AI 自動分析物品圖片並提取資訊。

**主要功能：**
- 自動識別物品名稱與描述
- 智慧分類建議
- 碳排放值估算
- 標籤自動生成

**技術細節：**
- 使用 Google Gemini 2.5 Flash-Lite 模型
- 透過 Supabase Edge Function 實現

**API 文件：**
- [AI 圖片分析 API](./contracts/analyzeItemImageAPI/analyzeItemImageAPI.js)
- [AI 辨識測試說明](./AI_RECOGNITION_TEST.md)

---

### 👥 社交功能

使用者互動相關功能。

**主要功能：**
- 追蹤/取消追蹤使用者
- 查看追蹤者與追蹤中列表
- 收藏/取消收藏物品
- 使用者評價系統
- 查看使用者個人資料

**API 文件：**
- [追蹤功能](./contracts/create_followAPI/) / [取消追蹤](./contracts/delete_followAPI/)
- [收藏功能](./contracts/create_favoriteAPI/) / [取消收藏](./contracts/delete_favoriteAPI/)
- [評價功能](./contracts/create_review/) / [查看評價](./contracts/get_my_reviews/)
- [使用者資料](./contracts/get_userProfileAPI/)

---

### 📦 物品管理

物品上架與管理功能。

**主要功能：**
- 建立新物品
- 編輯物品資訊
- 上架/下架切換
- 物品搜尋（支援距離、分類篩選）
- 物品詳情查看

**API 文件：**
- [我的物品](./contracts/get_myItemsAPI/) / [建立物品](./contracts/create_myItemsAPI/)
- [搜尋物品](./contracts/get_searchItemsAPI/)
- [物品詳情](./contracts/get_oneItemDetailAPI/)
- [上下架切換](./contracts/update_toggleItemStatusAPI/)

---

## 專案結構

```
backend/
├── supabase/
│   ├── migrations/          # 資料庫遷移檔案 (70+)
│   ├── functions/           # Edge Functions
│   │   ├── analyze-item-image/   # AI 圖片分析
│   │   └── save-location/        # 位置儲存
│   ├── seeds/               # 測試資料
│   └── tests/               # 測試腳本
├── contracts/               # 前後端 API 介面
│   ├── analyzeItemImageAPI/     # AI 物品分析
│   ├── conversationAPI/         # 對話功能
│   ├── dailySignInAPI/          # 每日簽到
│   ├── transaction/             # 交易功能
│   ├── userBadges/              # 徽章系統
│   ├── getUserPointsProfileAPI/ # 點數概況
│   ├── get_pointLogsAPI/        # 點數記錄
│   └── ...                      # 其他功能
├── docs/                    # 技術文件
├── examples/                # 使用範例
├── tests/                   # 測試檔案
├── MESSAGING_API.md         # 訊息功能 API 文件
├── AI_RECOGNITION_TEST.md   # AI 辨識測試說明
├── TROUBLESHOOTING.md       # 故障排除指南
└── README.md                # 專案說明
```

---

## 快速開始

### 先決條件

- **Docker Desktop** 或 **OrbStack**（建議 macOS 使用 OrbStack）
- **Node.js** 18 或以上版本
- **Git** 與 **npm**
- **Supabase CLI**（專案內開發依賴）

### 安裝步驟

```bash
# 進入 backend 目錄
cd backend

# 安裝依賴
npm install

# 初始化 Supabase（首次設定）
npx supabase init

# 啟動本地服務
npx supabase start

# 重置資料庫並套用所有遷移
npx supabase db reset
```

啟動後，服務將在以下端點運行：
- **Supabase Studio**: http://localhost:54323
- **PostgreSQL**: localhost:54322
- **API Gateway**: http://localhost:54321

---

## 環境變數設定

在 `backend/` 目錄下建立 `.env.local` 檔案：

```bash
# Supabase 連線設定
NEXT_PUBLIC_SUPABASE_URL=http://localhost:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=你的本地 anon key
SUPABASE_SERVICE_ROLE_KEY=你的本地 service role key

# 應用環境設定
NEXT_PUBLIC_APP_ENV=local
NODE_ENV=development
```

---

## 常用指令

### Supabase 服務管理

```bash
npx supabase start      # 啟動所有服務
npx supabase stop       # 停止所有服務
npx supabase status     # 查看服務狀態與連線資訊
```

### 資料庫操作

```bash
npx supabase db shell                        # 開啟資料庫 Shell
npx supabase db diff                         # 查看架構差異
npx supabase migration new <migration_name>  # 產生新遷移檔案
npx supabase db reset                        # 重置資料庫（危險！）
```

### 遠端部署

```bash
npx supabase link --project-ref <ref>  # 連結遠端專案
npx supabase db push                   # 推送遷移到遠端
npx supabase db pull                   # 從遠端拉取遷移
```

---

## IDE 資料庫連線

**本地開發環境連線設定：**

| 設定項 | 值 |
|-------|---|
| Host | localhost |
| Port | 54322 |
| Database | postgres |
| User | postgres |
| Password | postgres |

**支援工具：** IntelliJ IDEA、DataGrip、pgAdmin、DBeaver、TablePlus

---

## 安全性提醒

⚠️ **重要規則：**

1. **Production 環境絕不執行 seed 或危險操作**
2. **所有架構變更必須透過 migrations**
3. **敏感資料不可提交到版本控制**
4. **使用 RLS (Row Level Security) 保護資料**

```javascript
// 環境檢查範例
const isProd = process.env.NEXT_PUBLIC_APP_ENV === 'production';
if (isProd) {
  throw new Error('⛔ 禁止在 Production 環境進行此操作');
}
```

---

## 故障排除

詳細的問題排解請參閱 [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

### 常見問題

| 問題 | 解決方法 |
|-----|---------|
| Supabase 服務無法啟動 | 確認 Docker 正在運行，執行 `npx supabase stop && npx supabase start` |
| 無法連接到資料庫 | 檢查 Port 54322 是否被占用 |
| 環境變數未生效 | 重新開啟終端機或使用 env-cmd |

---

## 相關資源

- [Supabase 官方文件](https://supabase.com/docs)
- [PostgreSQL 官方文件](https://www.postgresql.org/docs/)
- [Supabase CLI 參考](https://supabase.com/docs/reference/cli)

---

## 貢獻

歡迎提交 Issue 和 Pull Request！

## 授權

請參閱專案根目錄的 LICENSE 檔案。