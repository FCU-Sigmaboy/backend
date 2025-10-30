-- =============================================
-- 模組二：產品目錄 - 主分類與子分類
-- =============================================

-- 主分類 (包含所有欄位的單一 INSERT 語句)
INSERT INTO public.main_categories (id, name, icon, color, created_at)
VALUES
    (1, '流行服飾', 'bi bi-person-fill', '#ff6f61', now()),
    (2, '鞋包配件', 'bi bi-bag', '#e83e8c', now()),
    (3, '3C 電子', 'bi bi-phone', '#007bff', now()),
    (4, '家電用品', 'bi bi-house-door', '#28a745', now()),
    (5, '親子婦幼', 'bi bi-baby-carriage', '#6f42c1', now()),
    (6, '生活娛樂', 'bi bi-controller', '#fd7e14', now())
ON CONFLICT (id) DO UPDATE SET 
    name = EXCLUDED.name, 
    icon = EXCLUDED.icon, 
    color = EXCLUDED.color;

-- 子分類
INSERT INTO public.sub_categories (id, main_category_id, name, default_carbon_value, created_at)
VALUES
-- 流行服飾
(11, 1, '男性上著', 0.8, now()),
(12, 1, '男性下著', 0.9, now()),
(13, 1, '男性外套', 1.8, now()),
(14, 1, '女性上著', 0.8, now()),
(15, 1, '女性下著', 1.0, now()),
(16, 1, '女性外套', 1.7, now()),

-- 鞋包配件
(21, 2, '運動鞋', 1.2, now()),
(22, 2, '休閒鞋', 1.0, now()),
(23, 2, '皮鞋', 1.3, now()),
(24, 2, '靴子', 1.5, now()),
(25, 2, '後背包', 0.9, now()),
(26, 2, '帽子', 0.5, now()),

-- 3C 電子
(31, 3, '手機', 2.5, now()),
(32, 3, '平板電腦', 2.0, now()),
(33, 3, '筆記型電腦', 3.5, now()),
(34, 3, '桌上型電腦', 4.0, now()),
(35, 3, '電腦螢幕', 2.8, now()),
(36, 3, '耳機', 0.6, now()),

-- 家電用品
(41, 4, '廚房家電', 3.0, now()),
(42, 4, '季節家電', 2.8, now()),
(43, 4, '清潔家電', 3.2, now()),
(44, 4, '洗衣設備', 4.5, now()),
(45, 4, '個人護理家電', 1.5, now()),
(46, 4, '電視', 5.0, now()),

-- 親子婦幼
(51, 5, '孕婦用品', 0.7, now()),
(52, 5, '嬰幼兒服飾', 0.6, now()),
(53, 5, '益智玩具', 0.5, now()),
(54, 5, '模型與玩偶', 0.4, now()),
(55, 5, '外出用品', 2.0, now()),
(56, 5, '哺育用品', 0.8, now()),

-- 生活娛樂
(61, 6, '運動用品', 1.5, now()),
(62, 6, '戶外露營', 2.2, now()),
(63, 6, '樂器', 2.0, now()),
(64, 6, '文具', 0.3, now()),
(65, 6, '寵物用品', 1.0, now()),
(66, 6, '廚房用具', 1.2, now())
ON CONFLICT (id) DO NOTHING;

-- 重設序列值
SELECT setval('main_categories_id_seq', (SELECT MAX(id) FROM public.main_categories));
SELECT setval('sub_categories_id_seq', (SELECT MAX(id) FROM public.sub_categories));
