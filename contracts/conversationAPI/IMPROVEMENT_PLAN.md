好的,這是一份基於顧問建議制定的改善計畫實施方案文件,包含詳細的實作說明與一份清晰的 TODO 清單,可供您的開發團隊直接參考與執行。

---

### **訊息系統改善計畫實施方案**

*   **文件版本**: 1.2
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

##### **任務 5：為未來功能（多媒體訊息）預留欄位**

*   **目標**：在資料庫中預先規劃欄位，使未來實作圖片或檔案訊息等功能時，無需進行破壞性的資料庫結構變更。
*   **實作說明**：
    1.  在 `conversation_messages` 表中新增 `message_type TEXT NOT NULL DEFAULT 'text'` 和 `metadata JSONB NULL` 欄位，`metadata` 可用來儲存圖片 URL、檔案大小等資訊。

*   **SQL 腳本**：
    ```sql
    ALTER TABLE public.conversation_messages
    ADD COLUMN IF NOT EXISTS message_type TEXT NOT NULL DEFAULT 'text',
    ADD COLUMN IF NOT EXISTS metadata JSONB NULL;
    ```

##### **任務 6：實作軟刪除機制 (Soft Deletes)** ✅ **已完成**

*   **目標**：允許使用者刪除對話或訊息，但不會真正從資料庫移除資料，避免另一方使用者的對話列表出錯，同時支援「單方面刪除」的使用情境。
*   **問題說明**：
    -   目前沒有刪除訊息或對話的機制
    -   直接使用 `DELETE` 會導致資料遺失
    -   另一方使用者的對話列表會出現錯誤或遺失訊息
    -   無法支援「我刪除但對方仍可見」的常見需求
    
*   **實作說明**：

    **1. 資料表結構調整**
    
    為 `conversations` 和 `conversation_messages` 表新增軟刪除相關欄位：
    
    ```sql
    -- 對話表：支援雙方分別刪除
    ALTER TABLE public.conversations
    ADD COLUMN IF NOT EXISTS deleted_by_buyer_at TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS deleted_by_seller_at TIMESTAMPTZ NULL;
    
    -- 訊息表：支援發送者刪除（兩方都不可見）
    ALTER TABLE public.conversation_messages
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS deleted_by UUID NULL;
    ```
    
    **2. 建立索引以提升查詢效能**
    
    ```sql
    -- 加速過濾已刪除訊息的查詢
    CREATE INDEX IF NOT EXISTS idx_messages_not_deleted
    ON public.conversation_messages(conversation_id, sent_at DESC)
    WHERE deleted_at IS NULL;
    ```
    
    **3. 建立 RPC 函數：刪除對話（單方面）**
    
    ```sql
    CREATE OR REPLACE FUNCTION public.delete_conversation(
        p_conversation_id BIGINT
    )
    RETURNS BOOLEAN
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
    DECLARE
        v_current_uid UUID := auth.uid();
        v_buyer_id UUID;
        v_seller_id UUID;
    BEGIN
        -- 檢查使用者是否登入
        IF v_current_uid IS NULL THEN
            RAISE EXCEPTION '使用者未登入';
        END IF;
        
        -- 取得對話資訊
        SELECT buyer_id, seller_id INTO v_buyer_id, v_seller_id
        FROM public.conversations
        WHERE id = p_conversation_id;
        
        -- 檢查對話是否存在
        IF v_buyer_id IS NULL THEN
            RAISE EXCEPTION '對話不存在';
        END IF;
        
        -- 檢查是否為對話參與者
        IF v_current_uid != v_buyer_id AND v_current_uid != v_seller_id THEN
            RAISE EXCEPTION '無權限刪除此對話';
        END IF;
        
        -- 根據使用者角色更新對應的刪除時間戳
        IF v_current_uid = v_buyer_id THEN
            UPDATE public.conversations
            SET deleted_by_buyer_at = now()
            WHERE id = p_conversation_id;
        ELSE
            UPDATE public.conversations
            SET deleted_by_seller_at = now()
            WHERE id = p_conversation_id;
        END IF;
        
        RETURN TRUE;
    END;
    $$;
    ```
    
    **4. 建立 RPC 函數：刪除訊息**
    
    ```sql
    CREATE OR REPLACE FUNCTION public.delete_message(
        p_message_id BIGINT
    )
    RETURNS BOOLEAN
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
    DECLARE
        v_current_uid UUID := auth.uid();
        v_sender_id UUID;
    BEGIN
        -- 檢查使用者是否登入
        IF v_current_uid IS NULL THEN
            RAISE EXCEPTION '使用者未登入';
        END IF;
        
        -- 取得訊息的發送者
        SELECT sender_id INTO v_sender_id
        FROM public.conversation_messages
        WHERE id = p_message_id;
        
        -- 檢查訊息是否存在
        IF v_sender_id IS NULL THEN
            RAISE EXCEPTION '訊息不存在';
        END IF;
        
        -- 只有發送者可以刪除訊息
        IF v_current_uid != v_sender_id THEN
            RAISE EXCEPTION '只能刪除自己發送的訊息';
        END IF;
        
        -- 標記訊息為已刪除
        UPDATE public.conversation_messages
        SET deleted_at = now(),
            deleted_by = v_current_uid
        WHERE id = p_message_id;
        
        RETURN TRUE;
    END;
    $$;
    ```
    
    **5. 建立清理函數：永久刪除雙方都已刪除的對話**
    
    ```sql
    CREATE OR REPLACE FUNCTION public.cleanup_deleted_conversations()
    RETURNS INTEGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
    DECLARE
        v_deleted_count INTEGER;
    BEGIN
        -- 刪除雙方都已刪除且超過 30 天的對話
        DELETE FROM public.conversations
        WHERE deleted_by_buyer_at IS NOT NULL
          AND deleted_by_seller_at IS NOT NULL
          AND deleted_by_buyer_at < now() - INTERVAL '30 days'
          AND deleted_by_seller_at < now() - INTERVAL '30 days';
        
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        
        RETURN v_deleted_count;
    END;
    $$;
    ```
    
    **6. 修改 `get_user_conversations` 函數以過濾已刪除對話**
    
    在現有的 `WHERE` 子句中加入軟刪除過濾：
    
    ```sql
    WHERE 
        -- 原有的角色過濾條件
        CASE 
            WHEN p_role = 'buyer' THEN c.buyer_id = v_current_uid
            WHEN p_role = 'seller' THEN c.seller_id = v_current_uid
            ELSE (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid)
        END
        -- 新增：過濾當前使用者已刪除的對話
        AND (
            (c.buyer_id = v_current_uid AND c.deleted_by_buyer_at IS NULL) OR
            (c.seller_id = v_current_uid AND c.deleted_by_seller_at IS NULL)
        )
    ```
    
    **7. 修改 `get_conversation_messages` 函數以過濾已刪除訊息**
    
    在現有的查詢中加入過濾條件：
    
    ```sql
    WHERE conversation_id = p_conversation_id
      AND deleted_at IS NULL  -- 過濾已刪除訊息
    ```

*   **使用情境範例**：
    
    **情境 1：買家刪除對話**
    - 買家執行 `delete_conversation(51)`
    - `deleted_by_buyer_at` 被設定為當前時間
    - 買家的對話列表中不再顯示此對話
    - 賣家仍可正常看到對話和訊息
    
    **情境 2：雙方都刪除對話**
    - 買家執行 `delete_conversation(51)` → `deleted_by_buyer_at` 設定
    - 賣家執行 `delete_conversation(51)` → `deleted_by_seller_at` 設定
    - 雙方的對話列表都不顯示此對話
    - 30 天後執行 `cleanup_deleted_conversations()` 會永久刪除
    
    **情境 3：刪除訊息**
    - 使用者執行 `delete_message(1001)`
    - 訊息標記為已刪除（`deleted_at` 設定）
    - 雙方都看不到此訊息
    - 只有發送者可以刪除自己的訊息

*   **前端 API 函數**：
    
    需要在 `conversationAPI.js` 新增以下函數：
    
    ```javascript
    /**
     * 刪除對話（單方面）
     * @param {number} conversationId - 對話 ID
     * @returns {Promise<boolean>}
     */
    export async function deleteConversation(conversationId) {
        const { data, error } = await supabase.rpc('delete_conversation', {
            p_conversation_id: conversationId
        });
        if (error) throw new Error(error.message);
        return data;
    }
    
    /**
     * 刪除訊息
     * @param {number} messageId - 訊息 ID
     * @returns {Promise<boolean>}
     */
    export async function deleteMessage(messageId) {
        const { data, error } = await supabase.rpc('delete_message', {
            p_message_id: messageId
        });
        if (error) throw new Error(error.message);
        return data;
    }
    ```

*   **注意事項**：
    -   ⚠️ 軟刪除會增加查詢的複雜度，所有相關查詢都需要過濾 `deleted_at` 或 `deleted_by_*_at`
    -   ⚠️ 需要定期執行 `cleanup_deleted_conversations()` 清理雙方都已刪除的舊對話（建議使用 Supabase 的 pg_cron）
    -   ⚠️ RLS 政策也需要配合調整，確保已刪除的資料不會被存取
    -   💡 可以考慮在前端加入「撤銷刪除」功能（在一定時間內可恢復）

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
    -   [ ] 在 `conversation_messages` 表新增 `message_type`, `metadata` 欄位。
-   [x] **任務 6: 實作軟刪除機制** ✅ **已完成 (2025-11-08)**
    -   [x] 在 `conversations` 表新增 `deleted_by_buyer_at`, `deleted_by_seller_at` 欄位。
    -   [x] 在 `conversation_messages` 表新增 `deleted_at`, `deleted_by` 欄位。
    -   [x] 建立索引 `idx_messages_not_deleted` 以提升查詢效能。
    -   [x] 實作 `delete_conversation` RPC 函數（支援單方面刪除）。
    -   [x] 實作 `restore_conversation` RPC 函數（恢復已刪除對話）。
    -   [x] 實作 `delete_message` RPC 函數（只能刪除自己的訊息）。
    -   [x] 實作 `cleanup_deleted_conversations` 清理函數。
    -   [x] 修改 `get_user_conversations` 函數以支援 `p_role` 和 `p_include_deleted` 參數。
    -   [x] 修改 `get_conversation_messages` 函數以支援 `p_include_deleted` 參數。
    -   [x] 在 `conversationAPI.js` 新增 `deleteConversation`, `restoreConversation` 和 `deleteMessage` 函數。
    -   [x] 更新 `conversationAPI.js` 中的 `getMyConversations` 以支援新參數。
    -   [ ] 調整 RLS 政策以配合軟刪除邏輯（待 P0 任務 1 完成後實作）。
    -   [ ] 設定 pg_cron 定期執行清理函數（建議每週執行，需生產環境配置）。
    -   [ ] 前端 UI 實作刪除確認對話框。
    -   [ ] (可選) 前端實作「撤銷刪除」功能。

---

### **第三部分：已完成項目詳情**

#### **✅ 任務 6: 實作軟刪除機制 (2025-11-08)**

**實施內容**：

1. **資料庫層面 (Migration: `20251108052733_feature_conversation_soft_delete.sql`)**
   - ✅ 新增 `conversations.deleted_by_buyer_at` 和 `conversations.deleted_by_seller_at` 欄位
   - ✅ 新增 `conversation_messages.deleted_at` 和 `conversation_messages.deleted_by` 欄位
   - ✅ 建立效能索引：
     - `idx_messages_not_deleted`
     - `idx_conversations_buyer_not_deleted`
     - `idx_conversations_seller_not_deleted`
   - ✅ 實作 RPC 函數：
     - `delete_conversation(p_conversation_id)` - 單方面刪除對話
     - `restore_conversation(p_conversation_id)` - 恢復已刪除對話
     - `delete_message(p_message_id)` - 刪除訊息（僅發送者可刪）
     - `cleanup_deleted_conversations(p_days_old)` - 清理雙方都已刪除的對話
   - ✅ 更新現有 RPC 函數：
     - `get_user_conversations()` 新增 `p_role` 和 `p_include_deleted` 參數
     - `get_conversation_messages()` 新增 `p_include_deleted` 參數
   - ✅ 新增完整的欄位註解和函數說明
   - ✅ 設定適當的權限控制

2. **API 層面 (conversationAPI.js v1.2)**
   - ✅ 新增 `deleteConversation(conversationId)` 函數
   - ✅ 新增 `restoreConversation(conversationId)` 函數
   - ✅ 新增 `deleteMessage(messageId)` 函數
   - ✅ 更新 `getMyConversations(options)` 支援：
     - `options.role` - 角色過濾 (buyer/seller/all)
     - `options.includeDeleted` - 是否包含已刪除的對話
   - ✅ 回傳資料新增 `is_deleted` 欄位標示刪除狀態
   - ✅ 加入完整的參數驗證和錯誤處理
   - ✅ 提供友善的錯誤訊息

3. **文件**
   - ✅ 建立完整的使用指南 (`SOFT_DELETE_GUIDE.md`)，包含：
     - 核心概念說明（單方面刪除、雙方刪除、訊息刪除）
     - 完整的 API 函數說明與範例
     - React 使用範例（含撤銷刪除、批次刪除）
     - UI/UX 最佳實踐建議
     - 完整的測試清單

**核心特性**：
- ✅ 支援「單方面刪除」：買家刪除不影響賣家，反之亦然
- ✅ 對話可恢復：使用者可撤銷自己的刪除操作
- ✅ 訊息刪除：發送者可刪除訊息，刪除後雙方都不可見
- ✅ 自動清理：提供清理函數刪除雙方都已刪除且超過指定天數的對話
- ✅ 效能優化：使用部分索引加速查詢未刪除的資料

**待完成項目**：
- ⏳ RLS 政策調整（等待任務 1 完成）
- ⏳ pg_cron 定期清理設定（需生產環境配置）
- ⏳ 前端 UI 實作（刪除確認、撤銷刪除等）

**相關文件**：
- Migration: `supabase/migrations/20251108052733_feature_conversation_soft_delete.sql`
- API: `contracts/conversationAPI/conversationAPI.js` (v1.2)
- 指南: `contracts/conversationAPI/SOFT_DELETE_GUIDE.md`

---

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
