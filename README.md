# Backend - 二手交易平台

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

## 專案結構

```
backend/
├── supabase/
│   ├── migrations/          # 資料庫遷移檔案
│   │   └── 20251029091800_setup_messaging_feature.sql
│   ├── seeds/              # 測試資料
│   └── tests/              # 測試腳本
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

