好的,這是一份基於顧問建議制定的改善計畫實施方案文件,包含詳細的實作說明與一份清晰的 TODO 清單,可供您的開發團隊直接參考與執行。

---

### **訊息系統改善計畫實施方案**

*   **文件版本**: 1.1
*   **制定日期**: 2025-11-07
*   **最後更新**: 2025-11-08
*   **目標**: 根據外部顧問的評估報告,針對現有的 Supabase 訊息功能後端設計進行優化,以提升系統的**安全性、效能、穩定性**與**未來擴充性**。

---

### **第一部分：實施項目與說明**

我們將改善計畫分為三個優先級 (P0, P1, P2) 來執行，確保最重要的項目能被優先處理。

#### **P0：最高優先級 (安全性與穩定性)**

這些項目涉及系統的核心安全與資料完整性，必須最優先實施。

##### **任務 1：實作 RLS (Row Level Security) 策略**

*   **目標**：防止未授權的資料存取，尤其是在使用 Supabase Realtime 時，確保使用者只能監聽與存取自身相關的對話與訊息，彌補重大安全漏洞。
*   **實作說明**：
    1.  為 `public.conversations` 資料表啟用 RLS。
    2.  為 `public.conversations` 建立政策，只允許對話參與者 (`buyer_id` 或 `seller_id`) 進行讀取 (`SELECT`)。
    3.  為 `public.conversation_messages` 資料表啟用 RLS。
    4.  為 `public.conversation_messages` 建立政策，允許對話參與者讀取 (`SELECT`) 訊息。
    5.  為 `public.conversation_messages` 建立政策，只允許對話參與者在對話中插入 (`INSERT`) 新訊息，且 `sender_id` 必須是當前使用者。

*   **SQL 腳本**：
    ```sql
    -- 啟用 RLS
    ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.conversation_messages ENABLE ROW LEVEL SECURITY;

    -- 建立 conversations 資料表的政策
    CREATE POLICY "Allow read for conversation participants"
    ON public.conversations FOR SELECT
    TO authenticated
    USING (buyer_id = auth.uid() OR seller_id = auth.uid());

    -- 建立 conversation_messages 資料表的讀取政策
    CREATE POLICY "Allow read for conversation participants on messages"
    ON public.conversation_messages FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.conversations c
            WHERE c.id = conversation_id
            AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
        )
    );

    -- 建立 conversation_messages 資料表的插入政策
    CREATE POLICY "Allow insert for conversation participants on messages"
    ON public.conversation_messages FOR INSERT
    TO authenticated
    WITH CHECK (
        sender_id = auth.uid() AND
        EXISTS (
            SELECT 1 FROM public.conversations c
            WHERE c.id = conversation_id
            AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
        )
    );
    ```
*   **⚠️ 重要提醒**：一旦啟用 RLS，所有未符合政策的資料庫查詢（**包含在 RPC 函數中的查詢**）都將失敗。必須在 Staging 環境進行完整的功能回歸測試。

##### **任務 2：建立唯一索引以防止重複對話** ✅ **已完成**

*   **目標**：解決高併發下可能產生的重複對話問題 (Race Condition)，從資料庫層級確保資料的唯一性與完整性。
*   **完成日期**: 2025-11-08
*   **實作檔案**: `supabase/migrations/20251108050033_idx_conversations_item_buyer_unique.sql`
*   **實作說明**：
    1.  ✅ 在 `conversations` 表上針對 `(item_id, buyer_id)` 建立一個 `UNIQUE` 複合索引。
    2.  ✅ 修改 `create_or_get_conversation` 函數，使用 `ON CONFLICT` 語句來處理插入衝突。
    3.  ✅ 新增效能索引 (`buyer_id, updated_at`) 和 (`seller_id, updated_at`) 以加速查詢。
    4.  ✅ 實作自動資料清理機制，移除可能存在的重複對話。
    5.  ✅ 新增 `get_conversations_by_ids` 輔助函數，避免 N+1 查詢問題。

*   **已實作的 SQL 腳本**：
    ```sql
    -- 1. 建立唯一索引
    CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_item_buyer_unique
    ON public.conversations(item_id, buyer_id);

    -- 2. 建立效能索引
    CREATE INDEX IF NOT EXISTS idx_conversations_buyer_updated
    ON public.conversations(buyer_id, updated_at DESC);

    CREATE INDEX IF NOT EXISTS idx_conversations_seller_updated
    ON public.conversations(seller_id, updated_at DESC);

    -- 3. 優化函數使用 ON CONFLICT
    CREATE OR REPLACE FUNCTION public.create_or_get_conversation(p_item_id BIGINT)
    RETURNS TABLE (...) AS $$
    BEGIN
        -- 使用 UPSERT 確保原子性
        INSERT INTO public.conversations (item_id, buyer_id, seller_id)
        VALUES (p_item_id, v_current_uid, v_item_user_id)
        ON CONFLICT (item_id, buyer_id)
        DO UPDATE SET updated_at = now()
        RETURNING id INTO v_conversation_id;
        -- ...
    END;
    $$ LANGUAGE plpgsql;
    ```

*   **實作亮點**：
    -   🎯 **併發安全**: 透過唯一索引 + ON CONFLICT 確保在高併發情況下不會產生重複對話
    -   ⚡ **效能提升**: 新增的索引大幅提升買家/賣家查詢對話列表的速度
    -   🧹 **自動清理**: Migration 執行時會自動檢測並清理已存在的重複資料
    -   🔒 **SECURITY DEFINER**: 函數使用安全定義者模式，搭配明確的 search_path
    -   📊 **批次查詢**: 新增的輔助函數支援一次查詢多個對話，避免 N+1 問題

---

#### **P1：次高優先級 (效能優化)**

此項目旨在解決潛在的效能瓶頸，對於保障大規模用戶下的系統流暢度至關重要。

##### **任務 3：優化 `get_user_conversations` 函數以解決 N+1 問題**

*   **目標**：移除 `get_user_conversations` 函數中的相關子查詢，避免因訊息量增大而導致的查詢效能急劇下降。
*   **實作說明**：提供兩種方案，**方案 A 為建議首選**。

    *   **方案 A (建議)：新增冗餘欄位**
        1.  在 `conversations` 資料表新增欄位，用於儲存最新訊息的快照：
            *   `last_message_content TEXT`
            *   `last_message_sent_at TIMESTAMPTZ`
            *   `last_message_sender_id UUID`
        2.  修改 `update_conversation_timestamp` 觸發器函數，在插入新訊息時，不僅更新 `updated_at`，同時更新上述三個冗餘欄位。
        3.  修改 `get_user_conversations` 函數，移除獲取最新訊息的子查詢，直接讀取 `conversations` 表中的新欄位。

    *   **方案 B (替代方案)：使用 `LATERAL JOIN`**
        1.  若不希望修改資料表結構，可以將 `get_user_conversations` 函數中的子查詢改寫為 `LATERAL JOIN`，以獲得更好的查詢效能。
        2.  此方案無需修改 Table Schema，但效能提升可能不如方案 A 顯著。

*   **SQL 腳本 (方案 A - 修改觸發器範例)**：
    ```sql
    -- 觸發器函數需要擴充
    CREATE OR REPLACE FUNCTION update_conversation_meta()
    RETURNS TRIGGER AS $$
    BEGIN
        UPDATE public.conversations
        SET
            updated_at = NEW.sent_at,
            last_message_content = NEW.content,
            last_message_sent_at = NEW.sent_at,
            last_message_sender_id = NEW.sender_id
        WHERE id = NEW.conversation_id;
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    -- 記得更新觸發器綁定
    DROP TRIGGER IF EXISTS trigger_update_conversation_on_new_message ON public.conversation_messages;
    CREATE TRIGGER trigger_update_conversation_on_new_message
        AFTER INSERT ON public.conversation_messages
        FOR EACH ROW EXECUTE FUNCTION update_conversation_meta();
    ```

---

#### **P2：建議實作 (開發體驗與未來擴充)**

這些項目能簡化前端開發、提升程式碼品質，並為未來的功能擴充做好準備。

##### **任務 4：優化 `send_message` 函數的回傳值**

*   **目標**：讓 `send_message` 函數成功後回傳包含發送者資訊的完整訊息物件，減少前端的處理負擔。
*   **實作說明**：修改 `send_message` 函數的 `RETURN QUERY` 部分，`JOIN public.users` 表以附加上 `sender_nickname` 和 `sender_profile_picture`。

*   **SQL 腳本 (修改部分)**：
    ```sql
    -- ... 在 send_message 函數的結尾
    RETURN QUERY
    SELECT
        cm.id,
        cm.sender_id,
        u.nickname, -- 新增
        u.profile_picture_url, -- 新增
        cm.content,
        cm.is_read,
        cm.sent_at
    FROM public.conversation_messages cm
    JOIN public.users u ON cm.sender_id = u.id -- 使用 JOIN
    WHERE cm.id = v_message_id;
    ```

##### **任務 5：為未來功能（軟刪除、多媒體訊息）預留欄位**

*   **目標**：在資料庫中預先規劃欄位，使未來實作軟刪除、圖片或檔案訊息等功能時，無需進行破壞性的資料庫結構變更。
*   **實作說明**：
    1.  在 `conversations` 和 `conversation_messages` 表中新增 `deleted_at TIMESTAMPTZ NULL` 欄位。
    2.  在 `conversation_messages` 表中新增 `message_type TEXT NOT NULL DEFAULT 'text'` 和 `metadata JSONB NULL` 欄位，`metadata` 可用來儲存圖片 URL、檔案大小等資訊。

*   **SQL 腳本**：
    ```sql
    ALTER TABLE public.conversation_messages
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS message_type TEXT NOT NULL DEFAULT 'text',
    ADD COLUMN IF NOT EXISTS metadata JSONB NULL;

    ALTER TABLE public.conversations
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL;
    ```

---

### **第二部分：TODO 清單**

#### **P0：最高優先級**
-   [ ] **任務 1: RLS**
    -   [ ] 為 `conversations` 表啟用 RLS。
    -   [ ] 為 `conversations` 表建立 `SELECT` 政策。
    -   [ ] 為 `conversation_messages` 表啟用 RLS。
    -   [ ] 為 `conversation_messages` 表建立 `SELECT` 政策。
    -   [ ] 為 `conversation_messages` 表建立 `INSERT` 政策。
    -   [ ] 在 Staging 環境對所有訊息相關功能進行完整回歸測試。
-   [x] **任務 2: 唯一索引** ✅ **已完成 (2025-11-08)**
    -   [x] 在 `conversations` 表上新增 `(item_id, buyer_id)` 的唯一索引。
    -   [x] 更新 `create_or_get_conversation` 函數以處理 `ON CONFLICT`。
    -   [x] 新增效能索引以加速買家/賣家查詢。
    -   [x] 實作自動資料清理機制。
    -   [x] 新增 `get_conversations_by_ids` 批次查詢函數。
    -   [x] 加入完整的錯誤處理與註解說明。

#### **P1：次高優先級**
-   [ ] **任務 3: 效能優化**
    -   [ ] 團隊決策採用方案 A 或方案 B。
    -   [ ] **若採方案 A**:
        -   [ ] 在 `conversations` 表新增 `last_message_*` 等冗餘欄位。
        -   [ ] 撰寫資料回填 (backfill) 腳本，為現有對話填上最新訊息。
        -   [ ] 更新資料庫觸發器函數 `update_conversation_meta`。
        -   [ ] 更新 `get_user_conversations` RPC 函數以使用新欄位。
    -   [ ] **若採方案 B**:
        -   [ ] 修改 `get_user_conversations` RPC 函數，將子查詢替換為 `LATERAL JOIN`。
    -   [ ] 進行壓力測試，驗證效能改善符合預期。

#### **P2：建議實作**
-   [ ] **任務 4: 優化 `send_message` 回傳值**
    -   [ ] 修改 `send_message` RPC 函數的回傳查詢。
    -   [ ] 通知前端團隊調整對應的 API 回應處理邏輯。
-   [ ] **任務 5: 預留未來功能欄位**
    -   [ ] 在 `conversations` 表新增 `deleted_at` 欄位。
    -   [ ] 在 `conversation_messages` 表新增 `deleted_at`, `message_type`, `metadata` 欄位。

---

### **第三部分：已完成項目詳情**

#### **✅ 任務 2: 唯一索引防止重複對話 (2025-11-08)**

**Migration 檔案**: `20251108050033_idx_conversations_item_buyer_unique.sql`

**完成內容**:
1. **唯一索引**: 建立 `idx_conversations_item_buyer_unique` 確保 `(item_id, buyer_id)` 組合的唯一性
2. **效能索引**:
   - `idx_conversations_buyer_updated`: 加速買家查詢
   - `idx_conversations_seller_updated`: 加速賣家查詢
3. **函數優化**: `create_or_get_conversation` 使用 `INSERT ... ON CONFLICT` 實現原子性 UPSERT
4. **新增函數**: `get_conversations_by_ids` 支援批次查詢，避免 N+1 問題
5. **資料清理**: 自動檢測並移除重複對話（保留最早建立的）
6. **安全性**: 使用 `SECURITY DEFINER` 並明確設定 `search_path`
7. **完整註解**: 所有索引和函數都有詳細的說明文件

**效能影響**:
- ✅ 防止併發寫入導致的重複資料
- ✅ 查詢對話列表效能提升 (透過索引)
- ✅ 減少前端 N+1 查詢問題

**測試建議**:
- [ ] 併發測試: 同時發送多個建立對話請求，確認不會產生重複
- [ ] 效能測試: 測量查詢對話列表的執行時間
- [ ] 功能測試: 確認現有功能正常運作
- [ ] 資料一致性: 檢查資料庫中沒有重複對話
