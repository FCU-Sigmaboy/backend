-- ####################################################################
-- ### 安全策略 (Row Level Security Policies) for User Data
-- ####################################################################

-- 政策 1: 任何人都可以讀取 "公開" 的 users 資料 (例如 nickname)
CREATE POLICY "Public can view public user info"
ON public.users FOR SELECT
                               USING ( true ); -- (注意: 如果您希望 users 資料更私密，可以修改此規則)

-- 政策 2: 使用者 "只能讀取" 自己的 profiles 資料 (例如 balance)
CREATE POLICY "Users can view their own profile details"
ON public.profiles FOR SELECT
                                  USING ( auth.uid() = user_id );

-- 政策 3: 使用者 "只能讀取" 自己的 locations 資料
CREATE POLICY "Users can view their own locations"
ON public.locations FOR SELECT
                                   USING ( auth.uid() = user_id );

-- 政策 4: 使用者 "只能更新" 自己的 users 資料 (例如 nickname)
CREATE POLICY "Users can update their own user info"
ON public.users FOR UPDATE
                               USING ( auth.uid() = id );

-- 政策 5: 使用者 "只能更新" 自己的 profiles 資料 (例如 balance)
CREATE POLICY "Users can update their own profile details"
ON public.profiles FOR UPDATE
                                  USING ( auth.uid() = user_id );

-- 政策 6: 使用者 "只能更新/新增/刪除" 自己的 locations 資料
CREATE POLICY "Users can manage their own locations"
ON public.locations FOR ALL -- 允許 INSERT, UPDATE, DELETE
USING ( auth.uid() = user_id );

-- ####################################################################
-- ### 安全策略 (Row Level Security Policies) for Items
-- ####################################################################

-- 政策 1: 任何人都可以 "讀取" 正在 "上架中" 的物品 (為了公開搜尋)
CREATE POLICY "Public can view listed items" -- (If not already created)
ON public.items FOR SELECT
USING ( listing_status = TRUE );

-- 政策 2: 使用者 "永遠" 可以 "讀取" "自己" 的所有物品 (無論狀態)
CREATE POLICY "Users can view their own items" -- (If not already created)
ON public.items FOR SELECT
USING ( auth.uid() = user_id );

-- 政策 3: 使用者只能更新/刪除自己的物品
CREATE POLICY "Users can manage their own items" -- (If not already created)
ON public.items FOR UPDATE, DELETE
USING ( auth.uid() = user_id );

-- 確保為 items 表啟用 RLS
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY; -- (If not already enabled)

-- ####################################################################
-- ### 安全策略 (Row Level Security Policies) for User Locations
-- ####################################################################

-- 政策 1: 使用者 "只能讀取" 自己的 locations 資料
CREATE POLICY "Users can view their own locations" -- (If not already created)
ON public.locations FOR SELECT
                                   USING ( auth.uid() = user_id );

-- 政策 2: 使用者 "只能更新/新增/刪除" 自己的 locations 資料
CREATE POLICY "Users can manage their own locations" -- (If not already created)
ON public.locations FOR ALL -- 允許 INSERT, UPDATE, DELETE
USING ( auth.uid() = user_id );

-- 確保為 locations 表啟用 RLS
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY; -- (If not already enabled)


-- ####################################################################
-- ### 安全策略 (Row Level Security Policies) for Following
-- ####################################################################

-- 政策 1: 使用者只能 "新增" 自己作為 follower 的追蹤關係
CREATE POLICY "Users can follow others"
ON public.following FOR INSERT
WITH CHECK ( auth.uid() = follower_id );

-- 政策 2: 使用者只能 "刪除" 自己作為 follower 的追蹤關係 (取消追蹤)
CREATE POLICY "Users can unfollow others"
ON public.following FOR DELETE
USING ( auth.uid() = follower_id );

-- 政策 3: 使用者可以 "讀取" 與自己相關的追蹤關係 (我追蹤誰 & 誰追蹤我)
CREATE POLICY "Users can view their own follow relationships"
ON public.following FOR SELECT
                                   USING ( auth.uid() = follower_id OR auth.uid() = following_id );

-- 確保為 following 表啟用 RLS
ALTER TABLE public.following ENABLE ROW LEVEL SECURITY; -- (If not already enabled)



-- ####################################################################
-- ### 安全策略 (Row Level Security Policies) for Favorites
-- ####################################################################

-- 政策 1: 使用者只能 "新增" 自己作為 user_id 的收藏關係
CREATE POLICY "Users can add items to their own favorites"
ON public.favorites FOR INSERT
WITH CHECK ( auth.uid() = user_id );

-- 政策 2: 使用者只能 "刪除" 自己作為 user_id 的收藏關係 (取消收藏)
CREATE POLICY "Users can remove items from their own favorites"
ON public.favorites FOR DELETE
USING ( auth.uid() = user_id );

-- 政策 3: 使用者只能 "讀取" 自己作為 user_id 的收藏關係
CREATE POLICY "Users can view their own favorites"
ON public.favorites FOR SELECT
                                   USING ( auth.uid() = user_id );

-- 確保為 favorites 表啟用 RLS
ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY; -- (If not already enabled)



-- ####################################################################
-- ### 安全策略 (Row Level Security Policies) for Conversations
-- ####################################################################

-- 政策 1: 使用者只能 "讀取" 自己參與的聊天室 (自己是買家或賣家)
CREATE POLICY "Users can view their own conversations"
ON public.conversations FOR SELECT
                                       USING ( auth.uid() = buyer_id OR auth.uid() = seller_id );

-- 政策 2: 使用者只能 "更新" 自己參與的聊天室 (例如 updated_at)
CREATE POLICY "Users can update their own conversations"
ON public.conversations FOR UPDATE
                                       USING ( auth.uid() = buyer_id OR auth.uid() = seller_id );

-- 政策 3: 使用者可以 "建立" 自己作為買家的聊天室
CREATE POLICY "Buyers can create conversations"
ON public.conversations FOR INSERT
WITH CHECK ( auth.uid() = buyer_id );

-- 確保為 conversations 表啟用 RLS
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY; -- (If not already enabled)


-- ####################################################################
-- ### 安全策略 (Row Level Security Policies) for Conversation Messages
-- ####################################################################

-- 政策 1: 使用者只能 "讀取" 自己參與的聊天室的訊息
CREATE POLICY "Users can view messages in their own conversations"
ON public.conversation_messages FOR SELECT
                                               USING (
                                               conversation_id IN (
                                               SELECT id FROM public.conversations
                                               WHERE auth.uid() = buyer_id OR auth.uid() = seller_id
                                               )
                                               );

-- 政策 2: 使用者只能 "新增" 訊息到自己參與的聊天室，且 sender_id 必須是自己
CREATE POLICY "Users can insert messages into their own conversations"
ON public.conversation_messages FOR INSERT
WITH CHECK (
  auth.uid() = sender_id -- 確保 sender 是自己
  AND conversation_id IN (
    SELECT id FROM public.conversations
    WHERE auth.uid() = buyer_id OR auth.uid() = seller_id -- 確保是自己的聊天室
  )
);

-- (通常不允許使用者刪除或修改訊息，因此不設定 DELETE/UPDATE 政策)

-- 確保為 conversation_messages 表啟用 RLS
ALTER TABLE public.conversation_messages ENABLE ROW LEVEL SECURITY; -- (If not already enabled)