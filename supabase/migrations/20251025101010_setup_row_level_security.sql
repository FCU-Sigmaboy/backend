-- =============================================
-- Row Level Security (RLS) 設定
-- =============================================

-- 啟用所有表的 RLS
ALTER TABLE public.users
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.point_logs
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ratings
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_messages
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.following
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.favorites
    ENABLE ROW LEVEL SECURITY;

-- =============================================
-- Users 表的 RLS 政策
-- =============================================

-- 所有人都可以讀取基本使用者資訊 (但不包含敏感資訊)
CREATE POLICY "Anyone can view public user profiles" ON public.users
    FOR SELECT USING (true);

-- 只有本人可以更新自己的資料
CREATE POLICY "Users can update own profile" ON public.users
    FOR UPDATE USING (auth.uid() = id);

-- =============================================
-- Profiles 表的 RLS 政策
-- =============================================

-- 只有本人可以查看自己的詳細資料
CREATE POLICY "Users can view own profile details" ON public.profiles
    FOR SELECT USING (auth.uid() = user_id);

-- 只有本人可以更新自己的資料
CREATE POLICY "Users can update own profile details" ON public.profiles
    FOR UPDATE USING (auth.uid() = user_id);

-- 註冊時自動建立 profile
CREATE POLICY "Users can insert own profile" ON public.profiles
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- =============================================
-- Locations 表的 RLS 政策
-- =============================================

-- 只有本人可以查看自己的地點
CREATE POLICY "Users can view own locations" ON public.locations
    FOR SELECT USING (auth.uid() = user_id);

-- 只有本人可以管理自己的地點
CREATE POLICY "Users can manage own locations" ON public.locations
    FOR ALL USING (auth.uid() = user_id);

-- =============================================
-- Items 表的 RLS 政策
-- =============================================

-- 所有人都可以查看上架的物品
CREATE POLICY "Anyone can view listed items" ON public.items
    FOR SELECT USING (listing_status = true);

-- 物品擁有者可以查看自己的所有物品 (包含下架的)
CREATE POLICY "Owners can view all own items" ON public.items
    FOR SELECT USING (auth.uid() = user_id);

-- 只有本人可以建立物品
CREATE POLICY "Users can create own items" ON public.items
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 只有本人可以更新自己的物品
CREATE POLICY "Users can update own items" ON public.items
    FOR UPDATE USING (auth.uid() = user_id);

-- 只有本人可以刪除自己的物品
CREATE POLICY "Users can delete own items" ON public.items
    FOR DELETE USING (auth.uid() = user_id);

-- =============================================
-- Transactions 表的 RLS 政策
-- =============================================

-- 交易參與者可以查看交易記錄
CREATE POLICY "Transaction participants can view transactions" ON public.transactions
    FOR SELECT USING (auth.uid() = giver_id OR auth.uid() = receiver_id);

-- 接收者可以建立交易請求
CREATE POLICY "Receivers can create transaction requests" ON public.transactions
    FOR INSERT WITH CHECK (auth.uid() = receiver_id);

-- 交易參與者可以更新交易狀態
CREATE POLICY "Transaction participants can update transactions" ON public.transactions
    FOR UPDATE USING (auth.uid() = giver_id OR auth.uid() = receiver_id);

-- =============================================
-- Point Logs 表的 RLS 政策
-- =============================================

-- 只有本人可以查看自己的點數記錄
CREATE POLICY "Users can view own point logs" ON public.point_logs
    FOR SELECT USING (auth.uid() = user_id);

-- =============================================
-- Ratings 表的 RLS 政策
-- =============================================

-- 所有人都可以查看評價 (但不包含評價者身份)
CREATE POLICY "Anyone can view ratings" ON public.ratings
    FOR SELECT USING (true);

-- 交易參與者可以新增評價
CREATE POLICY "Transaction participants can add ratings" ON public.ratings
    FOR INSERT WITH CHECK (
    auth.uid() = reviewer_id AND
    EXISTS (SELECT 1
            FROM public.transactions t
            WHERE t.id = transaction_id
              AND (t.giver_id = auth.uid() OR t.receiver_id = auth.uid())
              AND t.transaction_status = 'completed')
    );

-- =============================================
-- Conversations 表的 RLS 政策
-- =============================================

-- 對話參與者可以查看對話
CREATE POLICY "Conversation participants can view conversations" ON public.conversations
    FOR SELECT USING (auth.uid() = buyer_id OR auth.uid() = seller_id);

-- 潛在買家可以發起對話
CREATE POLICY "Buyers can initiate conversations" ON public.conversations
    FOR INSERT WITH CHECK (auth.uid() = buyer_id);

-- =============================================
-- Conversation Messages 表的 RLS 政策
-- =============================================

-- 對話參與者可以查看訊息
CREATE POLICY "Conversation participants can view messages" ON public.conversation_messages
    FOR SELECT USING (
    EXISTS (SELECT 1
            FROM public.conversations c
            WHERE c.id = conversation_id
              AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid()))
    );

-- 對話參與者可以發送訊息
CREATE POLICY "Conversation participants can send messages" ON public.conversation_messages
    FOR INSERT WITH CHECK (
    auth.uid() = sender_id AND
    EXISTS (SELECT 1
            FROM public.conversations c
            WHERE c.id = conversation_id
              AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid()))
    );

-- =============================================
-- Following 表的 RLS 政策
-- =============================================

-- 所有人都可以查看追蹤關係 (公開資訊)
CREATE POLICY "Anyone can view following relationships" ON public.following
    FOR SELECT USING (true);

-- 使用者可以管理自己的追蹤關係
CREATE POLICY "Users can manage own following" ON public.following
    FOR ALL USING (auth.uid() = follower_id);

-- =============================================
-- Favorites 表的 RLS 政策
-- =============================================

-- 只有本人可以查看自己的收藏
CREATE POLICY "Users can view own favorites" ON public.favorites
    FOR SELECT USING (auth.uid() = user_id);

-- 只有本人可以管理自己的收藏
CREATE POLICY "Users can manage own favorites" ON public.favorites
    FOR ALL USING (auth.uid() = user_id);

-- =============================================
-- 分類表不需要 RLS (公開資訊)
-- =============================================
-- main_categories 和 sub_categories 是公開資訊，所有人都可以讀取
