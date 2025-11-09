-- =====================================================
-- 📨 二手交易平台 - 用戶通訊功能完整模組
-- =====================================================
-- 版本: 1.4 (Production Ready)
-- 建立日期: 2025-11-10
-- 說明: 整合所有通訊功能相關的資料表、函數、索引、RLS 策略
-- =====================================================

-- =====================================================
-- 🗂️ 第一部分: 資料表結構
-- =====================================================

-- 1.1 檢查並建立 conversations 表的軟刪除欄位
DO $$
BEGIN
    -- 新增 deleted_by_buyer_at 欄位 (如果不存在)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'conversations'
          AND column_name = 'deleted_by_buyer_at'
    ) THEN
        ALTER TABLE public.conversations
        ADD COLUMN deleted_by_buyer_at TIMESTAMPTZ;
    END IF;

    -- 新增 deleted_by_seller_at 欄位 (如果不存在)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'conversations'
          AND column_name = 'deleted_by_seller_at'
    ) THEN
        ALTER TABLE public.conversations
        ADD COLUMN deleted_by_seller_at TIMESTAMPTZ;
    END IF;
END $$;

-- 1.2 檢查並建立 conversation_messages 表的軟刪除欄位
DO $$
BEGIN
    -- 新增 deleted_at 欄位 (如果不存在)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'conversation_messages'
          AND column_name = 'deleted_at'
    ) THEN
        ALTER TABLE public.conversation_messages
        ADD COLUMN deleted_at TIMESTAMPTZ;
    END IF;
END $$;

-- =====================================================
-- 🔑 第二部分: 索引建立
-- =====================================================

-- 2.1 唯一索引: 防止同一物品、同一買家重複建立對話 (解決 Race Condition)
CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_item_buyer_unique
ON public.conversations(item_id, buyer_id);

-- 2.2 效能索引: 加速買家查詢自己的對話列表
CREATE INDEX IF NOT EXISTS idx_conversations_buyer_updated
ON public.conversations(buyer_id, updated_at DESC);

-- 2.3 效能索引: 加速賣家查詢自己的對話列表
CREATE INDEX IF NOT EXISTS idx_conversations_seller_updated
ON public.conversations(seller_id, updated_at DESC);

-- 2.4 效能索引: 加速對話時間排序
CREATE INDEX IF NOT EXISTS idx_conversations_updated_at
ON public.conversations(updated_at DESC);

-- 2.5 複合索引: 優化未讀訊息查詢 (部分索引)
CREATE INDEX IF NOT EXISTS idx_conversation_messages_unread
ON public.conversation_messages(conversation_id, sender_id, is_read)
WHERE is_read = false;

-- =====================================================
-- 🔄 第三部分: 資料庫觸發器
-- =====================================================

-- 3.1 建立觸發器函數: 當新訊息發送時自動更新對話的 updated_at
CREATE OR REPLACE FUNCTION update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.conversations
    SET updated_at = NEW.sent_at
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3.2 建立觸發器: 當新訊息插入時自動更新對話時間
DROP TRIGGER IF EXISTS trigger_update_conversation_on_new_message ON public.conversation_messages;
CREATE TRIGGER trigger_update_conversation_on_new_message
    AFTER INSERT ON public.conversation_messages
    FOR EACH ROW EXECUTE FUNCTION update_conversation_timestamp();

-- =====================================================
-- 📡 第四部分: Realtime 功能啟用
-- =====================================================

-- 4.1 為 conversations 表啟用 Realtime
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'conversations'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
    END IF;
END $$;

-- 4.2 為 conversation_messages 表啟用 Realtime
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'conversation_messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_messages;
    END IF;
END $$;

-- =====================================================
-- 🔧 第五部分: RPC 函數 (Core Functions)
-- =====================================================

-- =====================================================
-- 5.1 create_or_get_conversation: 建立或取得對話
-- =====================================================
DROP FUNCTION IF EXISTS public.create_or_get_conversation(BIGINT);

CREATE OR REPLACE FUNCTION public.create_or_get_conversation(
    p_item_id BIGINT
)
RETURNS TABLE (
    conversation_id BIGINT,
    item_id BIGINT,
    buyer_id UUID,
    seller_id UUID,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID;
    v_item_user_id UUID;
    v_existing_conv_id BIGINT;
BEGIN
    -- 1. 取得當前使用者 ID
    v_current_uid := auth.uid();

    -- 2. 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入'
            USING HINT = '請先進行身份驗證',
                  ERRCODE = '42501';
    END IF;

    -- 3. 取得物品擁有者（只查詢上架中的物品）
    SELECT i.user_id INTO STRICT v_item_user_id
    FROM public.items i
    WHERE i.id = p_item_id
      AND i.listing_status = true;

    -- 4. 檢查是否為自己的物品
    IF v_item_user_id = v_current_uid THEN
        RAISE EXCEPTION '無法與自己的物品建立對話'
            USING HINT = '您不能對自己的商品發起對話',
                  ERRCODE = '23514';
    END IF;

    -- 5. 先檢查是否已存在對話
    SELECT c.id INTO v_existing_conv_id
    FROM public.conversations c
    WHERE c.item_id = p_item_id
      AND c.buyer_id = v_current_uid
    LIMIT 1;

    -- 6. 如果已存在，更新時間戳記並清除刪除標記
    IF v_existing_conv_id IS NOT NULL THEN
        UPDATE public.conversations
        SET updated_at = now(),
            deleted_by_buyer_at = NULL  -- 恢復對話
        WHERE id = v_existing_conv_id;
    ELSE
        -- 7. 如果不存在，建立新對話
        INSERT INTO public.conversations (item_id, buyer_id, seller_id)
        VALUES (p_item_id, v_current_uid, v_item_user_id)
        RETURNING id INTO v_existing_conv_id;
    END IF;

    -- 8. 使用子查詢返回結果，完全避免名稱衝突
    RETURN QUERY
    SELECT
        sub.conversation_id,
        sub.item_id,
        sub.buyer_id,
        sub.seller_id,
        sub.created_at,
        sub.updated_at
    FROM (
        SELECT
            c.id AS conversation_id,
            c.item_id AS item_id,
            c.buyer_id AS buyer_id,
            c.seller_id AS seller_id,
            c.created_at AS created_at,
            c.updated_at AS updated_at
        FROM public.conversations c
        WHERE c.id = v_existing_conv_id
    ) AS sub;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION '物品不存在或已下架'
            USING HINT = '請確認物品 ID 是否正確且物品處於上架狀態',
                  ERRCODE = '22023';
    WHEN OTHERS THEN
        RAISE NOTICE '建立對話時發生錯誤: %, SQLSTATE: %', SQLERRM, SQLSTATE;
        RAISE;
END;
$$;

COMMENT ON FUNCTION public.create_or_get_conversation(BIGINT) IS
'建立或取得對話 (使用子查詢避免 RETURNS TABLE 的名稱衝突)';

-- =====================================================
-- 5.2 get_user_conversations: 取得使用者的對話列表
-- =====================================================
DROP FUNCTION IF EXISTS public.get_user_conversations(INT, INT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION public.get_user_conversations(
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_role TEXT DEFAULT 'all',
    p_include_deleted BOOLEAN DEFAULT false
)
RETURNS TABLE (
    conversation_id BIGINT,
    item_id BIGINT,
    item_title TEXT,
    item_image_url TEXT,
    other_user_id UUID,
    other_user_nickname VARCHAR(50),
    other_user_profile_picture TEXT,
    last_message TEXT,
    last_message_time TIMESTAMPTZ,
    unread_count BIGINT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    is_deleted BOOLEAN
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_offset INT;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 驗證分頁參數
    IF p_page < 1 THEN
        RAISE EXCEPTION '頁碼必須大於 0';
    END IF;
    IF p_size < 1 OR p_size > 100 THEN
        RAISE EXCEPTION '每頁數量必須在 1 到 100 之間';
    END IF;

    -- 驗證 role 參數
    IF p_role NOT IN ('buyer', 'seller', 'all') THEN
        RAISE EXCEPTION 'role 參數必須是 buyer, seller 或 all';
    END IF;

    v_offset := (p_page - 1) * p_size;

    -- 使用 CTE 避免欄位名稱衝突
    RETURN QUERY
    WITH conversation_data AS (
        SELECT
            c.id,
            c.item_id,
            c.buyer_id,
            c.seller_id,
            c.created_at,
            c.updated_at,
            c.deleted_by_buyer_at,
            c.deleted_by_seller_at,
            i.title,
            i.image_urls,
            u_buyer.nickname AS buyer_nickname,
            u_buyer.profile_picture_url AS buyer_profile_picture,
            u_seller.nickname AS seller_nickname,
            u_seller.profile_picture_url AS seller_profile_picture
        FROM public.conversations c
        LEFT JOIN public.items i ON c.item_id = i.id
        LEFT JOIN public.users u_buyer ON c.buyer_id = u_buyer.id
        LEFT JOIN public.users u_seller ON c.seller_id = u_seller.id
        WHERE
            -- 根據 role 參數過濾
            CASE
                WHEN p_role = 'buyer' THEN c.buyer_id = v_current_uid
                WHEN p_role = 'seller' THEN c.seller_id = v_current_uid
                ELSE (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid)
            END
            -- 過濾當前使用者已刪除的對話
            AND (
                p_include_deleted = true OR
                (c.buyer_id = v_current_uid AND c.deleted_by_buyer_at IS NULL) OR
                (c.seller_id = v_current_uid AND c.deleted_by_seller_at IS NULL)
            )
    ),
    last_messages AS (
        SELECT DISTINCT ON (cm.conversation_id)
            cm.conversation_id,
            cm.content,
            cm.sent_at
        FROM public.conversation_messages cm
        WHERE cm.deleted_at IS NULL
        ORDER BY cm.conversation_id, cm.sent_at DESC
    ),
    unread_counts AS (
        SELECT
            cm.conversation_id,
            COUNT(*) AS count
        FROM public.conversation_messages cm
        WHERE cm.sender_id != v_current_uid
          AND cm.is_read = false
          AND cm.deleted_at IS NULL
        GROUP BY cm.conversation_id
    )
    SELECT
        cd.id::BIGINT,
        cd.item_id::BIGINT,
        cd.title::TEXT,
        cd.image_urls[1]::TEXT,
        CASE
            WHEN cd.buyer_id = v_current_uid THEN cd.seller_id
            ELSE cd.buyer_id
        END::UUID,
        CASE
            WHEN cd.buyer_id = v_current_uid THEN cd.seller_nickname
            ELSE cd.buyer_nickname
        END::VARCHAR(50),
        CASE
            WHEN cd.buyer_id = v_current_uid THEN cd.seller_profile_picture
            ELSE cd.buyer_profile_picture
        END::TEXT,
        lm.content::TEXT,
        lm.sent_at::TIMESTAMPTZ,
        COALESCE(uc.count, 0)::BIGINT,
        cd.created_at::TIMESTAMPTZ,
        cd.updated_at::TIMESTAMPTZ,
        CASE
            WHEN cd.buyer_id = v_current_uid THEN (cd.deleted_by_buyer_at IS NOT NULL)
            ELSE (cd.deleted_by_seller_at IS NOT NULL)
        END::BOOLEAN
    FROM conversation_data cd
    LEFT JOIN last_messages lm ON lm.conversation_id = cd.id
    LEFT JOIN unread_counts uc ON uc.conversation_id = cd.id
    ORDER BY cd.updated_at DESC
    LIMIT p_size OFFSET v_offset;
END;
$$;

COMMENT ON FUNCTION public.get_user_conversations(INT, INT, TEXT, BOOLEAN) IS
'取得使用者的對話列表(支援軟刪除、角色過濾、分頁)';

-- =====================================================
-- 5.3 get_conversation_messages: 取得對話的訊息列表
-- =====================================================
DROP FUNCTION IF EXISTS public.get_conversation_messages(BIGINT, INT, INT, BOOLEAN);

CREATE OR REPLACE FUNCTION public.get_conversation_messages(
    p_conversation_id BIGINT,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 50,
    p_include_deleted BOOLEAN DEFAULT false
)
RETURNS TABLE (
    message_id BIGINT,
    sender_id UUID,
    sender_nickname VARCHAR(50),
    sender_profile_picture TEXT,
    content TEXT,
    is_read BOOLEAN,
    sent_at TIMESTAMPTZ,
    is_deleted BOOLEAN,
    deleted_at TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_offset INT;
    v_is_participant BOOLEAN;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 驗證分頁參數
    IF p_page < 1 THEN
        RAISE EXCEPTION '頁碼必須大於 0';
    END IF;
    IF p_size < 1 OR p_size > 100 THEN
        RAISE EXCEPTION '每頁數量必須在 1 到 100 之間';
    END IF;

    -- 檢查使用者是否為對話參與者
    SELECT EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = p_conversation_id
          AND (buyer_id = v_current_uid OR seller_id = v_current_uid)
    ) INTO v_is_participant;

    IF NOT v_is_participant THEN
        RAISE EXCEPTION '無權限查看此對話'
            USING HINT = '您不是此對話的參與者',
                  ERRCODE = '42501';
    END IF;

    v_offset := (p_page - 1) * p_size;

    -- 返回訊息列表（使用 AS 明確指定所有欄位別名以避免歧義）
    RETURN QUERY
    SELECT
        cm.id AS message_id,
        cm.sender_id AS sender_id,
        u.nickname AS sender_nickname,
        u.profile_picture_url AS sender_profile_picture,
        cm.content AS content,
        cm.is_read AS is_read,
        cm.sent_at AS sent_at,
        (cm.deleted_at IS NOT NULL) AS is_deleted,
        cm.deleted_at AS deleted_at
    FROM public.conversation_messages cm
    LEFT JOIN public.users u ON cm.sender_id = u.id
    WHERE cm.conversation_id = p_conversation_id
      -- 過濾已刪除的訊息（除非 p_include_deleted = true）
      AND (p_include_deleted = true OR cm.deleted_at IS NULL)
    ORDER BY cm.sent_at ASC
    LIMIT p_size OFFSET v_offset;
END;
$$;

COMMENT ON FUNCTION public.get_conversation_messages(BIGINT, INT, INT, BOOLEAN) IS
'取得對話的訊息列表（支援軟刪除、分頁）';

-- =====================================================
-- 5.4 send_message: 發送訊息
-- =====================================================
DROP FUNCTION IF EXISTS public.send_message(BIGINT, TEXT);

CREATE OR REPLACE FUNCTION public.send_message(
    p_conversation_id BIGINT,
    p_content TEXT
)
RETURNS TABLE (
    message_id BIGINT,
    sender_id UUID,
    content TEXT,
    is_read BOOLEAN,
    sent_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID;
    v_new_message_id BIGINT;
BEGIN
    -- 1. 取得當前使用者
    v_current_uid := auth.uid();

    -- 2. 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入'
            USING HINT = '請先進行身份驗證',
                  ERRCODE = '42501';
    END IF;

    -- 3. 驗證訊息內容
    IF p_content IS NULL OR TRIM(p_content) = '' THEN
        RAISE EXCEPTION '訊息內容不能為空'
            USING HINT = '請輸入有效的訊息內容',
                  ERRCODE = '22023';
    END IF;

    -- 4. 驗證使用者是對話的參與者
    IF NOT EXISTS (
        SELECT 1
        FROM public.conversations c
        WHERE c.id = p_conversation_id
          AND (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid)
    ) THEN
        RAISE EXCEPTION '您不是此對話的參與者'
            USING HINT = '只有對話參與者可以發送訊息',
                  ERRCODE = '42501';
    END IF;

    -- 5. 插入新訊息
    INSERT INTO public.conversation_messages (
        conversation_id,
        sender_id,
        content
    )
    VALUES (
        p_conversation_id,
        v_current_uid,
        TRIM(p_content)
    )
    RETURNING id INTO v_new_message_id;

    -- 6. 更新對話的 updated_at 時間戳記
    UPDATE public.conversations
    SET updated_at = now()
    WHERE id = p_conversation_id;

    -- 7. 使用子查詢返回完整訊息資料 (避免名稱衝突)
    RETURN QUERY
    SELECT
        sub.message_id,
        sub.sender_id,
        sub.content,
        sub.is_read,
        sub.sent_at
    FROM (
        SELECT
            cm.id AS message_id,
            cm.sender_id AS sender_id,
            cm.content AS content,
            cm.is_read AS is_read,
            cm.sent_at AS sent_at
        FROM public.conversation_messages cm
        WHERE cm.id = v_new_message_id
    ) AS sub;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '發送訊息時發生錯誤: %, SQLSTATE: %', SQLERRM, SQLSTATE;
        RAISE;
END;
$$;

COMMENT ON FUNCTION public.send_message(BIGINT, TEXT) IS
'發送訊息到指定對話 (返回完整訊息物件)';

-- =====================================================
-- 5.5 mark_messages_as_read: 標記訊息為已讀
-- =====================================================
DROP FUNCTION IF EXISTS public.mark_messages_as_read(BIGINT);

CREATE OR REPLACE FUNCTION public.mark_messages_as_read(
    p_conversation_id BIGINT
)
RETURNS TABLE (
    updated_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
    v_count BIGINT;
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 檢查使用者是否為對話參與者
    IF NOT EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = p_conversation_id
          AND (buyer_id = v_current_uid OR seller_id = v_current_uid)
    ) THEN
        RAISE EXCEPTION '無權限修改此對話的訊息狀態';
    END IF;

    -- 更新訊息為已讀（只更新非自己發送的未讀訊息）
    UPDATE public.conversation_messages
    SET is_read = true
    WHERE conversation_id = p_conversation_id
      AND sender_id != v_current_uid
      AND is_read = false
      AND deleted_at IS NULL;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN QUERY SELECT v_count;
END;
$$;

COMMENT ON FUNCTION public.mark_messages_as_read(BIGINT) IS
'標記對話中所有未讀訊息為已讀 (只更新非自己發送的訊息)';

-- =====================================================
-- 5.6 get_unread_message_count: 取得未讀訊息總數
-- =====================================================
DROP FUNCTION IF EXISTS public.get_unread_message_count();

CREATE OR REPLACE FUNCTION public.get_unread_message_count()
RETURNS TABLE (
    unread_count BIGINT
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
BEGIN
    -- 檢查使用者是否登入
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    RETURN QUERY
    SELECT COUNT(*)
    FROM public.conversation_messages cm
    WHERE cm.sender_id != v_current_uid
      AND cm.is_read = false
      AND cm.deleted_at IS NULL
      AND EXISTS (
          SELECT 1 FROM public.conversations c
          WHERE c.id = cm.conversation_id
            AND (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid)
      );
END;
$$;

COMMENT ON FUNCTION public.get_unread_message_count() IS
'取得使用者的未讀訊息總數 (排除已刪除訊息)';

-- =====================================================
-- 5.7 get_conversations_by_ids: 批次取得對話資訊
-- =====================================================
DROP FUNCTION IF EXISTS public.get_conversations_by_ids(BIGINT[]);

CREATE OR REPLACE FUNCTION public.get_conversations_by_ids(
    p_conversation_ids BIGINT[]
)
RETURNS TABLE (
    conversation_id BIGINT,
    item_id BIGINT,
    buyer_id UUID,
    seller_id UUID,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    item_title TEXT,
    item_image_url TEXT
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_uid UUID := auth.uid();
BEGIN
    IF v_current_uid IS NULL THEN
        RAISE EXCEPTION '使用者未登入';
    END IF;

    -- 使用 CTE 避免欄位名稱衝突
    RETURN QUERY
    WITH conversation_data AS (
        SELECT
            c.id,
            c.item_id,
            c.buyer_id,
            c.seller_id,
            c.created_at,
            c.updated_at,
            i.title,
            i.image_urls
        FROM public.conversations c
        LEFT JOIN public.items i ON c.item_id = i.id
        WHERE c.id = ANY(p_conversation_ids)
          AND (c.buyer_id = v_current_uid OR c.seller_id = v_current_uid)
    )
    SELECT
        cd.id::BIGINT,
        cd.item_id::BIGINT,
        cd.buyer_id::UUID,
        cd.seller_id::UUID,
        cd.created_at::TIMESTAMPTZ,
        cd.updated_at::TIMESTAMPTZ,
        cd.title::TEXT,
        cd.image_urls[1]::TEXT
    FROM conversation_data cd;
END;
$$;

COMMENT ON FUNCTION public.get_conversations_by_ids(BIGINT[]) IS
'批次取得對話資訊，防止 N+1 查詢問題';

-- =====================================================
-- 🔒 第六部分: Row-Level Security (RLS) 策略
-- =====================================================

-- 6.1 啟用 RLS
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_messages ENABLE ROW LEVEL SECURITY;

-- 6.2 清除現有策略 (conversations)
DROP POLICY IF EXISTS "conversations_select_policy" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_policy" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_policy" ON public.conversations;
DROP POLICY IF EXISTS "conversations_delete_policy" ON public.conversations;

-- 6.3 清除現有策略 (conversation_messages)
DROP POLICY IF EXISTS "conversation_messages_select_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_insert_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_update_policy" ON public.conversation_messages;
DROP POLICY IF EXISTS "conversation_messages_delete_policy" ON public.conversation_messages;

-- 6.4 建立 conversations 表的 RLS 策略

-- SELECT: 使用者只能查看自己參與的對話
CREATE POLICY "conversations_select_policy"
ON public.conversations
FOR SELECT
TO authenticated
USING (
    buyer_id = auth.uid() OR seller_id = auth.uid()
);

-- INSERT: 使用者只能建立自己作為買家的對話
CREATE POLICY "conversations_insert_policy"
ON public.conversations
FOR INSERT
TO authenticated
WITH CHECK (
    buyer_id = auth.uid()
);

-- UPDATE: 對話參與者可以更新對話 (例如軟刪除)
CREATE POLICY "conversations_update_policy"
ON public.conversations
FOR UPDATE
TO authenticated
USING (
    buyer_id = auth.uid() OR seller_id = auth.uid()
)
WITH CHECK (
    buyer_id = auth.uid() OR seller_id = auth.uid()
);

-- 6.5 建立 conversation_messages 表的 RLS 策略

-- SELECT: 對話參與者可以查看訊息
CREATE POLICY "conversation_messages_select_policy"
ON public.conversation_messages
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.conversations c
        WHERE c.id = conversation_messages.conversation_id
          AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
);

-- INSERT: 對話參與者可以發送訊息 (且 sender_id 必須是自己)
CREATE POLICY "conversation_messages_insert_policy"
ON public.conversation_messages
FOR INSERT
TO authenticated
WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
        SELECT 1
        FROM public.conversations c
        WHERE c.id = conversation_messages.conversation_id
          AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
);

-- UPDATE: 對話參與者可以更新訊息 (例如標記為已讀)
CREATE POLICY "conversation_messages_update_policy"
ON public.conversation_messages
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.conversations c
        WHERE c.id = conversation_messages.conversation_id
          AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.conversations c
        WHERE c.id = conversation_messages.conversation_id
          AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
);

-- DELETE: 訊息發送者可以刪除自己的訊息
CREATE POLICY "conversation_messages_delete_policy"
ON public.conversation_messages
FOR DELETE
TO authenticated
USING (
    sender_id = auth.uid()
);

-- =====================================================
-- 🔑 第七部分: 權限授予
-- =====================================================

-- 7.1 授予表格權限
GRANT SELECT, INSERT, UPDATE ON public.conversations TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.conversation_messages TO authenticated;

-- 7.2 授予函數執行權限
GRANT EXECUTE ON FUNCTION public.create_or_get_conversation(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_conversations(INT, INT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_conversation_messages(BIGINT, INT, INT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_message(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_message_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_conversations_by_ids(BIGINT[]) TO authenticated;

-- =====================================================
-- 🧹 第八部分: 資料清理 (移除重複對話)
-- =====================================================

DO $$
DECLARE
    v_deleted_count INT;
BEGIN
    -- 刪除重複的對話（保留 id 最小的）
    WITH duplicates AS (
        SELECT
            id,
            ROW_NUMBER() OVER (
                PARTITION BY item_id, buyer_id
                ORDER BY id ASC
            ) as rn
        FROM public.conversations
    )
    DELETE FROM public.conversations
    WHERE id IN (
        SELECT id FROM duplicates WHERE rn > 1
    );

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    IF v_deleted_count > 0 THEN
        RAISE NOTICE '🧹 清理了 % 筆重複對話', v_deleted_count;
    ELSE
        RAISE NOTICE '✓ 沒有發現重複對話';
    END IF;
END $$;

-- =====================================================
-- ✅ 第九部分: 驗證與統計
-- =====================================================

DO $$
DECLARE
    v_total_conversations INT;
    v_total_messages INT;
    v_total_indexes INT;
    v_select_policies INT;
    v_insert_policies INT;
    v_update_policies INT;
    v_delete_policies INT;
    v_rls_enabled BOOLEAN;
BEGIN
    -- 統計對話總數
    SELECT COUNT(*) INTO v_total_conversations FROM public.conversations;

    -- 統計訊息總數
    SELECT COUNT(*) INTO v_total_messages FROM public.conversation_messages;

    -- 統計索引數量
    SELECT COUNT(*) INTO v_total_indexes
    FROM pg_indexes
    WHERE tablename IN ('conversations', 'conversation_messages')
      AND indexname LIKE 'idx_%';

    -- 統計 RLS 策略
    SELECT
        COUNT(*) FILTER (WHERE cmd = 'SELECT'),
        COUNT(*) FILTER (WHERE cmd = 'INSERT'),
        COUNT(*) FILTER (WHERE cmd = 'UPDATE'),
        COUNT(*) FILTER (WHERE cmd = 'DELETE')
    INTO
        v_select_policies,
        v_insert_policies,
        v_update_policies,
        v_delete_policies
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('conversations', 'conversation_messages');

    -- 檢查 RLS 是否啟用
    SELECT rowsecurity INTO v_rls_enabled
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename = 'conversations';

    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  📨 通訊功能模組部署完成！';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '📊 資料統計:';
    RAISE NOTICE '  - 對話總數: %', v_total_conversations;
    RAISE NOTICE '  - 訊息總數: %', v_total_messages;
    RAISE NOTICE '  - 索引數量: %', v_total_indexes;
    RAISE NOTICE '';
    RAISE NOTICE '🔒 安全策略:';
    RAISE NOTICE '  - RLS 啟用: %', CASE WHEN v_rls_enabled THEN '✅ 是' ELSE '❌ 否' END;
    RAISE NOTICE '  - SELECT 策略: % 個', v_select_policies;
    RAISE NOTICE '  - INSERT 策略: % 個', v_insert_policies;
    RAISE NOTICE '  - UPDATE 策略: % 個', v_update_policies;
    RAISE NOTICE '  - DELETE 策略: % 個', v_delete_policies;
    RAISE NOTICE '';
    RAISE NOTICE '🎯 已完成項目:';
    RAISE NOTICE '  ✅ 1. 建立軟刪除欄位';
    RAISE NOTICE '  ✅ 2. 建立唯一索引 (防止重複對話)';
    RAISE NOTICE '  ✅ 3. 建立效能索引 (5 個)';
    RAISE NOTICE '  ✅ 4. 建立自動更新觸發器';
    RAISE NOTICE '  ✅ 5. 啟用 Realtime 功能';
    RAISE NOTICE '  ✅ 6. 建立 7 個 RPC 函數';
    RAISE NOTICE '  ✅ 7. 設定 RLS 策略 (% 個)', v_select_policies + v_insert_policies + v_update_policies + v_delete_policies;
    RAISE NOTICE '  ✅ 8. 清理重複資料';
    RAISE NOTICE '';
    RAISE NOTICE '🔧 核心 RPC 函數:';
    RAISE NOTICE '  1. create_or_get_conversation(p_item_id)';
    RAISE NOTICE '  2. get_user_conversations(p_page, p_size, p_role, p_include_deleted)';
    RAISE NOTICE '  3. get_conversation_messages(p_conversation_id, p_page, p_size, p_include_deleted)';
    RAISE NOTICE '  4. send_message(p_conversation_id, p_content)';
    RAISE NOTICE '  5. mark_messages_as_read(p_conversation_id)';
    RAISE NOTICE '  6. get_unread_message_count()';
    RAISE NOTICE '  7. get_conversations_by_ids(p_conversation_ids)';
    RAISE NOTICE '';
    RAISE NOTICE '📡 Realtime 功能:';
    RAISE NOTICE '  - conversations 表: ✅ 已啟用';
    RAISE NOTICE '  - conversation_messages 表: ✅ 已啟用';
    RAISE NOTICE '';
    RAISE NOTICE '💡 下一步:';
    RAISE NOTICE '  1. 測試前端「聯絡賣家」功能';
    RAISE NOTICE '  2. 測試發送訊息功能';
    RAISE NOTICE '  3. 測試 Realtime 即時推送';
    RAISE NOTICE '  4. 測試軟刪除功能';
    RAISE NOTICE '  5. 監控查詢效能';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  🎉 部署成功！系統已就緒。';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
END $$;

-- =====================================================
-- 📝 索引與註解
-- =====================================================

COMMENT ON INDEX idx_conversations_item_buyer_unique IS
'唯一索引：確保同一物品、同一買家只能有一個對話，防止併發情況下的重複建立';

COMMENT ON INDEX idx_conversations_buyer_updated IS
'效能索引：加速買家查詢自己的對話列表（依更新時間排序）';

COMMENT ON INDEX idx_conversations_seller_updated IS
'效能索引：加速賣家查詢自己的對話列表（依更新時間排序）';

COMMENT ON INDEX idx_conversations_updated_at IS
'效能索引：加速對話時間排序查詢';

COMMENT ON INDEX idx_conversation_messages_unread IS
'複合索引：優化未讀訊息查詢（部分索引，只索引未讀訊息）';

COMMENT ON TRIGGER trigger_update_conversation_on_new_message ON public.conversation_messages IS
'自動觸發器：當新訊息插入時，自動更新對話的 updated_at 時間戳記';

-- =====================================================
-- 🎓 結束
-- =====================================================
-- 版本: 1.4 (Production Ready)
-- 最後更新: 2025-11-10
-- 維護建議:
--   - 定期監控索引使用率 (pg_stat_user_indexes)
--   - 檢查慢查詢並優化 (pg_stat_statements)
--   - 追蹤錯誤日誌
--   - 定期清理過期軟刪除資料 (可選)
-- =====================================================
