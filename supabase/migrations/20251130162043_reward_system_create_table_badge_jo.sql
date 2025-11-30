-- 新增表 1: badges (徽章定義表)
CREATE TABLE public.badges (
                               id VARCHAR(50) PRIMARY KEY,           -- badge_id (e.g., 'streak_7', 'seller_5')
                               name VARCHAR(50) NOT NULL,            -- 徽章名稱
                               icon VARCHAR(10) NOT NULL,            -- emoji 圖示
                               description TEXT NOT NULL,            -- 徽章說明
                               points_reward INTEGER NOT NULL DEFAULT 0 CHECK (points_reward >= 0),
                               rarity VARCHAR(20) NOT NULL CHECK (rarity IN ('Common', 'Uncommon', 'Rare', 'Epic', 'Legendary')),
                               category VARCHAR(50) NOT NULL CHECK (category IN ('streak', 'transaction', 'points', 'carbon', 'seasonal')),
                               threshold_value INTEGER NOT NULL,     -- 觸發門檻值 (天數/筆數/點數/kg)
                               threshold_type VARCHAR(20) NOT NULL CHECK (threshold_type IN ('days', 'count', 'points', 'kg')),
                               created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 新增表 2: user_badges (使用者徽章表)
CREATE TABLE public.user_badges (
                                    user_id UUID NOT NULL,
                                    badge_id VARCHAR(50) NOT NULL,
                                    earned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                    PRIMARY KEY (user_id, badge_id),
                                    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
                                    FOREIGN KEY (badge_id) REFERENCES public.badges(id) ON DELETE CASCADE
);

-- 索引優化
CREATE INDEX idx_user_badges_user_id ON public.user_badges(user_id);
CREATE INDEX idx_user_badges_earned_at ON public.user_badges(earned_at DESC);

-- 新增表 3: user_badge_progress (徽章進度追蹤)
CREATE TABLE public.user_badge_progress (
                                            user_id UUID NOT NULL,
                                            badge_id VARCHAR(50) NOT NULL,
                                            current_value INTEGER NOT NULL DEFAULT 0,  -- 當前進度值
                                            target_value INTEGER NOT NULL,             -- 目標值
                                            percentage NUMERIC(5, 2) GENERATED ALWAYS AS (
                                                CASE
                                                    WHEN target_value > 0 THEN (current_value::NUMERIC / target_value * 100)
                                                    ELSE 0
                                                    END
                                                ) STORED,
                                            last_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                                            PRIMARY KEY (user_id, badge_id),
                                            FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE,
                                            FOREIGN KEY (badge_id) REFERENCES public.badges(id) ON DELETE CASCADE,
                                            CHECK (current_value >= 0 AND target_value > 0)
);

-- 索引優化
CREATE INDEX idx_badge_progress_percentage ON public.user_badge_progress(percentage DESC);

-- 擴展 profiles 表 (新增統計欄位)
ALTER TABLE public.profiles
    ADD COLUMN total_sales_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN total_purchase_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN total_points_earned INTEGER NOT NULL DEFAULT 0;  -- 只計算賣出收入

-- 索引優化
CREATE INDEX idx_profiles_sales_count ON public.profiles(total_sales_count);
CREATE INDEX idx_profiles_purchase_count ON public.profiles(total_purchase_count);
CREATE INDEX idx_profiles_points_earned ON public.profiles(total_points_earned);

-- ============================================
-- 徽章資料 (Badge Data)
-- ============================================
-- 總計: 32 個徽章
-- - Streak: 6 個
-- - Transaction: 13 個 (銷售7 + 購買5 + 總交易2)
-- - Points: 7 個
-- - Carbon: 5 個
-- - Seasonal: 0 個 (預留之後新增)
-- ============================================

-- 插入所有徽章定義
INSERT INTO public.badges (id, name, icon, description, points_reward, rarity, category, threshold_value, threshold_type) VALUES
-- ============================================
-- A. Streak Badges (連續簽到類) - 6 個
-- ============================================
('streak_7',   '連續簽到達人', '🔥', '連續簽到7天',    20,  'Common',    'streak', 7,   'days'),
('streak_14',  '雙週堅持者',   '⭐', '連續簽到14天',   30,  'Uncommon',  'streak', 14,  'days'),
('streak_30',  '月度堅持者',   '🌟', '連續簽到30天',   50,  'Rare',      'streak', 30,  'days'),
('streak_60',  '雙月達人',     '💫', '連續簽到60天',   100, 'Rare',      'streak', 60,  'days'),
('streak_100', '傳奇簽到王',   '👑', '連續簽到100天',  200, 'Legendary', 'streak', 100, 'days'),
('streak_365', '年度簽到王',   '🏆', '連續簽到365天',  500, 'Legendary', 'streak', 365, 'days'),

-- ============================================
-- B. Transaction Badges (交易類) - 13 個
-- ============================================
-- B1. 銷售類 (Sales) - 7 個
('first_sale', '首次出售', '🎉', '完成第1筆銷售', 10,  'Common',   'transaction', 1,   'count'),
('seller_5',   '新手賣家', '📦', '完成5筆銷售',    20,  'Common',   'transaction', 5,   'count'),
('seller_10',  '活躍賣家', '💼', '完成10筆銷售',   30,  'Uncommon', 'transaction', 10,  'count'),
('seller_25',  '熟練賣家', '📊', '完成25筆銷售',   50,  'Uncommon', 'transaction', 25,  'count'),
('seller_50',  '專業賣家', '🏆', '完成50筆銷售',   100, 'Rare',     'transaction', 50,  'count'),
('seller_100', '頂級賣家', '💎', '完成100筆銷售',  200, 'Epic',     'transaction', 100, 'count'),

-- B2. 購買類 (Purchase) - 5 個
('first_purchase', '首次購買', '🛒', '完成第一筆購買', 10,  'Common',   'transaction', 1,  'count'),
('buyer_5',        '購物新手', '🛍️', '完成5筆購買',    15,  'Common',   'transaction', 5,  'count'),
('buyer_10',       '購物達人', '🛒', '完成10筆購買',   30,  'Uncommon', 'transaction', 10, 'count'),
('buyer_25',       '購物專家', '🎁', '完成25筆購買',   50,  'Uncommon', 'transaction', 25, 'count'),
('buyer_50',       '購物大師', '🏅', '完成50筆購買',   100, 'Rare',     'transaction', 50, 'count'),

-- B3. 總交易類 (Total Transactions) - 2 個
('transaction_100', '百筆交易', '⚡', '累積完成100筆交易', 150, 'Rare', 'transaction', 100, 'count'),
('transaction_500', '五百交易', '🌟', '累積完成500筆交易', 300, 'Epic', 'transaction', 500, 'count'),

-- ============================================
-- C. Points Accumulation (點數累積類) - 7 個
-- ============================================
-- 註: 只計算銷售賺取的點數 (total_points_earned)
('points_500',   '五百點達人',   '💰', '累積賺取500點',   20,   'Common',    'points', 500,   'points'),
('points_1000',  '千點富翁',     '💵', '累積賺取1000點',  50,   'Uncommon',  'points', 1000,  'points'),
('points_2500',  '兩千五百點',   '💸', '累積賺取2500點',  100,  'Uncommon',  'points', 2500,  'points'),
('points_5000',  '萬點大亨',     '💎', '累積賺取5000點',  200,  'Rare',      'points', 5000,  'points'),
('points_10000', '萬點富翁',     '💍', '累積賺取10000點', 300,  'Rare',      'points', 10000, 'points'),
('points_25000', '兩萬五千點',   '👑', '累積賺取25000點', 500,  'Epic',      'points', 25000, 'points'),
('points_50000', '五萬點傳奇',   '🌟', '累積賺取50000點', 1000, 'Legendary', 'points', 50000, 'points'),

-- ============================================
-- D. Carbon Footprint Badges (環保碳足跡類) - 5 個
-- ============================================
-- 註: 透過二手交易減少的碳排放量 (單位: kg)
('carbon_10',  '環保新手', '🌿', '減少10公斤碳排放',  20,  'Common',    'carbon', 10,  'kg'),
('carbon_50',  '環保達人', '🌳', '減少50公斤碳排放',  50,  'Uncommon',  'carbon', 50,  'kg'),
('carbon_100', '環保高手', '🌲', '減少100公斤碳排放', 100, 'Rare',      'carbon', 100, 'kg'),
('carbon_200', '環保大師', '🌍', '減少200公斤碳排放', 200, 'Epic',      'carbon', 200, 'kg'),
('carbon_500', '環保傳奇', '🌎', '減少500公斤碳排放', 500, 'Legendary', 'carbon', 500, 'kg');

-- ============================================
-- E. Seasonal Badges (季節性徽章)
-- ============================================
-- 預留給未來季節性活動徽章
-- 例如: 春節特別徽章、萬聖節徽章、聖誕節徽章等
