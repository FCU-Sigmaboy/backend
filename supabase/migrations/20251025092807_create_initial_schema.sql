-- =============================================
-- 生態交換平台資料庫結構
-- 建立日期: 2025-10-25
-- =============================================

-- 啟用必要的擴展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- =============================================
-- 第一層：基礎資料表
-- =============================================

-- 使用者主表
CREATE TABLE public.users (
                              id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                              nickname VARCHAR(50) NOT NULL UNIQUE,
                              profile_picture_url TEXT,
                              avg_rating NUMERIC(3, 2) DEFAULT 0.00 CHECK (avg_rating >= 0 AND avg_rating <= 5),
                              created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                              updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 主分類表
CREATE TABLE public.main_categories (
                                        id SERIAL PRIMARY KEY,
                                        name VARCHAR(50) NOT NULL UNIQUE,
                                        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================
-- 第二層：依賴基礎表的資料表
-- =============================================

-- 使用者詳細資料表
CREATE TABLE public.profiles (
                                 user_id UUID PRIMARY KEY,
                                 balance INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
                                 carbon_saved_kg NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (carbon_saved_kg >= 0),
                                 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

-- 使用者地點表
CREATE TABLE public.locations (
                                  id BIGSERIAL PRIMARY KEY,
                                  user_id UUID NOT NULL,
                                  coordinates GEOGRAPHY(Point, 4326) NOT NULL,
                                  type VARCHAR(50) CHECK (type IN ('家', '公司', '其他')),
                                  is_primary BOOLEAN NOT NULL DEFAULT false,
                                  formatted_address TEXT,
                                  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

-- 子分類表
CREATE TABLE public.sub_categories (
                                       id SERIAL PRIMARY KEY,
                                       main_category_id INTEGER NOT NULL,
                                       name VARCHAR(50) NOT NULL,
                                       default_carbon_value NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (default_carbon_value >= 0),
                                       created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                       FOREIGN KEY (main_category_id) REFERENCES public.main_categories(id) ON DELETE RESTRICT
);

-- =============================================
-- 第三層：物品與核心業務邏輯
-- =============================================

-- 物品表
CREATE TABLE public.items (
                              id BIGSERIAL PRIMARY KEY,
                              user_id UUID NOT NULL,
                              sub_category_id INTEGER NOT NULL,
                              location_id BIGINT NOT NULL,
                              title VARCHAR(50) NOT NULL,
                              description TEXT,
                              condition VARCHAR(20) NOT NULL CHECK (condition IN ('全新', '近全新', '良好', '普通', '需修理')),
                              listing_status BOOLEAN NOT NULL DEFAULT true,
                              price INTEGER NOT NULL DEFAULT 0 CHECK (price >= 0),
                              carbon_value NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (carbon_value >= 0),
                              image_urls TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
                              tags TEXT[] DEFAULT ARRAY[]::TEXT[],
                              created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                              updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                              FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
                              FOREIGN KEY (sub_category_id) REFERENCES public.sub_categories(id) ON DELETE RESTRICT,
                              FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE RESTRICT
);

-- =============================================
-- 第四層：交易與互動功能
-- =============================================

-- 交易表
CREATE TABLE public.transactions (
                                     id BIGSERIAL PRIMARY KEY,
                                     item_id BIGINT NOT NULL UNIQUE, -- 每件物品只能交易一次
                                     giver_id UUID NOT NULL,
                                     receiver_id UUID NOT NULL,
                                     points_amount INTEGER NOT NULL CHECK (points_amount >= 0),
                                     carbon_amount_kg NUMERIC(10, 2) NOT NULL CHECK (carbon_amount_kg >= 0),
                                     transaction_status VARCHAR(20) NOT NULL DEFAULT 'pending'
                                         CHECK (transaction_status IN ('pending', 'confirmed', 'in_progress', 'completed', 'cancelled')),
                                     completed_at TIMESTAMPTZ,
                                     created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                     updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                     FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE RESTRICT,
                                     FOREIGN KEY (giver_id) REFERENCES public.users(id) ON DELETE RESTRICT,
                                     FOREIGN KEY (receiver_id) REFERENCES public.users(id) ON DELETE RESTRICT,
                                     CHECK (giver_id != receiver_id) -- 不能自己跟自己交易
    );

-- 聊天室表
CREATE TABLE public.conversations (
                                      id BIGSERIAL PRIMARY KEY,
                                      item_id BIGINT NOT NULL,
                                      buyer_id UUID NOT NULL,
                                      seller_id UUID NOT NULL,
                                      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                      FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE,
                                      FOREIGN KEY (buyer_id) REFERENCES public.users(id) ON DELETE CASCADE,
                                      FOREIGN KEY (seller_id) REFERENCES public.users(id) ON DELETE CASCADE,
                                      UNIQUE(item_id, buyer_id, seller_id) -- 每個物品的買賣雙方只能有一個聊天室
);

-- 追蹤關係表
CREATE TABLE public.following (
                                  follower_id UUID NOT NULL,
                                  following_id UUID NOT NULL,
                                  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                  PRIMARY KEY (follower_id, following_id),
                                  FOREIGN KEY (follower_id) REFERENCES public.users(id) ON DELETE CASCADE,
                                  FOREIGN KEY (following_id) REFERENCES public.users(id) ON DELETE CASCADE,
                                  CHECK (follower_id != following_id) -- 不能追蹤自己
    );

-- 收藏表
CREATE TABLE public.favorites (
                                  user_id UUID NOT NULL,
                                  item_id BIGINT NOT NULL,
                                  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                  PRIMARY KEY (user_id, item_id),
                                  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
                                  FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE
);

-- =============================================
-- 第五層：依賴交易的功能
-- =============================================

-- 點數記錄表
CREATE TABLE public.point_logs (
                                   id BIGSERIAL PRIMARY KEY,
                                   user_id UUID NOT NULL,
                                   amount INTEGER NOT NULL, -- 正數表示增加，負數表示減少
                                   type VARCHAR(50) NOT NULL CHECK (type IN (
                                                                             'transaction_income', 'transaction_expense', 'daily_login',
                                                                             'quest_reward', 'initial_gift', 'admin_adjustment'
                                       )),
                                   transaction_id BIGINT,
                                   description TEXT,
                                   created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                   FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
                                   FOREIGN KEY (transaction_id) REFERENCES public.transactions(id) ON DELETE SET NULL
);

-- 評價表
CREATE TABLE public.ratings (
                                id BIGSERIAL PRIMARY KEY,
                                transaction_id BIGINT NOT NULL,
                                reviewer_id UUID NOT NULL,
                                reviewed_user_id UUID NOT NULL,
                                score SMALLINT NOT NULL CHECK (score >= 1 AND score <= 5),
                                comment TEXT,
                                created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                FOREIGN KEY (transaction_id) REFERENCES public.transactions(id) ON DELETE CASCADE,
                                FOREIGN KEY (reviewer_id) REFERENCES public.users(id) ON DELETE CASCADE,
                                FOREIGN KEY (reviewed_user_id) REFERENCES public.users(id) ON DELETE CASCADE,
                                UNIQUE(transaction_id, reviewer_id) -- 每個交易每個評價者只能評價一次
);

-- 聊天訊息表
CREATE TABLE public.conversation_messages (
                                              id BIGSERIAL PRIMARY KEY,
                                              conversation_id BIGINT NOT NULL,
                                              sender_id UUID NOT NULL,
                                              content TEXT NOT NULL,
                                              is_read BOOLEAN NOT NULL DEFAULT false,
                                              sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                              FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE,
                                              FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE CASCADE
);

-- =============================================
-- 索引優化
-- =============================================

-- 使用者相關索引
CREATE INDEX idx_users_nickname ON public.users(nickname);
CREATE INDEX idx_profiles_user_id ON public.profiles(user_id);
CREATE INDEX idx_locations_user_id ON public.locations(user_id);
CREATE INDEX idx_locations_coordinates ON public.locations USING GIST(coordinates);

-- 物品相關索引
CREATE INDEX idx_items_user_id ON public.items(user_id);
CREATE INDEX idx_items_sub_category_id ON public.items(sub_category_id);
CREATE INDEX idx_items_listing_status ON public.items(listing_status);
CREATE INDEX idx_items_created_at ON public.items(created_at DESC);
CREATE INDEX idx_items_price ON public.items(price);

-- 交易相關索引
CREATE INDEX idx_transactions_item_id ON public.transactions(item_id);
CREATE INDEX idx_transactions_giver_id ON public.transactions(giver_id);
CREATE INDEX idx_transactions_receiver_id ON public.transactions(receiver_id);
CREATE INDEX idx_transactions_status ON public.transactions(transaction_status);
CREATE INDEX idx_transactions_created_at ON public.transactions(created_at DESC);

-- 點數記錄索引
CREATE INDEX idx_point_logs_user_id ON public.point_logs(user_id);
CREATE INDEX idx_point_logs_created_at ON public.point_logs(created_at DESC);
CREATE INDEX idx_point_logs_transaction_id ON public.point_logs(transaction_id);

-- 聊天相關索引
CREATE INDEX idx_conversations_item_id ON public.conversations(item_id);
CREATE INDEX idx_conversations_buyer_id ON public.conversations(buyer_id);
CREATE INDEX idx_conversations_seller_id ON public.conversations(seller_id);
CREATE INDEX idx_conversation_messages_conversation_id ON public.conversation_messages(conversation_id);
CREATE INDEX idx_conversation_messages_sent_at ON public.conversation_messages(sent_at DESC);

-- 評價索引
CREATE INDEX idx_ratings_transaction_id ON public.ratings(transaction_id);
CREATE INDEX idx_ratings_reviewed_user_id ON public.ratings(reviewed_user_id);

-- 追蹤和收藏索引
CREATE INDEX idx_following_follower_id ON public.following(follower_id);
CREATE INDEX idx_following_following_id ON public.following(following_id);
CREATE INDEX idx_favorites_user_id ON public.favorites(user_id);
CREATE INDEX idx_favorites_item_id ON public.favorites(item_id);

-- =============================================
-- 觸發器設定（自動更新 updated_at）
-- =============================================

-- 建立通用的 updated_at 觸發器函數
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 為需要的表建立觸發器
CREATE TRIGGER trigger_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_locations_updated_at
    BEFORE UPDATE ON public.locations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_items_updated_at
    BEFORE UPDATE ON public.items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_transactions_updated_at
    BEFORE UPDATE ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_conversations_updated_at
    BEFORE UPDATE ON public.conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
