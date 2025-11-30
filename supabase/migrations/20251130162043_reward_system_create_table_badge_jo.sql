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
CREATE INDEX idx_badge_progress_user_id ON public.user_badge_progress(user_id);
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