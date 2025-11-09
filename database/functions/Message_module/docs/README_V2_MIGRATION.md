# 訊息系統 v2 遷移總覽

## 📌 專案概述

本專案提供了訊息系統從 v1 到 v2 的完整遷移方案,實現**去角色化設計**和**平滑過渡**,不影響現有 v1 系統的運行。

### 核心改進

| 功能 | v1 | v2 | 改進 |
|------|----|----|------|
| **角色設計** | 固定買家/賣家 | 去角色化 (participant_1/2) | ✅ 支援角色互換 |
| **商品關聯** | 單一商品 | 多商品討論 | ✅ 更靈活的對話 |
| **已讀狀態** | 單一 is_read | 雙向追蹤 | ✅ 獨立追蹤每個用戶 |
| **歸檔功能** | 軟刪除 | 獨立歸檔 | ✅ 個人化管理 |
| **資料表** | 2 個表 | 3 個表 | ✅ 更清晰的資料結構 |

---

## 📁 文件結構

```
Message_module/
├── README_V2_MIGRATION.md          # 本文件 (總覽)
├── 角色互換改造方案_v2平滑過渡.md   # 完整設計文件
├── api-reference-v2.md              # API 參考手冊
├── IMPLEMENTATION_GUIDE_V2.md       # 實施指南
└── migrations/
    └── messaging_v2_complete.sql    # 完整 SQL 遷移腳本
```

---

## 🚀 快速開始

### 1️⃣ 安裝 v2 系統 (5 分鐘)

```bash
# 執行 SQL 安裝腳本
psql -U postgres -d your_database \
  -f migrations/messaging_v2_complete.sql
```

**腳本會自動建立**:
- ✅ 3 個新資料表 (`conversations_v2`, `conversation_messages_v2`, `conversation_items_v2`)
- ✅ 所有必要的索引
- ✅ RLS 安全性策略
- ✅ 9 個 RPC 函數

### 2️⃣ 遷移現有資料 (可選)

```sql
-- 批次遷移 v1 資料到 v2
SELECT * FROM migrate_conversations_v1_to_v2(1000, 0);

-- 驗證遷移結果
SELECT * FROM verify_migration_v1_to_v2();
```

### 3️⃣ 前端整合

```typescript
import { MessagingV2 } from '@/lib/messaging-v2';

// 建立對話
const conversation = await MessagingV2.createOrGetConversation(
  'other-user-id',
  123  // item_id
);

// 發送訊息
await MessagingV2.sendMessage(
  conversation.conversation_id,
  'Hello!',
  { messageType: 'text' }
);

// 查詢對話列表
const conversations = await MessagingV2.getConversations(1, 20);
```

---

## 📚 文件導覽

### 新手入門

1. **先閱讀**: [API 參考手冊](./api-reference-v2.md)
   - 簡短易懂
   - 包含所有 API 使用範例
   - 適合快速上手

2. **再閱讀**: [實施指南](./IMPLEMENTATION_GUIDE_V2.md)
   - 詳細的安裝步驟
   - 測試驗證方法
   - 故障排除指南

### 深入理解

3. **完整設計**: [角色互換改造方案](./角色互換改造方案_v2平滑過渡.md)
   - 設計理念和原因
   - 完整的資料庫架構
   - 遷移策略和時程規劃

4. **SQL 腳本**: [migrations/messaging_v2_complete.sql](./migrations/messaging_v2_complete.sql)
   - 完整的 SQL 程式碼
   - 可直接執行
   - 包含詳細註解

---

## 🎯 核心 API 一覽

### 對話管理

```typescript
// 建立或取得對話
create_or_get_conversation_v2(other_user_id, initial_item_id?)
→ { conversation_id, is_new, ... }

// 查詢對話列表
get_user_conversations_v2(page?, size?, include_archived?)
→ [{ conversation_id, other_user_name, unread_count, ... }]

// 歸檔對話
toggle_conversation_archive_v2(conversation_id, archived)
→ boolean
```

### 訊息管理

```typescript
// 發送訊息
send_message_v2(conversation_id, content, message_type?, related_item_id?)
→ { message_id, created_at, ... }

// 查詢訊息
get_conversation_messages_v2(conversation_id, page?, size?)
→ [{ message_id, content, is_mine, is_read, ... }]

// 標記已讀
mark_messages_as_read_v2(conversation_id, up_to_message_id?)
→ number (更新筆數)
```

### 商品關聯

```typescript
// 查詢對話中的商品
get_conversation_items_v2(conversation_id)
→ [{ item_id, item_title, message_count, ... }]
```

---

## 🔄 遷移策略

### 方案 A: 完全獨立 (推薦)

**特點**: v1 和 v2 完全並存,互不影響

```
✅ 優點:
- 零風險,v1 完全不受影響
- 可以隨時回退到 v1
- 漸進式測試和推出

⚠️ 注意:
- 需要維護兩套程式碼一段時間
- 資料庫空間增加 (約 2 倍)
```

**實施步驟**:
1. 安裝 v2 系統 (不影響 v1)
2. 遷移歷史資料到 v2
3. 新功能使用 v2 API
4. 漸進式推出給用戶 (5% → 20% → 50% → 100%)
5. 穩定運行 3-6 個月後移除 v1

### 方案 B: 立即切換 (不推薦新手)

**特點**: 直接全面切換到 v2

```
⚠️ 風險較高:
- 需要充分測試
- 建議先在測試環境驗證
- 需要準備好回退方案
```

---

## 📊 資料表對照

### v1 架構

```
conversations
├── buyer_id (UUID)
├── seller_id (UUID)
└── item_id (BIGINT) - 固定單一商品

conversation_messages
├── sender_id (UUID)
├── receiver_id (UUID)
└── is_read (BOOLEAN) - 單向追蹤
```

### v2 架構

```
conversations_v2
├── participant_1_id (UUID) - 去角色化
├── participant_2_id (UUID) - 去角色化
├── initial_item_id (BIGINT) - 可選
├── archived_by_participant_1 (BOOLEAN)
└── archived_by_participant_2 (BOOLEAN)

conversation_messages_v2
├── sender_id (UUID)
├── related_item_id (BIGINT) - 可關聯商品
├── read_by_participant_1 (BOOLEAN)
└── read_by_participant_2 (BOOLEAN)

conversation_items_v2 (新增)
├── conversation_id (BIGINT)
├── item_id (BIGINT)
└── message_count - 追蹤討論熱度
```

---

## 🎨 UI/UX 改進建議

### 對話列表頁面

```typescript
// 顯示對方用戶資訊 (自動判斷)
<ConversationItem
  otherUserName={conv.other_user_name}
  otherUserAvatar={conv.other_user_avatar}
  lastMessage={conv.last_message_content}
  unreadCount={conv.unread_count}
/>
```

### 對話室頁面

```typescript
// 顯示所有討論的商品
<ConversationHeader items={conversationItems} />

// 訊息支援商品引用
<Message
  content="請問這個商品..."
  relatedItem={item}  // 關聯的商品
/>
```

---

## ⚡ 效能特性

### 查詢優化

- ✅ 優化的索引設計 (7 個索引)
- ✅ 使用 CTE 減少子查詢
- ✅ 索引覆蓋查詢 (covering index)
- ✅ 分頁查詢支援

### 預期效能

| 操作 | 預期時間 | 備註 |
|------|---------|------|
| 建立對話 | < 50ms | 包含資料驗證 |
| 發送訊息 | < 30ms | 自動更新已讀狀態 |
| 查詢對話列表 | < 100ms | 20 筆 + JOIN |
| 查詢訊息列表 | < 80ms | 50 筆 + JOIN |
| 標記已讀 | < 20ms | 批次更新 |

---

## 🔒 安全性

### RLS (Row-Level Security)

所有資料表都啟用 RLS,確保:

- ✅ 只能查詢自己參與的對話
- ✅ 只能發送訊息到自己的對話
- ✅ 不能查看其他人的私密對話
- ✅ 禁止直接刪除資料 (使用軟刪除/歸檔)

### 最佳實踐

```typescript
// ✅ 推薦: 使用 RPC 函數 (自動驗證權限)
await MessagingV2.sendMessage(conversationId, content);

// ❌ 避免: 直接操作資料表 (繞過安全檢查)
await supabase.from('conversation_messages_v2').insert({ ... });
```

---

## 🧪 測試清單

### 功能測試

- [ ] 建立新對話
- [ ] 取得已存在的對話
- [ ] 發送純文字訊息
- [ ] 發送帶商品引用的訊息
- [ ] 查詢對話列表 (含未讀數)
- [ ] 查詢對話訊息
- [ ] 標記訊息為已讀
- [ ] 歸檔對話
- [ ] 取消歸檔對話
- [ ] 查詢對話中的商品

### 權限測試

- [ ] 無法查看他人對話
- [ ] 無法發送訊息到他人對話
- [ ] 無法與自己建立對話
- [ ] 未認證用戶無法操作

### 效能測試

- [ ] 對話列表查詢 < 100ms
- [ ] 訊息列表查詢 < 80ms
- [ ] 發送訊息 < 30ms
- [ ] 1000+ 對話的效能表現

---

## 📈 監控指標

### 關鍵指標

```sql
-- 查看 v2 系統狀態
SELECT * FROM messaging_v2_dashboard;

-- 輸出:
-- | metric                        | value  |
-- |-------------------------------|--------|
-- | Total Conversations           | 1,523  |
-- | Active Conversations (7d)     | 456    |
-- | Messages Today                | 234    |
-- | Avg Response Time (min)       | 15.3   |
```

### 告警設定

建議監控:
- ⚠️ 錯誤率 > 1%
- ⚠️ API 回應時間 > 500ms
- ⚠️ 未讀訊息數量異常增長
- ⚠️ 資料庫連接數過高

---

## ❓ 常見問題

### Q1: v2 會影響現有 v1 系統嗎?

**答**: 不會。v2 使用完全獨立的資料表和函數,v1 系統繼續正常運作。

### Q2: 需要停機維護嗎?

**答**: 不需要。安裝 v2 和遷移資料都可以在線上進行。

### Q3: 遷移需要多久?

**答**: 取決於資料量:
- 1,000 個對話: ~5 分鐘
- 10,000 個對話: ~30 分鐘
- 100,000 個對話: ~3 小時 (建議分批執行)

### Q4: 可以回退到 v1 嗎?

**答**: 可以。v1 資料完全保留,隨時可以切換回去。

### Q5: 前端需要改動多少?

**答**: 如果使用適配器模式,改動很小:
```typescript
// 只需要改變一個 import
import { MessagingAdapter } from '@/lib/messaging-adapter';
// MessagingAdapter 會自動選擇 v1 或 v2
```

### Q6: v2 支援群組對話嗎?

**答**: 目前不支援。v2 仍是兩人對話設計。群組功能需要額外的架構設計。

---

## 🛠️ 故障排除

### 安裝失敗

```bash
# 檢查 PostgreSQL 版本
psql --version  # 需要 14+

# 檢查用戶權限
psql -c "SELECT current_user, session_user;"

# 查看錯誤日誌
tail -f /var/log/postgresql/postgresql.log
```

### 遷移錯誤

```sql
-- 查看遷移錯誤詳情
SELECT errors FROM migrate_conversations_v1_to_v2(10, 0);

-- 重置並重新遷移
TRUNCATE TABLE conversation_messages_v2;
TRUNCATE TABLE conversation_items_v2;
TRUNCATE TABLE conversations_v2 CASCADE;
```

### 效能問題

```sql
-- 重建索引
REINDEX TABLE conversations_v2;
REINDEX TABLE conversation_messages_v2;

-- 更新統計資訊
ANALYZE conversations_v2;
ANALYZE conversation_messages_v2;
```

---

## 🎓 學習資源

### 官方文件

- [Supabase RLS 指南](https://supabase.com/docs/guides/auth/row-level-security)
- [PostgreSQL 效能優化](https://www.postgresql.org/docs/current/performance-tips.html)
- [Supabase Realtime](https://supabase.com/docs/guides/realtime)

### 內部文件

- [v1 架構說明](./用戶通訊模組架構說明.md)
- [v1 改造方案](./角色互換改造方案.md)

---

## 📞 支援

### 技術問題

- 📧 Email: tech-support@example.com
- 💬 Slack: #messaging-v2
- 🐛 GitHub Issues: [提交 Bug](https://github.com/your-org/your-repo/issues)

### 緊急聯絡

- 🚨 緊急熱線: +886-XXX-XXXX
- ⏰ 值班時間: 24/7

---

## 📅 版本歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 2.0.0 | 2024-01-XX | 初始發布 |
| 2.0.1 | TBD | Bug 修復與優化 |

---

## 📝 授權

本專案採用 MIT 授權條款。

---

## 🙏 貢獻者

感謝以下貢獻者的努力:

- [@your-name] - 架構設計與實作
- [@team-member-1] - 測試與文件
- [@team-member-2] - 前端整合

---

**最後更新**: 2024-01-XX  
**文件版本**: 1.0.0  
**維護者**: Development Team