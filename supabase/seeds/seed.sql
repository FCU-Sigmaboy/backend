-- =============================================
-- 測試資料 (僅用於本地和 Staging 環境)
-- =============================================

-- 測試使用者
INSERT INTO auth.users (id,
                        email,
                        encrypted_password,
                        email_confirmed_at,
                        created_at,
                        updated_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'alice@example.com', crypt('password123', gen_salt('bf')), now(), now(),
        now()),
       ('22222222-2222-2222-2222-222222222222', 'bob@example.com', crypt('password123', gen_salt('bf')), now(), now(),
        now()),
       ('33333333-3333-3333-3333-333333333333', 'charlie@example.com', crypt('password123', gen_salt('bf')), now(),
        now(), now());

-- 同步到 public.users
INSERT INTO public.users (id, nickname, profile_picture_url)
VALUES ('11111111-1111-1111-1111-111111111111', 'Alice 環保達人', 'https://example.com/avatar1.jpg'),
       ('22222222-2222-2222-2222-222222222222', 'Bob 二手王', 'https://example.com/avatar2.jpg'),
       ('33333333-3333-3333-3333-333333333333', 'Charlie 減碳俠', 'https://example.com/avatar3.jpg');

-- 使用者資料
INSERT INTO public.profiles (user_id, balance, carbon_saved_kg)
VALUES ('11111111-1111-1111-1111-111111111111', 1500, 125.50),
       ('22222222-2222-2222-2222-222222222222', 2300, 89.20),
       ('33333333-3333-3333-3333-333333333333', 800, 203.75);

-- 地點資料
INSERT INTO public.locations (user_id, coordinates, type, is_primary, formatted_address)
VALUES ('11111111-1111-1111-1111-111111111111', ST_GeogFromText('POINT(121.5654 25.0330)'), '家', true,
        '台北市信義區市府路1號'),
       ('22222222-2222-2222-2222-222222222222', ST_GeogFromText('POINT(121.5168 25.0478)'), '家', true,
        '台北市中正區重慶南路一段122號'),
       ('33333333-3333-3333-3333-333333333333', ST_GeogFromText('POINT(121.5598 25.0855)'), '家', true,
        '台北市松山區南京東路四段2號');

-- 測試物品
INSERT INTO public.items (user_id, sub_category_id, location_id, title, description,
                          condition, price, carbon_value, tags)
VALUES ('11111111-1111-1111-1111-111111111111', 1, 1, 'iPhone 13 Pro', '九成新，無刮痕，原廠盒裝齊全', '近全新', 800,
        15.50, ARRAY ['蘋果', '手機', '5G']),
       ('22222222-2222-2222-2222-222222222222', 2, 2, 'MacBook Air M2', '輕度使用，適合學生', '良好', 1200, 45.20,
        ARRAY ['蘋果', '筆電', 'M2']),
       ('33333333-3333-3333-3333-333333333333', 6, 3, 'Uniqlo 羽絨外套', '全新未穿，吊牌未拆', '全新', 0, 8.20,
        ARRAY ['UNIQLO', '外套', '冬季']);
