-- =============================================
-- 模組二：產品目錄 - 主分類與子分類
-- =============================================

-- 新增主分類 icon 和 color
INSERT INTO public.main_categories (id, icon, color)
VALUES
(1, 'bi bi-phone', '#007bff'),
(2, 'bi bi-bag-heart', '#e83e8c'),
(3, 'bi bi-house-door', '#28a745'),
(4, 'bi bi-book', '#ffc107'),
(5, 'bi bi-bicycle', '#17a2b8'),
(6, 'bi bi-brush', '#ff6f61'),
(7, 'bi bi-controller', '#fd7e14'),
(8, 'bi bi-box', '#6c757d')
ON CONFLICT (id) DO NOTHING;

-- 主分類
INSERT INTO public.main_categories (id, name, created_at)
VALUES (1, '流行服飾 (Fashion Apparel)', now()),
       (2, '鞋包配件 (Shoes, Bags & Accessories)', now()),
       (3, '3C 電子 (Electronics)', now()),
       (4, '家電用品 (Home Appliances)', now()),
       (5, '親子婦幼 (Mom & Baby)', now()),
       (6, '生活娛樂 (Lifestyle & Hobbies)', now())
ON CONFLICT (id) DO NOTHING;

-- 子分類
INSERT INTO public.sub_categories (id, main_category_id, name, default_carbon_value, created_at)
VALUES
-- 流行服飾
(1, 1, '男性上著 (Men''s Tops)', 0.8, now()),
(7, 1, '男性下著 (Men''s Bottoms)', 0.9, now()),
(13, 1, '男性外套 (Men''s Outerwear)', 1.8, now()),
(19, 1, '女性上著 (Women''s Tops)', 0.8, now()),
(25, 1, '女性下著 (Women''s Bottoms)', 1.0, now()),
(31, 1, '女性外套 (Women''s Outerwear)', 1.7, now()),

-- 鞋包配件
(2, 2, '運動鞋 (Sneakers)', 1.2, now()),
(8, 2, '休閒鞋 (Casual Shoes)', 1.0, now()),
(14, 2, '皮鞋 (Leather Shoes)', 1.3, now()),
(20, 2, '靴子 (Boots)', 1.5, now()),
(26, 2, '後背包 (Backpacks)', 0.9, now()),
(32, 2, '帽子 (Hats)', 0.5, now()),

-- 3C 電子
(3, 3, '手機 (Mobile Phones)', 2.5, now()),
(9, 3, '平板電腦 (Tablets)', 2.0, now()),
(15, 3, '筆記型電腦 (Laptops)', 3.5, now()),
(21, 3, '桌上型電腦 (Desktop Computers)', 4.0, now()),
(27, 3, '電腦螢幕 (Monitors)', 2.8, now()),
(33, 3, '耳機 (Headphones)', 0.6, now()),

-- 家電用品
(4, 4, '廚房家電 (Kitchen Appliances)', 3.0, now()),
(10, 4, '季節家電 (Seasonal Appliances)', 2.8, now()),
(16, 4, '清潔家電 (Cleaning Appliances)', 3.2, now()),
(22, 4, '洗衣設備 (Laundry Appliances)', 4.5, now()),
(28, 4, '個人護理家電 (Personal Care Appliances)', 1.5, now()),
(34, 4, '電視 (Televisions)', 5.0, now()),

-- 親子婦幼
(5, 5, '孕婦用品 (Maternity)', 0.7, now()),
(11, 5, '嬰幼兒服飾 (Baby & Kids'' Clothing)', 0.6, now()),
(17, 5, '益智玩具 (Educational Toys)', 0.5, now()),
(23, 5, '模型與玩偶 (Models & Dolls)', 0.4, now()),
(29, 5, '外出用品 (Strollers & Gear)', 2.0, now()),
(35, 5, '哺育用品 (Feeding & Nursing)', 0.8, now()),

-- 生活娛樂
(6, 6, '運動用品 (Sports Equipment)', 1.5, now()),
(12, 6, '戶外露營 (Camping & Hiking)', 2.2, now()),
(18, 6, '樂器 (Musical Instruments)', 2.0, now()),
(24, 6, '文具 (Stationery)', 0.3, now()),
(30, 6, '寵物用品 (Pet Supplies)', 1.0, now()),
(36, 6, '廚房用具 (Cookware)', 1.2, now())
ON CONFLICT (id) DO NOTHING;

-- 重設序列值
SELECT setval('main_categories_id_seq', (SELECT MAX(id) FROM public.main_categories));
SELECT setval('sub_categories_id_seq', (SELECT MAX(id) FROM public.sub_categories));
